import Foundation
import SQLite3
import Testing
@testable import ShepitCore

struct StatsDatabaseTests {
    private func makeDatabase() -> (StatsDatabase, URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        return (StatsDatabase(file: dir.appending(path: "stats.sqlite")), dir)
    }

    @Test func insertAndReadBackEveryField() throws {
        let (db, dir) = makeDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }
        let rows = [statsRow(terms: ["Kubernetes", "GitHub"]), statsRow("2026-10-21 09:00:00", outcome: .empty, app: nil, detected: nil)]
        for row in rows { try db.insert(row) }
        #expect(try db.dictations(in: nil) == rows)
    }

    @Test func rangeFilterUsesHalfOpenIntervals() throws {
        let (db, dir) = makeDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }
        let early = statsRow("2026-10-20 10:00:00")
        let late = statsRow("2026-10-21 10:00:00")
        try db.insert(early)
        try db.insert(late)
        #expect(try db.dictations(in: DateInterval(start: early.time, end: late.time)) == [early])
    }

    @Test func clearDeletesTheDatabaseAndItCanBeUsedAgain() throws {
        let (db, dir) = makeDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }
        try db.insert(statsRow())
        try db.insertMeeting(meetingRow())
        try db.insertModelLoad(engine: EngineChoice(engine: .whispercpp, model: "large-v3"), seconds: 1.2, residentMB: 3500, at: .now)
        #expect(FileManager.default.fileExists(atPath: db.file.path))
        try db.clear()
        #expect(!FileManager.default.fileExists(atPath: db.file.path))
        #expect(try db.dictations(in: nil).isEmpty)
        #expect(try db.meetings(in: nil).isEmpty)
    }

    @Test func meetingsInsertAndReadBackWithRange() throws {
        let (db, dir) = makeDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }
        let early = meetingRow("2026-10-20 10:00:00")
        let late = meetingRow("2026-10-21 10:00:00", speakers: nil, diarization: nil, failed: 0) // no speaker step
        try db.insertMeeting(early)
        try db.insertMeeting(late)
        #expect(try db.meetings(in: nil) == [early, late])
        #expect(try db.meetings(in: DateInterval(start: early.start, end: late.start)) == [early])
    }

    @Test func phase2DatabaseGetsTheMeetingsTableOnOpen() throws {
        let (db, dir) = makeDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var handle: OpaquePointer?
        #expect(sqlite3_open(db.file.path, &handle) == SQLITE_OK)
        #expect(sqlite3_exec(handle, "CREATE TABLE dictations (time REAL NOT NULL, tz_offset INTEGER NOT NULL, outcome TEXT NOT NULL)", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(handle)
        try db.insertMeeting(meetingRow())
        #expect(try db.meetings(in: nil).count == 1)
    }

    /// No transcript text and no speaker names: the meetings table holds numbers and the engine only.
    @Test func meetingsTableHasNoTextColumnsBeyondTheEngine() throws {
        let (db, dir) = makeDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try db.meetings(in: nil)
        var handle: OpaquePointer?
        #expect(sqlite3_open(db.file.path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }
        var statement: OpaquePointer?
        #expect(sqlite3_prepare_v2(handle, "SELECT name, type FROM pragma_table_info('meetings')", -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        var columns: [String: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            columns[String(cString: sqlite3_column_text(statement, 0))] = String(cString: sqlite3_column_text(statement, 1))
        }
        #expect(columns.filter { $0.value == "TEXT" }.keys.sorted() == ["engine", "model"])
        #expect(columns.keys.sorted() == ["diarization_seconds", "duration_seconds", "engine", "failed_chunks", "model", "speakers",
                                          "time", "words_call", "words_mine"])
    }
}
