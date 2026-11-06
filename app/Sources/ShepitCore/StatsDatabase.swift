import Foundation
import SQLite3

/// stats.sqlite (`05-statistics.md` §1): one row per dictation attempt, per meeting and per model load.
/// Numbers and names only; nothing dictated is ever written here.
public final class StatsDatabase {
    public struct DatabaseError: Error, CustomStringConvertible {
        public let description: String
    }

    public let file: URL
    private var db: OpaquePointer?

    public init(file: URL) {
        self.file = file
    }

    deinit {
        sqlite3_close(db)
    }

    public func insert(_ row: DictationRow) throws {
        let terms = String(decoding: try JSONSerialization.data(withJSONObject: row.replacedTerms), as: UTF8.self)
        try run("""
            INSERT INTO dictations (time, tz_offset, outcome, audio_seconds, wait_seconds, words, characters, engine, model,
              language_requested, language_detected, app_bundle_id, app_name, replacements, replaced_terms, preview_requests)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [row.time.timeIntervalSince1970, row.tzOffset, row.outcome.rawValue, row.audioSeconds, row.waitSeconds, row.words,
                  row.characters, row.engine, row.model, row.languageRequested, row.languageDetected, row.appBundleID, row.appName,
                  row.replacements, terms, row.previewRequests])
    }

    public func insertModelLoad(engine: EngineChoice, seconds: Double, residentMB: Double?, at time: Date) throws {
        try run("INSERT INTO model_events (time, engine, model, load_seconds, resident_mb) VALUES (?, ?, ?, ?, ?)",
                [time.timeIntervalSince1970, engine.engine.rawValue, engine.model, seconds, residentMB])
    }

    public func insertMeeting(_ record: MeetingRecord) throws {
        try run("""
            INSERT INTO meetings (time, duration_seconds, words_mine, words_call, speakers, engine, model, diarization_seconds, failed_chunks)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [record.start.timeIntervalSince1970, record.duration, record.wordsMine, record.wordsCall, record.speakers,
                  record.engine.engine.rawValue, record.engine.model, record.diarizationSeconds, record.failedChunks])
    }

