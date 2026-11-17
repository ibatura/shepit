import Foundation

/// stats.sqlite (`05-statistics.md` §1): one row per dictation attempt, per meeting, per call offer and per model load.
/// Numbers and names only; nothing dictated is ever written here.
public final class StatsDatabase {
    public var file: URL { sqlite.file }
    private let sqlite: SQLiteFile

    public init(file: URL) {
        sqlite = SQLiteFile(file: file, schema: Self.schema, upgrades: Self.upgrades)
    }

    public func insert(_ row: DictationRow) throws {
        let terms = String(decoding: try JSONSerialization.data(withJSONObject: row.replacedTerms), as: UTF8.self)
        try run("""
            INSERT INTO dictations (time, tz_offset, outcome, audio_seconds, wait_seconds, words, characters, engine, model,
              language_requested, language_detected, app_bundle_id, app_name, replacements, replaced_terms, preview_requests)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [row.time.timeIntervalSince1970, row.tzOffset, row.outcome.rawValue, row.audioSeconds, row.waitSeconds, row.words,
                  row.characters, row.engine.engine.rawValue, row.engine.model, row.languageRequested, row.languageDetected, row.appBundleID, row.appName,
                  row.replacements, terms, row.previewRequests])
    }

    public func insertModelLoad(engine: EngineChoice, seconds: Double, residentMB: Double?, at time: Date) throws {
        try run("INSERT INTO model_events (time, engine, model, load_seconds, resident_mb) VALUES (?, ?, ?, ?, ?)",
                [time.timeIntervalSince1970, engine.engine.rawValue, engine.model, seconds, residentMB])
    }

    public func insertMeeting(_ record: MeetingRecord) throws {
        try run("""
            INSERT INTO meetings (time, duration_seconds, words_mine, words_call, speakers, engine, model, diarization_seconds, failed_chunks,
              app)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [record.start.timeIntervalSince1970, record.duration, record.wordsMine, record.wordsCall, record.speakers,
                  record.engine.engine.rawValue, record.engine.model, record.diarizationSeconds, record.failedChunks, record.app?.rawValue])
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
            SELECT time, duration_seconds, words_mine, words_call, speakers, engine, model, diarization_seconds, failed_chunks, app
            FROM meetings
            """, in: range) { row in
            MeetingRecord(
                start: Date(timeIntervalSince1970: row.double(0)), duration: row.double(1), wordsMine: row.int(2), wordsCall: row.int(3),
                speakers: row.isNull(4) ? nil : row.int(4),
                engine: Self.engine(row.text(5), row.text(6)),
                diarizationSeconds: row.isNull(7) ? nil : row.double(7), failedChunks: row.int(8),
                app: CallApp(rawValue: row.text(9) ?? "")) // nil for older meetings and for an app this version doesn't know
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
                waitSeconds: row.double(4), words: row.int(5), characters: row.int(6), engine: Self.engine(row.text(7), row.text(8)),
                languageRequested: row.text(9) ?? "", languageDetected: row.text(10), appBundleID: row.text(11), appName: row.text(12),
                replacedTerms: terms, previewRequests: row.int(14))
        }
    }

    /// A stored engine and model. Engine IDs were never renamed; one this version doesn't know (a newer Shepit's) reads
    /// as whisper.cpp with its model.
    private static func engine(_ engine: String?, _ model: String?) -> EngineChoice {
        EngineChoice(engine: EngineID(rawValue: engine ?? "") ?? .whispercpp, model: model ?? "")
    }

    /// Clear statistics…: deletes the database file.
    public func clear() throws {
        try sqlite.delete()
    }

    // Version 1's layout; later tables come here with CREATE … IF NOT EXISTS, later columns in `upgrades`.
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
        "CREATE INDEX IF NOT EXISTS offers_time ON offers (time)",
        "CREATE TABLE IF NOT EXISTS model_events (time REAL NOT NULL, engine TEXT, model TEXT, load_seconds REAL, resident_mb REAL)",
    ]

    private static let upgrades = [
        // 2 (statistics design §6): the meeting's app, CallApp's raw value ("Teams"); older meetings keep it empty.
        "ALTER TABLE meetings ADD COLUMN app TEXT",
    ]

    private func run(_ sql: String, _ values: [Any?]) throws {
        try sqlite.run(sql, values)
    }
}
