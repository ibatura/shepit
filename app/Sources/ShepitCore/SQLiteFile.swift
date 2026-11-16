import Foundation
import SQLite3

/// One SQLite file, opened on first use with its schema (`CREATE … IF NOT EXISTS`, so older files get new tables on open).
/// Only `run` creates a missing file: reads find nothing in it and `runIfExists` leaves it missing, so a cleared store
/// stays deleted until something is written. Shared by `StatsDatabase`, `MeetingStore` and `DictationStore`.
final class SQLiteFile {
    struct Failure: LocalizedError, CustomStringConvertible {
        let description: String
        var errorDescription: String? { description }
    }

    let file: URL
    private let schema: [String]
    private var db: OpaquePointer?

    init(file: URL, schema: [String]) {
        self.file = file
        self.schema = schema
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
        for sql in schema {
            guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
                let failure = error(handle)
                sqlite3_close(handle) // not cached: the next call retries the schema
                throw failure
            }
        }
        db = handle
        return handle
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
