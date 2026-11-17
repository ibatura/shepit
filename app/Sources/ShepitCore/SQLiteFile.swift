import Foundation
import SQLite3

/// One SQLite file, opened on first use with its schema (`CREATE … IF NOT EXISTS`, so older files get new tables on open)
/// and its upgrades (changes to tables an older file already has). Only `run` creates a missing file: reads find nothing
/// in it and `runIfExists` leaves it missing, so a cleared store stays deleted until something is written. Shared by
/// `StatsDatabase`, `MeetingStore` and `DictationStore`.
final class SQLiteFile {
    struct Failure: LocalizedError, CustomStringConvertible {
        let description: String
        var errorDescription: String? { description }
    }

    let file: URL
    private let schema: [String]
    /// Upgrade 2, 3…: each runs once, after the schema, with the version it brings in the file's `schema_version` table
    /// (version 1 when the file has none), all in one transaction. The schema stays version 1's layout, since it runs
    /// first: a schema line can't use a column an upgrade adds. A failed upgrade changes nothing and fails the open, so
    /// the file isn't used until it runs on a later use.
    private let upgrades: [String]
    /// SQL functions of one text argument, for what SQLite can't do itself (folding Cyrillic case); NULL in, NULL out.
    private let functions: [String: (String) -> String?]
    private var db: OpaquePointer?

    init(file: URL, schema: [String], upgrades: [String] = [], functions: [String: (String) -> String?] = [:]) {
        self.file = file
        self.schema = schema
        self.upgrades = upgrades
        self.functions = functions
    }

    deinit {
        sqlite3_close(db)
    }

    /// Rows changed by the last INSERT, UPDATE or DELETE.
    var changes: Int { db.map { Int(sqlite3_changes($0)) } ?? 0 }

    /// A write; creates the file with its schema when it is missing.
    func run(_ sql: String, _ values: [Any?] = []) throws {
        try execute(try existing() ?? open(), sql, values)
    }

    /// A change that means nothing for a missing file (a delete): it leaves the file missing.
    func runIfExists(_ sql: String, _ values: [Any?] = []) throws {
        guard let db = try existing() else { return }
        try execute(db, sql, values)
    }

    /// One result row: its columns by index.
    struct Row {
        fileprivate let statement: OpaquePointer

        func text(_ i: Int32) -> String? { sqlite3_column_text(statement, i).map { String(cString: $0) } }
        func double(_ i: Int32) -> Double { sqlite3_column_double(statement, i) }
        func int(_ i: Int32) -> Int { Int(sqlite3_column_int64(statement, i)) }
        func isNull(_ i: Int32) -> Bool { sqlite3_column_type(statement, i) == SQLITE_NULL }
    }

