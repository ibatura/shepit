import Foundation
import SQLite3
import Testing
@testable import ShepitCore

// Numbered upgrades (statistics design §6): changes to tables an older file already has.
struct SQLiteFileTests {
    private let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    private var file: URL { folder.appending(path: "test.sqlite") }

    private func open(_ upgrades: [String]) -> SQLiteFile {
        SQLiteFile(file: file, schema: ["CREATE TABLE IF NOT EXISTS t (a INTEGER)"], upgrades: upgrades)
    }

    /// The file as it is, read without its schema or upgrades.
    private func read(_ sql: String) throws -> [Int] {
        try SQLiteFile(file: file, schema: []).rows(sql) { $0.int(0) }
    }

    @Test func aNewFileRunsTheSchemaAndEveryUpgrade() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try open(["ALTER TABLE t ADD COLUMN b INTEGER", "ALTER TABLE t ADD COLUMN c INTEGER"]).run("INSERT INTO t (a, b, c) VALUES (1, 2, 3)")
        #expect(try read("SELECT version FROM schema_version") == [3])
        #expect(try read("SELECT a + b + c FROM t") == [6])
    }

    @Test func anOlderFileRunsOnlyTheUpgradesItLacksAndOnlyOnce() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try SQLiteFile(file: file, schema: ["CREATE TABLE IF NOT EXISTS t (a INTEGER)"]).run("INSERT INTO t (a) VALUES (1)") // no version yet
        try open(["ALTER TABLE t ADD COLUMN b INTEGER"]).run("UPDATE t SET b = 2")
        #expect(try read("SELECT version FROM schema_version") == [2])
        // Adding b again would fail ("duplicate column name"), so each open below runs upgrade 3 at most.
        try open(["ALTER TABLE t ADD COLUMN b INTEGER", "ALTER TABLE t ADD COLUMN c INTEGER DEFAULT 3"]).run("UPDATE t SET a = a")
        try open(["ALTER TABLE t ADD COLUMN b INTEGER", "ALTER TABLE t ADD COLUMN c INTEGER DEFAULT 3"]).run("UPDATE t SET a = a")
        #expect(try read("SELECT version FROM schema_version") == [3])
        #expect(try read("SELECT a + b + c FROM t") == [6])
    }

    @Test func aFailedUpgradeChangesNothingAndIsTriedAgainOnTheNextUse() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let sqlite = open(["INSERT INTO t (a) VALUES (1); ALTER TABLE missing ADD COLUMN b INTEGER"])
        #expect(throws: SQLiteFile.Failure.self) { try sqlite.run("INSERT INTO t (a) VALUES (2)") }
        #expect(try read("SELECT count(*) FROM t") == [0])
        #expect(try read("SELECT version FROM schema_version") == [1])
        try SQLiteFile(file: file, schema: []).run("CREATE TABLE missing (a INTEGER)")
        try sqlite.run("INSERT INTO t (a) VALUES (2)")
        #expect(try read("SELECT a FROM t ORDER BY a") == [1, 2])
        #expect(try read("SELECT version FROM schema_version") == [2])
    }

    @Test func aTextFunctionIsCalledFromSQLAndNullStaysNull() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let sqlite = SQLiteFile(file: file, schema: ["CREATE TABLE IF NOT EXISTS t (a TEXT)"],
                                functions: ["twice": { $0.isEmpty ? nil : $0 + $0 }])
        try sqlite.run("INSERT INTO t (a) VALUES ('ab'), (''), (NULL)")
        #expect(try sqlite.rows("SELECT twice(a) FROM t ORDER BY rowid") { $0.text(0) ?? "NULL" } == ["abab", "NULL", "NULL"])
    }

    /// Query plans design §7.5: a transaction that reads, then writes, waits for another connection's write instead of
    /// failing at once with "database is locked" (SQLite skips the busy timeout for a reader that asks for the write lock).
    @Test func aTransactionWaitsForAnotherConnectionsWrite() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let sqlite = open([])
        try sqlite.run("INSERT INTO t (a) VALUES (1)")
        var handle: OpaquePointer?
        guard sqlite3_open(file.path, &handle) == SQLITE_OK else { throw CocoaError(.fileReadUnknown) }
        nonisolated(unsafe) let other = handle
        #expect(sqlite3_exec(other, "BEGIN IMMEDIATE; INSERT INTO t (a) VALUES (2)", nil, nil, nil) == SQLITE_OK)
        let committed = DispatchSemaphore(value: 0)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
            sqlite3_exec(other, "COMMIT", nil, nil, nil)
            committed.signal()
        }
        defer {
            committed.wait() // closed only after the commit, also when the transaction failed at once
            sqlite3_close(other)
        }
        try sqlite.transaction {
            #expect(try sqlite.rows("SELECT count(*) FROM t") { $0.int(0) } == [2])
            try sqlite.run("INSERT INTO t (a) VALUES (3)")
        }
        #expect(try read("SELECT a FROM t ORDER BY a") == [1, 2, 3])
    }
}