    /// Meetings that started in `range` (all of them when nil), oldest first.
    public func meetings(in range: DateInterval?) throws -> [MeetingRecord] {
        let start = range?.start.timeIntervalSince1970 ?? -.greatestFiniteMagnitude
        let end = range?.end.timeIntervalSince1970 ?? .greatestFiniteMagnitude
        let statement = try prepare("""
            SELECT time, duration_seconds, words_mine, words_call, speakers, engine, model, diarization_seconds, failed_chunks
            FROM meetings WHERE time >= ? AND time < ? ORDER BY time
            """, [start, end])
        defer { sqlite3_finalize(statement) }
        var rows: [MeetingRecord] = []
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            func text(_ i: Int32) -> String { sqlite3_column_text(statement, i).map { String(cString: $0) } ?? "" }
            func optional<T>(_ i: Int32, _ read: (Int32) -> T) -> T? { sqlite3_column_type(statement, i) == SQLITE_NULL ? nil : read(i) }
            rows.append(MeetingRecord(
                start: Date(timeIntervalSince1970: sqlite3_column_double(statement, 0)), duration: sqlite3_column_double(statement, 1),
                wordsMine: Int(sqlite3_column_int64(statement, 2)), wordsCall: Int(sqlite3_column_int64(statement, 3)),
                speakers: optional(4) { Int(sqlite3_column_int64(statement, $0)) },
                engine: EngineChoice(engine: EngineID(rawValue: text(5)) ?? .whispercpp, model: text(6)),
                diarizationSeconds: optional(7) { sqlite3_column_double(statement, $0) },
                failedChunks: Int(sqlite3_column_int64(statement, 8))))
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw error(try open()) }
        return rows
    }

    /// Attempts in `range` (all of them when nil), oldest first.
    public func dictations(in range: DateInterval?) throws -> [DictationRow] {
        let start = range?.start.timeIntervalSince1970 ?? -.greatestFiniteMagnitude
        let end = range?.end.timeIntervalSince1970 ?? .greatestFiniteMagnitude
        let statement = try prepare("""
            SELECT time, tz_offset, outcome, audio_seconds, wait_seconds, words, characters, engine, model, language_requested,
              language_detected, app_bundle_id, app_name, replaced_terms, preview_requests
            FROM dictations WHERE time >= ? AND time < ? ORDER BY time
            """, [start, end])
        defer { sqlite3_finalize(statement) }
        var rows: [DictationRow] = []
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            func text(_ i: Int32) -> String? { sqlite3_column_text(statement, i).map { String(cString: $0) } }
            let terms = text(13).flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String] } ?? []
            rows.append(DictationRow(
                time: Date(timeIntervalSince1970: sqlite3_column_double(statement, 0)), tzOffset: Int(sqlite3_column_int64(statement, 1)),
                outcome: DictationOutcome(rawValue: text(2) ?? "") ?? .failed, audioSeconds: sqlite3_column_double(statement, 3),
                waitSeconds: sqlite3_column_double(statement, 4), words: Int(sqlite3_column_int64(statement, 5)),
                characters: Int(sqlite3_column_int64(statement, 6)), engine: text(7) ?? "", model: text(8) ?? "",
                languageRequested: text(9) ?? "", languageDetected: text(10), appBundleID: text(11), appName: text(12),
                replacedTerms: terms, previewRequests: Int(sqlite3_column_int64(statement, 14))))
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw error(try open()) } // don't pass a truncated read off as complete
        return rows
    }

    /// Clear statistics…: deletes the database file.
    public func clear() throws {
        sqlite3_close(db)
        db = nil
        for suffix in ["", "-wal", "-shm", "-journal"] {
            let path = file.path + suffix
            if FileManager.default.fileExists(atPath: path) { try FileManager.default.removeItem(atPath: path) }
        }
    }

    private func open() throws -> OpaquePointer {
        if let db { return db }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        var handle: OpaquePointer?
        guard sqlite3_open(file.path, &handle) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open"
            sqlite3_close(handle)
            throw DatabaseError(description: "\(file.lastPathComponent): \(message)")
        }
        // New columns or tables later are added with ALTER/CREATE IF NOT EXISTS; schema_version marks the layout.
        for sql in [
            """
            CREATE TABLE IF NOT EXISTS dictations (
              time REAL NOT NULL, tz_offset INTEGER NOT NULL, outcome TEXT NOT NULL, audio_seconds REAL, wait_seconds REAL,
              words INTEGER, characters INTEGER, engine TEXT, model TEXT, language_requested TEXT, language_detected TEXT,
              app_bundle_id TEXT, app_name TEXT, replacements INTEGER, replaced_terms TEXT, preview_requests INTEGER)
            """,
            "CREATE INDEX IF NOT EXISTS dictations_time ON dictations (time)",
            // Phase 3; databases from phase 2 get it on open. Numbers and the engine only: no text, no speaker names.
            """
            CREATE TABLE IF NOT EXISTS meetings (
              time REAL NOT NULL, duration_seconds REAL, words_mine INTEGER, words_call INTEGER, speakers INTEGER,
              engine TEXT, model TEXT, diarization_seconds REAL, failed_chunks INTEGER)
            """,
            "CREATE INDEX IF NOT EXISTS meetings_time ON meetings (time)",
            "CREATE TABLE IF NOT EXISTS model_events (time REAL NOT NULL, engine TEXT, model TEXT, load_seconds REAL, resident_mb REAL)",
            "CREATE TABLE IF NOT EXISTS schema_version (version INTEGER NOT NULL)",
            "INSERT INTO schema_version (version) SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM schema_version)",
        ] {
            guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
                let failure = error(handle)
                sqlite3_close(handle) // not cached: the next call retries the schema
                throw failure
            }
        }
        db = handle
        return handle
    }

    private func run(_ sql: String, _ values: [Any?]) throws {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw error(try open()) }
    }

    private func prepare(_ sql: String, _ values: [Any?]) throws -> OpaquePointer? {
        let db = try open()
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw error(db) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self) // SQLITE_TRANSIENT: SQLite copies the text
        for (index, value) in values.enumerated() {
            let i = Int32(index + 1)
            switch value {
            case let v as Double: sqlite3_bind_double(statement, i, v)
            case let v as Int: sqlite3_bind_int64(statement, i, Int64(v))
            case let v as String: sqlite3_bind_text(statement, i, v, -1, transient)
            default: sqlite3_bind_null(statement, i)
            }
        }
        return statement
    }

    private func error(_ db: OpaquePointer) -> DatabaseError {
        DatabaseError(description: "\(file.lastPathComponent): \(String(cString: sqlite3_errmsg(db)))")
    }
}
