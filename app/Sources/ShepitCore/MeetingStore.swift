import Foundation

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

    /// A meeting's person: `key` is the label speaker detection gave; `name` the name shown for it (the linked person's,
    /// or for "you" the name in this note); `person` the person it is linked to (voices design §5), You for "you";
    /// `recognised` when that link came from a voice.
    public struct Person: Equatable, Sendable {
        public var key: String
        public var name: String?
        public var person: Int?
        public var recognised: Bool

        public init(key: String, name: String?, person: Int? = nil, recognised: Bool = false) {
            self.key = key
            self.name = name
            self.person = person
            self.recognised = recognised
        }
    }

    public typealias Place = MeetingNote.Place

    public struct Line: Equatable, Sendable {
        public var place: Place
        public var original: String
        public var current: String

        public init(place: Place, original: String, current: String) {
            self.place = place
            self.original = original
            self.current = current
        }
    }

    private let sqlite: SQLiteFile

    public init(file: URL) {
        sqlite = SQLiteFile(file: file, schema: Self.schema, upgrades: Self.upgrades, functions: ["name_key": Names.key])
    }

    /// Adds a meeting with a person per distinct label (in order of first line) and a line per labelled entry, with its
    /// words, and its talk time and voice sample when the session knows them (voices design §4, §7).
    /// nil when a meeting with this path is already listed.
    public func add(path: String, start: Date, duration: TimeInterval?, title: String?, app: String?, you: String?,
                    entries: [MeetingNote.Entry], samples: [Place: VoiceSample] = [:], seconds: [Place: Double] = [:]) throws -> Int? {
        try sqlite.transaction {
            try sqlite.run("INSERT OR IGNORE INTO meetings (path, title, app, start, duration, you) VALUES (?, ?, ?, ?, ?, ?)",
                           [path, title, app, start.timeIntervalSince1970, duration, you])
            guard sqlite.changes == 1 else { return nil }
            let id = try sqlite.rows("SELECT last_insert_rowid()") { $0.int(0) }[0]
            let labelled = entries.filter { $0.label != nil }
            for (entry, place) in zip(labelled, MeetingNote.places(labelled.map(\.timestamp))) {
                try sqlite.run("INSERT OR IGNORE INTO people (meeting, key) VALUES (?, ?)", [id, entry.label])
                if sqlite.changes == 1, let label = entry.label {
                    // A label that is a name ("[Olena]" in a note added by hand) is that person.
                    try link(id, key: label, to: label == you ? youID() : personID(named: label))
                }
                try sqlite.run("INSERT INTO lines (meeting, timestamp, ord, original, current, words, seconds) VALUES (?, ?, ?, ?, ?, ?, ?)",
                               [id, place.timestamp, place.order, entry.label, entry.label, Self.words(entry.text), seconds[place]])
                if let sample = samples[place] {
                    try sqlite.run("INSERT INTO samples (meeting, timestamp, ord, vector) VALUES (?, ?, ?, ?)",
                                   [id, place.timestamp, place.order, sample.blob])
                }
            }
            return id
        }
    }

    /// An entry's words; none for a line that wasn't recognised.
    static func words(_ text: String) -> Int {
        text == MeetingQueue.failedText ? 0 : DictationStore.words(text)
    }

    /// Meetings listed before words were kept (voices design §7): some lines have none.
    public func meetingsWithoutWords() throws -> [Meeting] {
        try meetings("WHERE id IN (SELECT meeting FROM lines WHERE words IS NULL) ORDER BY start DESC, id DESC")
    }

    /// The words of a meeting listed before they were kept, from its note's `entries`; only lines that have none.
    public func fillWords(_ meeting: Int, entries: [MeetingNote.Entry]) throws {
        guard try !sqlite.rows("SELECT 1 FROM lines WHERE meeting = ? AND words IS NULL LIMIT 1", [meeting]) { $0.int(0) }.isEmpty else { return }
        let lines = try lines(meeting)
        try transaction {
            for (entry, line) in zip(entries, MeetingPage.pair(entries, lines)) {
                guard let line else { continue }
                try sqlite.run("UPDATE lines SET words = ? WHERE meeting = ? AND timestamp = ? AND ord = ? AND words IS NULL",
                               [Self.words(entry.text), meeting, line.place.timestamp, line.place.order])
            }
        }
    }

    /// A file with no entry headers.
    public struct NotATranscript: LocalizedError {
        public var errorDescription: String? { "not a meeting transcript (no entries)" }
    }

    /// Adds the meeting of a note (§4). What the session knows (`start`, `duration`) wins, and its lines' talk time and voice samples are kept; otherwise the start is the front
    /// matter's (or the first header's) and the duration runs to the last header. `you` is kept only when the note has
    /// that label. The labels the note has now count as what speaker detection gave. nil when already listed.
    public func add(note: URL, you: String?, start: Date? = nil, duration: TimeInterval? = nil, samples: [Place: VoiceSample] = [:],
                    seconds: [Place: Double] = [:], calendar: Calendar = .current) throws -> Int? {
        let parsed = MeetingNote.parse(try String(contentsOf: note, encoding: .utf8), calendar: calendar)
        let times = parsed.entries.filter { $0.label != nil }.compactMap { MeetingNote.date($0.timestamp, calendar: calendar) }
        guard let first = times.first else { throw NotATranscript() }
        let begin = start ?? parsed.start ?? first
        return try add(path: note.path, start: begin, duration: duration ?? max(0, (times.max() ?? begin).timeIntervalSince(begin)),
                       title: parsed.title, app: parsed.app, you: parsed.entries.contains { $0.label == you } ? you : nil,
                       entries: parsed.entries, samples: samples, seconds: seconds)
    }

    /// Newest first.
    public func meetings() throws -> [Meeting] {
        try meetings("ORDER BY start DESC, id DESC")
    }

    public func meeting(_ id: Int) throws -> Meeting? {
        try meetings("WHERE id = ?", [id]).first
    }

    private func meetings(_ clause: String, _ values: [Any?] = []) throws -> [Meeting] {
        try sqlite.rows("SELECT id, path, title, app, start, duration, you FROM meetings \(clause)", values) { row in
            Meeting(id: row.int(0), path: row.text(1) ?? "", title: row.text(2), app: row.text(3), start: Date(timeIntervalSince1970: row.double(4)),
                    duration: row.isNull(5) ? nil : row.double(5), you: row.text(6))
        }
    }

    /// In the order they were added.
    public func people(_ meeting: Int) throws -> [Person] {
        // people.name is set only on the "you" row, and You has no name of its own.
        try sqlite.rows("""
            SELECT people.key, COALESCE(people.name, persons.name), people.person, people.recognised
            FROM people LEFT JOIN persons ON persons.id = people.person WHERE people.meeting = ? ORDER BY people.rowid
            """, [meeting]) { row in
            Person(key: row.text(0) ?? "", name: row.text(1), person: row.isNull(2) ? nil : row.int(2), recognised: row.int(3) == 1)
        }
    }

    /// In note order.
    public func lines(_ meeting: Int) throws -> [Line] {
        try sqlite.rows("SELECT timestamp, ord, original, current FROM lines WHERE meeting = ? ORDER BY timestamp, ord", [meeting]) { row in
            Line(place: Place(timestamp: row.text(0) ?? "", order: row.int(1)), original: row.text(2) ?? "", current: row.text(3) ?? "")
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
            for table in ["lines", "people", "samples", "declined"] { try sqlite.run("DELETE FROM \(table) WHERE meeting = ?", [meeting]) }
            try sqlite.run("DELETE FROM meetings WHERE id = ?", [meeting])
            try dropUnlistedPersons()
        }
    }

    /// Links a meeting's person to the person with that name, or to a new one (voices design §5); nil: no name, it shows
    /// its label. "you" keeps the name for this note only: the author is You whatever the name.
    public func setName(_ meeting: Int, person key: String, to name: String?) throws {
        try transaction {
            if try sqlite.rows("SELECT 1 FROM meetings WHERE id = ? AND you = ?", [meeting, key]) { $0.int(0) }.isEmpty {
                try link(meeting, key: key, to: name.flatMap(personID(named:)))
                try dropUnlistedPersons()
            } else {
                try sqlite.run("UPDATE people SET name = ? WHERE meeting = ? AND key = ?", [name, meeting, key])
            }
        }
    }

    private func link(_ meeting: Int, key: String, to person: Int?) throws {
        // A name of version 1 that is no person's ("Person 5") stays on its row until the row is named again.
        try sqlite.run("UPDATE people SET person = ?, name = NULL, recognised = 0 WHERE meeting = ? AND key = ?", [person, meeting, key])
    }

    private func youID() throws -> Int {
        try sqlite.rows("SELECT id FROM persons WHERE you = 1") { $0.int(0) }[0]
    }

    /// The person called `name`, the one seen most recently when two share it, or a new person when nobody is;
    /// nil for a label that names nobody ("Person 3").
    private func personID(named name: String) throws -> Int? {
        guard let key = Names.key(name) else { return nil }
        let found = try sqlite.rows("""
            SELECT persons.id FROM persons
            LEFT JOIN people ON people.person = persons.id LEFT JOIN meetings ON meetings.id = people.meeting
            WHERE persons.you = 0 AND name_key(persons.name) = ? GROUP BY persons.id ORDER BY max(meetings.start) DESC LIMIT 1
            """, [key]) { $0.int(0) }
        if let id = found.first { return id }
        try sqlite.run("INSERT INTO persons (name) VALUES (?)", [name])
        return try sqlite.rows("SELECT last_insert_rowid()") { $0.int(0) }[0]
    }

    /// A person left with no meeting goes; You stays.
    private func dropUnlistedPersons() throws {
        try sqlite.run("DELETE FROM persons WHERE you = 0 AND id NOT IN (SELECT person FROM people WHERE person IS NOT NULL)")
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

    // MARK: Voices (voices design §4, §5)

    /// Every sample of a line that belongs to a person now, for prints; `except` leaves one meeting out.
    public func voiceRows(except meeting: Int? = nil) throws -> [Voices.Row] {
        try sqlite.rows("""
            SELECT people.person, samples.meeting, samples.vector FROM samples JOIN lines USING (meeting, timestamp, ord)
            JOIN people ON people.meeting = lines.meeting AND people.key = lines.current
            WHERE people.person IS NOT NULL AND samples.meeting IS NOT ?
            """, [meeting]) { row in
            VoiceSample(blob: row.blob(2)).map { Voices.Row(person: row.int(0), meeting: row.int(1), sample: $0) }
        }
    }

    /// The samples of each person of `meeting` that has no person yet, by key.
    public func unnamedVoices(_ meeting: Int) throws -> [String: [VoiceSample]] {
        let rows = try sqlite.rows("""
            SELECT lines.current, samples.vector FROM samples JOIN lines USING (meeting, timestamp, ord)
            JOIN people ON people.meeting = lines.meeting AND people.key = lines.current
            WHERE samples.meeting = ? AND people.person IS NULL
            """, [meeting]) { row in VoiceSample(blob: row.blob(1)).map { (key: row.text(0) ?? "", sample: $0) } }
        return Dictionary(grouping: rows, by: \.key).mapValues { $0.map(\.sample) }
    }

    /// Names the people of `meeting` a print recognises, as the window names them (the note's headers and the store
    /// together), marked as recognised; a match with You merges that person into "you". Returns how many.
    public func recognise(_ meeting: Meeting) throws -> Int {
        let links = Voices.recognise(try unnamedVoices(meeting.id), prints: Voices.prints(try voiceRows(except: meeting.id)))
        let you = try youID()
        let applied = links.filter { $0.value != you || meeting.you != nil }
        guard !applied.isEmpty else { return 0 }
        try change([meeting]) {
            for (key, person) in applied {
                if person == you, let label = meeting.you {
                    try merge(meeting.id, person: key, into: label)
                } else {
                    try link(meeting.id, key: key, to: person)
                    try sqlite.run("UPDATE people SET recognised = 1 WHERE meeting = ? AND key = ?", [meeting.id, key])
                }
            }
        }
        return applied.count
    }

    /// May also be in (voices design §6): the samples of each unnamed person (by key) of each meeting `person` isn't in,
    /// leaving out the ones declined for `person`.
    public func suggestedVoices(for person: Int) throws -> [Int: [String: [VoiceSample]]] {
        let rows = try sqlite.rows("""
            SELECT samples.meeting, lines.current, samples.vector FROM samples JOIN lines USING (meeting, timestamp, ord)
            JOIN people ON people.meeting = lines.meeting AND people.key = lines.current
            WHERE people.person IS NULL AND samples.meeting NOT IN (SELECT meeting FROM people WHERE person = ?)
              AND NOT EXISTS (SELECT 1 FROM declined WHERE declined.meeting = people.meeting AND declined.key = people.key AND declined.person = ?)
            """, [person, person]) { row in
            VoiceSample(blob: row.blob(2)).map { (meeting: row.int(0), key: row.text(1) ?? "", sample: $0) }
        }
        return Dictionary(grouping: rows, by: \.meeting).mapValues { Dictionary(grouping: $0, by: \.key).mapValues { $0.map(\.sample) } }
    }

    /// Name them (voices design §6): the suggested people (key by meeting) become `person`, in the notes too, unless they
    /// were named meanwhile; the `declined` ones aren't suggested for `person` again.
    public func nameSuggested(_ person: Int, named: [Int: String], declined: [Int: String]) throws {
        try change(try meetings().filter { named[$0.id] != nil }) {
            for (meeting, key) in named {
                try sqlite.run("UPDATE people SET person = ?, name = NULL, recognised = 0 WHERE meeting = ? AND key = ? AND person IS NULL",
                               [person, meeting, key])
            }
            for (meeting, key) in declined {
                try sqlite.run("INSERT OR IGNORE INTO declined (meeting, key, person) VALUES (?, ?, ?)", [meeting, key, person])
            }
        }
    }

    /// The samples of lines that belong to nobody named, in meetings started before `date` (voices design §4: 30 days).
    public func forgetUnnamedVoices(before date: Date) throws {
        try sqlite.runIfExists("""
            DELETE FROM samples WHERE meeting IN (SELECT id FROM meetings WHERE start < ?) AND NOT EXISTS (
              SELECT 1 FROM lines JOIN people ON people.meeting = lines.meeting AND people.key = lines.current
              WHERE lines.meeting = samples.meeting AND lines.timestamp = samples.timestamp AND lines.ord = samples.ord
                AND people.person IS NOT NULL)
            """, [date.timeIntervalSince1970])
    }

    // MARK: People (voices design §6)

    /// A person in a listed meeting where they have lines now, and how many of those lines keep a voice sample.
    public struct Presence: Hashable, Sendable {
        public var person: Int
        /// nil for You, who has no name of their own.
        public var name: String?
        public var you: Bool
        public var meeting: Int
        public var samples: Int
        /// Their words in the meeting; nil while the meeting's words aren't known (listed before they were kept).
        public var words: Int? = nil
        /// Their talk time; nil when none of their lines has one (Add notes…, meetings before talk time was kept).
        public var seconds: Double? = nil
        /// The words of the whole meeting, everyone's.
        public var meetingWords: Int? = nil
    }

    /// Every person (or only `person`) in every meeting (or those started `since`) where they have lines now, once per
    /// meeting. Reads every line of those meetings: People reads one person's, for a period.
    public func presences(of person: Int? = nil, since: Date? = nil) throws -> [Presence] {
        var filters = ["1"], values: [Any?] = []
        if let person { filters.append("people.person = ?"); values.append(person) }
        if let since { filters.append("meetings.start >= ?"); values.append(since.timeIntervalSince1970) }
        return try sqlite.rows("""
            SELECT persons.id, persons.name, persons.you, people.meeting, count(samples.ord), sum(lines.words), sum(lines.seconds),
              (SELECT sum(words) FROM lines AS everyone WHERE everyone.meeting = people.meeting)
            FROM people JOIN persons ON persons.id = people.person JOIN meetings ON meetings.id = people.meeting
            JOIN lines ON lines.meeting = people.meeting AND lines.current = people.key
            LEFT JOIN samples ON samples.meeting = lines.meeting AND samples.timestamp = lines.timestamp AND samples.ord = lines.ord
            WHERE \(filters.joined(separator: " AND "))
            GROUP BY persons.id, people.meeting
            """, values) { row in
            Presence(person: row.int(0), name: row.text(1), you: row.int(2) == 1, meeting: row.int(3), samples: row.int(4),
                     words: row.isNull(5) ? nil : row.int(5), seconds: row.isNull(6) ? nil : row.double(6),
                     meetingWords: row.isNull(7) ? nil : row.int(7))
        }
    }

    /// A person as People's list shows them: how many listed meetings they have lines in now, the last one's start, and
    /// in how many of them a line of theirs keeps a voice sample.
    public struct Summary: Equatable, Sendable {
        public var person: Int
        /// nil for You, who has no name of their own.
        public var name: String?
        public var you: Bool
        public var meetings: Int
        public var last: Date
        public var voiceMeetings: Int
    }

    /// A row per person, without reading every line: each meeting stops at its first line (and sample) of theirs.
    public func summaries() throws -> [Summary] {
        try sqlite.rows("""
            SELECT persons.id, persons.name, persons.you, count(DISTINCT people.meeting), max(meetings.start),
              count(DISTINCT CASE WHEN EXISTS (
                SELECT 1 FROM samples JOIN lines USING (meeting, timestamp, ord)
                WHERE samples.meeting = people.meeting AND lines.current = people.key) THEN people.meeting END)
            FROM people JOIN persons ON persons.id = people.person JOIN meetings ON meetings.id = people.meeting
            WHERE EXISTS (SELECT 1 FROM lines WHERE lines.meeting = people.meeting AND lines.current = people.key)
            GROUP BY persons.id
            """) { row in
            Summary(person: row.int(0), name: row.text(1), you: row.int(2) == 1, meetings: row.int(3),
                    last: Date(timeIntervalSince1970: row.double(4)), voiceMeetings: row.int(5))
        }
    }

    /// Delete voice…: the samples of the lines that are `person`'s now. The person and their names stay.
    public func deleteVoice(_ person: Int) throws {
        try sqlite.runIfExists("""
            DELETE FROM samples WHERE EXISTS (
              SELECT 1 FROM lines JOIN people ON people.meeting = lines.meeting AND people.key = lines.current
              WHERE lines.meeting = samples.meeting AND lines.timestamp = samples.timestamp AND lines.ord = samples.ord
                AND people.person = ?)
            """, [person])
    }

    /// Delete all voices…: every sample, named or not.
    public func deleteAllVoices() throws {
        try sqlite.runIfExists("DELETE FROM samples")
    }

    /// Every real name of every meeting, for the name fields: names given in the window, and labels that are names
    /// ("you", the labels of notes added by hand), not "Person N" or the live label. Newest meeting first, each once.
    public func knownNames() throws -> [String] {
        let names = try sqlite.rows("""
            SELECT COALESCE(people.name, persons.name, people.key) FROM people JOIN meetings ON meetings.id = people.meeting
            LEFT JOIN persons ON persons.id = people.person ORDER BY meetings.start DESC, people.rowid
            """) { $0.text(0) }
        var seen = Set<String>()
        return names.filter { Names.key($0) != nil && seen.insert($0).inserted }
    }

    /// Rename (voices design §6): the person's one name, in every meeting and in the headers of their notes.
    public func rename(person: Int, to name: String) throws {
        try change(try meetings(of: person)) {
            try sqlite.run("UPDATE persons SET name = ? WHERE id = ? AND you = 0", [name, person])
        }
    }

    /// Merge into… (voices design §6): every meeting of `person` moves to `other`, and `person` is deleted. In a meeting
    /// with both, `person`'s lines go to the other, as a merge in one meeting does. Into You, a meeting without "you"
    /// gets this person as its "you", named `myName`.
    public func merge(person: Int, into other: Int, myName: String) throws {
        let meetings = try meetings(of: person)
        let you = try youID()
        try change(meetings) {
            for meeting in meetings {
                var target = other == you ? meeting.you : try keys(of: other, in: meeting.id).first
                for key in try keys(of: person, in: meeting.id) {
                    if let target {
                        try merge(meeting.id, person: key, into: target)
                        try link(meeting.id, key: key, to: nil)
                        continue
                    }
                    if other == you {
                        try sqlite.run("UPDATE meetings SET you = ? WHERE id = ?", [key, meeting.id])
                        try sqlite.run("UPDATE people SET name = ? WHERE meeting = ? AND key = ?", [myName, meeting.id, key])
                    }
                    try sqlite.run("UPDATE people SET person = ? WHERE meeting = ? AND key = ?", [other, meeting.id, key])
                    target = key
                }
            }
            try sqlite.run("UPDATE OR IGNORE declined SET person = ? WHERE person = ?", [other, person])
            try sqlite.run("DELETE FROM declined WHERE person = ?", [person])
            try dropUnlistedPersons()
        }
    }

    private func meetings(of person: Int) throws -> [Meeting] {
        try meetings("WHERE id IN (SELECT meeting FROM people WHERE person = ?) ORDER BY start DESC, id DESC", [person])
    }

    private func keys(of person: Int, in meeting: Int) throws -> [String] {
        try sqlite.rows("SELECT key FROM people WHERE meeting = ? AND person = ? ORDER BY rowid", [meeting, person]) { $0.text(0) ?? "" }
    }

    /// A note a change could not read or write: nothing was changed.
    public struct NoteNotChanged: LocalizedError {
        public var path: String
        public var reason: String
        public var errorDescription: String? { "\(path)\n\(reason)" }
    }

    /// A change to the people or lines of `meetings` made by `body` (Meetings design §8): the store and the notes' headers
    /// together, or none of them. Each note is read right before it is written, so edits made in Obsidian meanwhile stay;
    /// only the headers whose shown name changed are rewritten. A missing note changes only the store.
    public func change(_ meetings: [Meeting], _ body: () throws -> Void) throws {
        try transaction {
            let before = try meetings.map { (people: try people($0.id), lines: try lines($0.id)) }
            try body()
            var written: [(note: URL, text: String)] = []
            do {
                for (meeting, before) in zip(meetings, before) {
                    let after = (people: try people(meeting.id), lines: try lines(meeting.id))
                    let note = URL(fileURLWithPath: meeting.path)
                    guard FileManager.default.fileExists(atPath: note.path) else { continue }
                    do {
                        let text = try String(contentsOf: note, encoding: .utf8)
                        let changed = MeetingPage.relabelled(text, before: before, after: after)
                        guard changed != text else { continue }
                        try Data(changed.utf8).write(to: note, options: .atomic)
                        written.append((note, text))
                    } catch {
                        throw NoteNotChanged(path: meeting.path, reason: error.localizedDescription)
                    }
                }
            } catch {
                for (note, text) in written.reversed() { try? Data(text.utf8).write(to: note, options: .atomic) }
                throw error
            }
        }
    }

    /// Remove note from list (the note stays), or with `trash` Move file to Trash: the row and the file go together.
    public func remove(_ meeting: Meeting, trash: Bool) throws {
        try transaction {
            try remove(meeting.id)
            if trash { try FileManager.default.trashItem(at: URL(fileURLWithPath: meeting.path), resultingItemURL: nil) }
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

    /// Version 1's layout; later versions are `upgrades`.
    static let schema = [
        // Runs on every open. Deleted voice samples are overwritten; macOS's default (FAST) leaves freed pages as they were.
        "PRAGMA secure_delete = ON",
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

    /// Version 2 (voices design §7): persons, voice samples, talk time and words per line. Names already given, and labels
    /// that are names, become persons: one per name the same ignoring case, accents and script, spelled as in the newest
    /// meeting. Each meeting's "you" row is You and keeps its name for that note; a linked row's name is its person's.
    static let upgrades = ["""
        CREATE TABLE persons (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, you INTEGER NOT NULL DEFAULT 0);
        ALTER TABLE people ADD COLUMN person INTEGER;
        ALTER TABLE people ADD COLUMN recognised INTEGER NOT NULL DEFAULT 0;
        ALTER TABLE lines ADD COLUMN words INTEGER;
        ALTER TABLE lines ADD COLUMN seconds REAL;
        CREATE TABLE samples (
          meeting INTEGER NOT NULL, timestamp TEXT NOT NULL, ord INTEGER NOT NULL, vector BLOB NOT NULL,
          PRIMARY KEY (meeting, timestamp, ord));
        CREATE TABLE declined (meeting INTEGER NOT NULL, key TEXT NOT NULL, person INTEGER NOT NULL, PRIMARY KEY (meeting, key, person));
        INSERT INTO persons (you) VALUES (1);
        UPDATE people SET person = (SELECT id FROM persons WHERE you = 1)
          WHERE key = (SELECT you FROM meetings WHERE meetings.id = people.meeting);
        INSERT INTO persons (name)
          SELECT name FROM (
            SELECT COALESCE(people.name, people.key) AS name, max(meetings.start)
            FROM people JOIN meetings ON meetings.id = people.meeting
            WHERE people.person IS NULL AND name_key(COALESCE(people.name, people.key)) IS NOT NULL
            GROUP BY name_key(COALESCE(people.name, people.key)));
        UPDATE people SET person = (
            SELECT persons.id FROM persons WHERE persons.you = 0 AND name_key(persons.name) = name_key(COALESCE(people.name, people.key)))
          WHERE person IS NULL;
        UPDATE people SET name = NULL WHERE person IN (SELECT id FROM persons WHERE you = 0)
        """]
}
