import Foundation

/// stats.sqlite (`05-statistics.md` §1): one row per dictation attempt, per meeting, per call offer and per model load.
/// Numbers and names only; nothing dictated is ever written here.
public final class StatsDatabase {
    public var file: URL { sqlite.file }
    private let sqlite: SQLiteFile

    public init(file: URL) {
        sqlite = SQLiteFile(file: file, schema: Self.schema)
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

    public func insertOffer(_ row: OfferRow) throws {
        try run("INSERT INTO offers (time, app, outcome) VALUES (?, ?, ?)",
                [row.time.timeIntervalSince1970, row.app.rawValue, row.outcome.rawValue])
    }

    /// Call offers in `range` (all of them when nil), oldest first.
    public func offers(in range: DateInterval?) throws -> [OfferRow] {
        try rows("SELECT time, app, outcome FROM offers", in: range) { row in
            // A row with an app or outcome this version doesn't know is left out.
            guard let app = CallApp(rawValue: row.text(1) ?? ""), let outcome = CallOffer.Outcome(rawValue: row.text(2) ?? "") else { return nil }
            return OfferRow(time: Date(timeIntervalSince1970: row.double(0)), app: app, outcome: outcome)
        }
    }

    /// The rows `select` gives with `time` in `range` (all of them when nil), oldest first; `read` returns nil to skip one.
    private func rows<T>(_ select: String, in range: DateInterval?, read: (SQLiteFile.Row) -> T?) throws -> [T] {
        let start = range?.start.timeIntervalSince1970 ?? -.greatestFiniteMagnitude
        let end = range?.end.timeIntervalSince1970 ?? .greatestFiniteMagnitude
        return try sqlite.rows(select + " WHERE time >= ? AND time < ? ORDER BY time", [start, end], read: read)
    }

    /// Meetings that started in `range` (all of them when nil), oldest first.
    public func meetings(in range: DateInterval?) throws -> [MeetingRecord] {
        try rows("""
            SELECT time, duration_seconds, words_mine, words_call, speakers, engine, model, diarization_seconds, failed_chunks
            FROM meetings
            """, in: range) { row in
            MeetingRecord(
                start: Date(timeIntervalSince1970: row.double(0)), duration: row.double(1), wordsMine: row.int(2), wordsCall: row.int(3),
                speakers: row.isNull(4) ? nil : row.int(4),
                engine: EngineChoice(engine: EngineID(rawValue: row.text(5) ?? "") ?? .whispercpp, model: row.text(6) ?? ""),
                diarizationSeconds: row.isNull(7) ? nil : row.double(7), failedChunks: row.int(8))
        }
    }

    /// Attempts in `range` (all of them when nil), oldest first.
    public func dictations(in range: DateInterval?) throws -> [DictationRow] {
        try rows("""
            SELECT time, tz_offset, outcome, audio_seconds, wait_seconds, words, characters, engine, model, language_requested,
              language_detected, app_bundle_id, app_name, replaced_terms, preview_requests
            FROM dictations
            """, in: range) { row in
            let terms = row.text(13).flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String] } ?? []
            return DictationRow(
                time: Date(timeIntervalSince1970: row.double(0)), tzOffset: row.int(1),
                outcome: DictationOutcome(rawValue: row.text(2) ?? "") ?? .failed, audioSeconds: row.double(3),
                waitSeconds: row.double(4), words: row.int(5), characters: row.int(6), engine: row.text(7) ?? "", model: row.text(8) ?? "",
                languageRequested: row.text(9) ?? "", languageDetected: row.text(10), appBundleID: row.text(11), appName: row.text(12),
                replacedTerms: terms, previewRequests: row.int(14))
        }
    }

    /// Clear statistics…: deletes the database file.
    public func clear() throws {
        try sqlite.delete()
    }

    // New columns or tables later are added with ALTER/CREATE IF NOT EXISTS; schema_version marks the layout.
    private static let schema = [
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
        // Call offers; older databases get it on open. The app's name and how the offer ended: no call names.
        "CREATE TABLE IF NOT EXISTS offers (time REAL NOT NULL, app TEXT NOT NULL, outcome TEXT NOT NULL)",
        "CREATE TABLE IF NOT EXISTS model_events (time REAL NOT NULL, engine TEXT, model TEXT, load_seconds REAL, resident_mb REAL)",
        "CREATE TABLE IF NOT EXISTS schema_version (version INTEGER NOT NULL)",
        "INSERT INTO schema_version (version) SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM schema_version)",
    ]

    private func run(_ sql: String, _ values: [Any?]) throws {
        try sqlite.run(sql, values)
    }
}