    /// The rows `sql` gives, none for a missing file; `read` returns nil to skip one.
    func rows<T>(_ sql: String, _ values: [Any?] = [], read: (Row) -> T?) throws -> [T] {
        guard let db = try existing() else { return [] }
        let statement = try prepare(db, sql, values)
        defer { sqlite3_finalize(statement) }
        var rows: [T] = []
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            if let row = read(Row(statement: statement)) { rows.append(row) }
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw error(db) } // don't pass a truncated read off as complete
        return rows
    }

    /// Runs `body` as one change: all of it is kept, or none when it throws. Nests.
    func transaction<T>(_ body: () throws -> T) throws -> T {
        try run("SAVEPOINT change")
        do {
            let result = try body()
            try run("RELEASE change")
            return result
        } catch {
            try? run("ROLLBACK TO change")
            try? run("RELEASE change")
            throw error
        }
    }

    /// Deletes the file and its journal; the next use creates it again.
    func delete() throws {
        sqlite3_close(db)
        db = nil
        for suffix in ["", "-wal", "-shm", "-journal"] {
            let path = file.path + suffix
            if FileManager.default.fileExists(atPath: path) { try FileManager.default.removeItem(atPath: path) }
        }
    }

    /// The connection to the file, nil when it is missing. A file deleted under an open connection would take writes
    /// nobody reads again, so that connection is closed.
    private func existing() throws -> OpaquePointer? {
        guard FileManager.default.fileExists(atPath: file.path) else {
            sqlite3_close(db)
            db = nil
            return nil
        }
        return try db ?? open()
    }

    private func open() throws -> OpaquePointer {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        var handle: OpaquePointer?
        guard sqlite3_open(file.path, &handle) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open"
            sqlite3_close(handle)
            throw Failure(description: "\(file.lastPathComponent): \(message)")
        }
        do {
            for (name, body) in functions { try register(handle, name, body) }
            for sql in schema { try exec(handle, sql) }
            try upgrade(handle)
        } catch {
            sqlite3_close(handle) // not cached: the next call retries the schema and the upgrades
            throw error
        }
        db = handle
        return handle
    }

    private func upgrade(_ handle: OpaquePointer) throws {
        guard !upgrades.isEmpty else { return }
        try exec(handle, "CREATE TABLE IF NOT EXISTS schema_version (version INTEGER NOT NULL)")
        try exec(handle, "INSERT INTO schema_version (version) SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM schema_version)")
        guard try version(handle) <= upgrades.count else { return }
        try exec(handle, "BEGIN IMMEDIATE")
        do {
            // Read again under the write lock: another process opening the file may have upgraded it meanwhile.
            let current = try version(handle)
            for (index, sql) in upgrades.enumerated() where index + 2 > current {
                try exec(handle, "\(sql); UPDATE schema_version SET version = \(index + 2)")
            }
            try exec(handle, "COMMIT")
        } catch {
            sqlite3_exec(handle, "ROLLBACK", nil, nil, nil)
            throw error
        }
    }

    private final class TextFunction {
        let body: (String) -> String?
        init(_ body: @escaping (String) -> String?) { self.body = body }
    }

    private func register(_ handle: OpaquePointer, _ name: String, _ body: @escaping (String) -> String?) throws {
        let box = Unmanaged.passRetained(TextFunction(body)).toOpaque() // released by SQLite when the connection closes
        let result = sqlite3_create_function_v2(handle, name, 1, SQLITE_UTF8 | SQLITE_DETERMINISTIC, box, { context, _, arguments in
            let function = Unmanaged<TextFunction>.fromOpaque(sqlite3_user_data(context)).takeUnretainedValue()
            guard let argument = arguments?[0], let text = sqlite3_value_text(argument),
                  let value = function.body(String(cString: text)) else { return sqlite3_result_null(context) }
            sqlite3_result_text(context, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) // SQLITE_TRANSIENT
        }, nil, nil, { Unmanaged<TextFunction>.fromOpaque($0!).release() })
        guard result == SQLITE_OK else { throw error(handle) }
    }

    private func version(_ handle: OpaquePointer) throws -> Int {
        let statement = try prepare(handle, "SELECT max(version) FROM schema_version", [])
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw error(handle) }
        return Int(sqlite3_column_int64(statement, 0))
    }

    /// Runs `sql` as it is, several statements included (`execute` runs one, with values).
    private func exec(_ handle: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw error(handle) }
    }

    private func execute(_ db: OpaquePointer, _ sql: String, _ values: [Any?]) throws {
        let statement = try prepare(db, sql, values)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw error(db) }
    }

    private func prepare(_ db: OpaquePointer, _ sql: String, _ values: [Any?]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw error(db) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self) // SQLITE_TRANSIENT: SQLite copies the text
        for (index, value) in values.enumerated() {
            let i = Int32(index + 1)
            switch value {
            case let v as Double: sqlite3_bind_double(statement, i, v)
            case let v as Int: sqlite3_bind_int64(statement, i, Int64(v))
            case let v as Int64: sqlite3_bind_int64(statement, i, v)
            case let v as String: sqlite3_bind_text(statement, i, v, -1, transient)
            default: sqlite3_bind_null(statement, i)
            }
        }
        return statement
    }

    private func error(_ db: OpaquePointer) -> Failure {
        Failure(description: "\(file.lastPathComponent): \(String(cString: sqlite3_errmsg(db)))")
    }
}
