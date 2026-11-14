import Foundation
import SQLite3

/// meetings.sqlite (Meetings design §4): the list of meetings, their people and who said each line.
/// Names, paths and times only; the transcript's text stays in the note.
public final class MeetingStore {
    public struct Meeting: Equatable, Sendable {
        public var id: Int
        public var path: String
        public var title: String?
        public var app: String?
        public var start: Date
        public var duration: TimeInterval?
        /// The label "you" has in this note.
        public var you: String?

        public init(id: Int, path: String, title: String?, app: String?, start: Date, duration: TimeInterval?, you: String?) {
            self.id = id
            self.path = path
            self.title = title
            self.app = app
            self.start = start
            self.duration = duration
            self.you = you
        }
    }

    /// `key` is the label speaker detection gave; `name` the one given in the window.
    public struct Person: Equatable, Sendable {
        public var key: String
        public var name: String?

        public init(key: String, name: String?) {
            self.key = key
            self.name = name
        }
    }

    /// Where a line is in the note: its header's timestamp and its place among the headers of that second.
    public struct Place: Hashable, Sendable {
        public var timestamp: String
        public var order: Int

        public init(timestamp: String, order: Int) {
            self.timestamp = timestamp
            self.order = order
        }
    }

    public struct Line: Equatable, Sendable {
        public var timestamp: String
        public var order: Int
        public var original: String
        public var current: String

        public init(timestamp: String, order: Int, original: String, current: String) {
            self.timestamp = timestamp
            self.order = order
            self.original = original
            self.current = current
        }

        public var place: Place { Place(timestamp: timestamp, order: order) }
    }

    private let sqlite: SQLiteFile

    public init(file: URL) {
        sqlite = SQLiteFile(file: file, schema: Self.schema)
    }

    /// Adds a meeting with a person per distinct label (in order of first line) and a line per labelled entry.
    /// nil when a meeting with this path is already listed.
    public func add(path: String, start: Date, duration: TimeInterval?, title: String?, app: String?, you: String?,
                    entries: [MeetingNote.Entry]) throws -> Int? {
        try sqlite.transaction {
            try sqlite.run("INSERT OR IGNORE INTO meetings (path, title, app, start, duration, you) VALUES (?, ?, ?, ?, ?, ?)",
                           [path, title, app, start.timeIntervalSince1970, duration, you])
            guard sqlite.changes == 1 else { return nil }
            let id = try sqlite.rows("SELECT last_insert_rowid()") { Int(sqlite3_column_int64($0, 0)) }[0]
            var orders: [String: Int] = [:]
            for entry in entries {
                guard let label = entry.label else { continue }
                let order = orders[entry.timestamp, default: 0]
                orders[entry.timestamp] = order + 1
                try sqlite.run("INSERT OR IGNORE INTO people (meeting, key) VALUES (?, ?)", [id, label])
                try sqlite.run("INSERT INTO lines (meeting, timestamp, ord, original, current) VALUES (?, ?, ?, ?, ?)",
                               [id, entry.timestamp, order, label, label])
            }
            return id
        }
    }

    /// A file with no entry headers.
    public struct NotATranscript: LocalizedError {
        public var errorDescription: String? { "not a meeting transcript (no entries)" }
    }

    /// Adds the meeting of a note (§4). What the session knows (`start`, `duration`) wins; otherwise the start is the front
    /// matter's (or the first header's) and the duration runs to the last header. `you` is kept only when the note has
    /// that label. The labels the note has now count as what speaker detection gave. nil when already listed.
    public func add(note: URL, you: String?, start: Date? = nil, duration: TimeInterval? = nil, calendar: Calendar = .current) throws -> Int? {
        let parsed = MeetingNote.parse(try String(contentsOf: note, encoding: .utf8), calendar: calendar)
        let times = parsed.entries.filter { $0.label != nil }.compactMap { MeetingNote.date($0.timestamp, calendar: calendar) }
        guard let first = times.first else { throw NotATranscript() }
        let begin = start ?? parsed.start ?? first
        return try add(path: note.path, start: begin, duration: duration ?? max(0, (times.max() ?? begin).timeIntervalSince(begin)),
                       title: parsed.title, app: parsed.app, you: parsed.entries.contains { $0.label == you } ? you : nil,
                       entries: parsed.entries)
    }

    /// Newest first.
    public func meetings() throws -> [Meeting] {
        try sqlite.rows("SELECT id, path, title, app, start, duration, you FROM meetings ORDER BY start DESC, id DESC") { s in
            Meeting(id: Int(sqlite3_column_int64(s, 0)), path: Self.text(s, 1) ?? "", title: Self.text(s, 2), app: Self.text(s, 3),
                    start: Date(timeIntervalSince1970: sqlite3_column_double(s, 4)),
                    duration: sqlite3_column_type(s, 5) == SQLITE_NULL ? nil : sqlite3_column_double(s, 5), you: Self.text(s, 6))
        }
    }

    /// In the order they were added.
    public func people(_ meeting: Int) throws -> [Person] {
        try sqlite.rows("SELECT key, name FROM people WHERE meeting = ? ORDER BY rowid", [meeting]) { s in
            Person(key: Self.text(s, 0) ?? "", name: Self.text(s, 1))
        }
    }

    /// In note order.
    public func lines(_ meeting: Int) throws -> [Line] {
        try sqlite.rows("SELECT timestamp, ord, original, current FROM lines WHERE meeting = ? ORDER BY timestamp, ord", [meeting]) { s in
            Line(timestamp: Self.text(s, 0) ?? "", order: Int(sqlite3_column_int64(s, 1)), original: Self.text(s, 2) ?? "",
                 current: Self.text(s, 3) ?? "")
        }
    }

