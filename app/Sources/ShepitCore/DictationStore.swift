import Foundation

/// dictations.sqlite (Dictations and Dictionary design §4): every dictation's time, app, text and word count.
/// The only place dictated text is kept; `stats.sqlite` keeps numbers only.
public final class DictationStore {
    public struct Entry: Equatable, Sendable {
        public var id: Int
        public var time: Date
        public var appName: String?
        public var appBundleID: String?
        public var text: String
        public var words: Int

        public init(id: Int, time: Date, appName: String?, appBundleID: String?, text: String, words: Int) {
            self.id = id
            self.time = time
            self.appName = appName
            self.appBundleID = appBundleID
            self.text = text
            self.words = words
        }
    }

    public var file: URL { sqlite.file }
    private let sqlite: SQLiteFile
    /// After every add, delete, prune and clear: the one place the app learns that the history changed.
    private let changed: () -> Void

    public init(file: URL, changed: @escaping () -> Void = {}) {
        sqlite = SQLiteFile(file: file, schema: Self.schema)
        self.changed = changed
    }

    /// Returns the new entry's id.
    @discardableResult
    public func add(text: String, app: AppRef?, at time: Date) throws -> Int {
        try sqlite.run("INSERT INTO dictations (time, app_name, app_bundle_id, text, words) VALUES (?, ?, ?, ?, ?)",
                       [time.timeIntervalSince1970, app?.name, app?.bundleID, text, Self.words(text)])
        let id = try sqlite.rows("SELECT last_insert_rowid()") { $0.int(0) }[0]
        changed()
        return id
    }

    /// Words as the list and the statistics count them.
    public static func words(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    /// Up to `limit` entries older than `before` (the newest when nil) and not older than `since`, newest first. Ordered
    /// by time, then id, so entries of one second neither repeat nor go missing from one page to the next.
    public func page(before: Entry? = nil, since: Date? = nil, limit: Int) throws -> [Entry] {
        var conditions: [String] = []
        var values: [Any?] = []
        if let before {
            conditions.append("(time, id) < (?, ?)")
            values += [before.time.timeIntervalSince1970, before.id]
        }
        if let since {
            conditions.append("time >= ?")
            values.append(since.timeIntervalSince1970)
        }
        return try sqlite.rows("""
            SELECT id, time, app_name, app_bundle_id, text, words FROM dictations
            \(conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")) ORDER BY time DESC, id DESC LIMIT ?
            """, values + [limit]) { row in
            Entry(id: row.int(0), time: Date(timeIntervalSince1970: row.double(1)), appName: row.text(2), appBundleID: row.text(3),
                  text: row.text(4) ?? "", words: row.int(5))
        }
    }

    public func delete(_ id: Int) throws {
        try sqlite.runIfExists("DELETE FROM dictations WHERE id = ?", [id])
        changed()
    }

    /// Deletes entries older than `cutoff`; returns how many.
    @discardableResult
    public func prune(before cutoff: Date) throws -> Int {
        try sqlite.runIfExists("DELETE FROM dictations WHERE time < ?", [cutoff.timeIntervalSince1970])
        let count = sqlite.changes
        if count > 0 { changed() }
        return count
    }

    /// Clear history…: deletes the file; the next add creates it again.
    public func clear() throws {
        try sqlite.delete()
        changed()
    }

    // Later columns or tables are added with ALTER/CREATE IF NOT EXISTS; schema_version marks the layout.
    private static let schema = [
        // Runs on every open. Deleted text is overwritten; macOS's default (FAST) leaves freed overflow pages as they were.
        "PRAGMA secure_delete = ON",
        """
        CREATE TABLE IF NOT EXISTS dictations (
          id INTEGER PRIMARY KEY, time REAL NOT NULL, app_name TEXT, app_bundle_id TEXT, text TEXT NOT NULL, words INTEGER NOT NULL)
        """,
        "CREATE INDEX IF NOT EXISTS dictations_time ON dictations (time)",
        "CREATE TABLE IF NOT EXISTS schema_version (version INTEGER NOT NULL)",
        "INSERT INTO schema_version (version) SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM schema_version)",
    ]
}