    public func rename(_ meeting: Int, title: String?) throws {
        try sqlite.run("UPDATE meetings SET title = ? WHERE id = ?", [title, meeting])
    }

    public func relink(_ meeting: Int, path: String) throws {
        try sqlite.run("UPDATE meetings SET path = ? WHERE id = ?", [path, meeting])
    }

    public func remove(_ meeting: Int) throws {
        try sqlite.transaction {
            for table in ["lines", "people"] { try sqlite.run("DELETE FROM \(table) WHERE meeting = ?", [meeting]) }
            try sqlite.run("DELETE FROM meetings WHERE id = ?", [meeting])
        }
    }

    /// nil: no name, the person shows its label.
    public func setName(_ meeting: Int, person: String, to name: String?) throws {
        try sqlite.run("UPDATE people SET name = ? WHERE meeting = ? AND key = ?", [name, meeting, person])
    }

    public func give(_ meeting: Int, line: Place, to person: String) throws {
        try sqlite.run("UPDATE lines SET current = ? WHERE meeting = ? AND timestamp = ? AND ord = ?",
                       [person, meeting, line.timestamp, line.order])
    }

    /// Every line of `person` goes to `into`.
    public func merge(_ meeting: Int, person: String, into: String) throws {
        try sqlite.run("UPDATE lines SET current = ? WHERE meeting = ? AND current = ?", [into, meeting, person])
    }

    /// A new person with the next free "Person N"; it has no lines until one is given to it.
    public func newPerson(_ meeting: Int) throws -> String {
        let taken = try people(meeting).compactMap { $0.key.wholeMatch(of: /Person (\d+)/).flatMap { Int($0.1) } }
        let key = "Person \((taken.max() ?? 0) + 1)"
        try sqlite.run("INSERT INTO people (meeting, key) VALUES (?, ?)", [meeting, key])
        return key
    }

    /// Every line back to the person speaker detection gave it. Names stay.
    public func reset(_ meeting: Int) throws {
        try sqlite.run("UPDATE lines SET current = original WHERE meeting = ?", [meeting])
    }

    /// Every real name of every meeting, for the name fields: names given in the window, and labels that are names
    /// ("you", the labels of notes added by hand), not "Person N" or the live label. Newest meeting first, each once.
    public func knownNames() throws -> [String] {
        let names = try sqlite.rows("""
            SELECT COALESCE(people.name, people.key) FROM people JOIN meetings ON meetings.id = people.meeting
            ORDER BY meetings.start DESC, people.rowid
            """) { Self.text($0, 0) }
        var seen = Set<String>()
        return names.filter { name in
            !name.isEmpty && name != MeetingNote.callLabel && name.wholeMatch(of: /Person \d+/) == nil && seen.insert(name).inserted
        }
    }

    /// Renames a meeting (Meetings design §8): the store, the note's `title` line and file name, and `meeting-names.json`.
    /// The store and the note change together or not at all; a missing note changes only the store and the names file.
    public func rename(_ meeting: Meeting, to title: String?, template: String, namesFile: URL, calendar: Calendar = .current) throws {
        let fm = FileManager.default
        let note = URL(fileURLWithPath: meeting.path)
        try transaction {
            try rename(meeting.id, title: title)
            guard fm.fileExists(atPath: note.path) else { return }
            let target = MeetingFileName.renamed(note, template: template, start: meeting.start, title: title, app: meeting.app,
                                                 calendar: calendar) { fm.fileExists(atPath: $0.path) }
            if target != note { try relink(meeting.id, path: target.path) }
            let text = try String(contentsOf: note, encoding: .utf8)
            let titled = MeetingNote.settingTitle(text, title)
            if titled != text { try Data(titled.utf8).write(to: note, options: .atomic) }
            guard target != note else { return }
            do {
                try fm.moveItem(at: note, to: target)
            } catch {
                if titled != text { try? Data(text.utf8).write(to: note, options: .atomic) }
                throw error
            }
        }
        // Best effort: the names file only prefills the name dialog.
        try? MeetingNames.save(MeetingNames.renaming(MeetingNames.load(namesFile), start: meeting.start, to: title, app: meeting.app), to: namesFile)
    }

    /// Runs `body` as one change: all of it is kept, or none when it throws.
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        try sqlite.transaction(body)
    }

    private static func text(_ statement: OpaquePointer, _ i: Int32) -> String? {
        sqlite3_column_text(statement, i).map { String(cString: $0) }
    }

    // Later parts (voice prints, import) add tables with CREATE IF NOT EXISTS; schema_version marks the layout.
    private static let schema = [
        """
        CREATE TABLE IF NOT EXISTS meetings (
          id INTEGER PRIMARY KEY, path TEXT NOT NULL UNIQUE, title TEXT, app TEXT, start REAL NOT NULL, duration REAL, you TEXT)
        """,
        "CREATE TABLE IF NOT EXISTS people (meeting INTEGER NOT NULL, key TEXT NOT NULL, name TEXT, PRIMARY KEY (meeting, key))",
        """
        CREATE TABLE IF NOT EXISTS lines (
          meeting INTEGER NOT NULL, timestamp TEXT NOT NULL, ord INTEGER NOT NULL, original TEXT NOT NULL, current TEXT NOT NULL,
          PRIMARY KEY (meeting, timestamp, ord))
        """,
        "CREATE TABLE IF NOT EXISTS schema_version (version INTEGER NOT NULL)",
        "INSERT INTO schema_version (version) SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM schema_version)",
    ]
}
