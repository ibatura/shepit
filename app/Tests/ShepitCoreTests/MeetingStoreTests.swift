import Foundation
import Testing
@testable import ShepitCore

// Meetings design §4, §8.
struct MeetingStoreTests {
    private func store() -> (MeetingStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "meeting-store-\(UUID().uuidString)")
        return (MeetingStore(file: dir.appending(path: "meetings.sqlite")), dir)
    }

    private func entry(_ label: String?, _ second: Int, line: Int = 0) -> MeetingNote.Entry {
        .init(label: label, timestamp: "2026-07-31 10:00:\(String(format: "%02d", second))", text: "", line: line)
    }

    private let start = Date(timeIntervalSince1970: 1_785_484_800)

    /// Me, Person 1, Person 2, Person 1 (two in second 03), a ⚠ line.
    private func addSample(_ store: MeetingStore, path: String = "/notes/a.md", start: Date? = nil) throws -> Int {
        try #require(try store.add(path: path, start: start ?? self.start, duration: 60, title: "Sync", app: "Teams", you: "Me",
                                   entries: [entry("Me", 1), entry("Person 1", 3), entry("Person 2", 3), entry(nil, 0), entry("Person 1", 5)]))
    }

    @Test func addKeepsTheMeetingItsPeopleAndLines() throws {
        let (store, dir) = store()
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = try addSample(store)
        #expect(try store.meetings() == [.init(id: id, path: "/notes/a.md", title: "Sync", app: "Teams", start: start, duration: 60, you: "Me")])
        #expect(try store.people(id) == [.init(key: "Me", name: nil, person: 1), .init(key: "Person 1", name: nil), .init(key: "Person 2", name: nil)])
        #expect(try store.lines(id) == [
            .init(place: .init(timestamp: "2026-07-31 10:00:01", order: 0), original: "Me", current: "Me", words: 0),
            .init(place: .init(timestamp: "2026-07-31 10:00:03", order: 0), original: "Person 1", current: "Person 1", words: 0),
            .init(place: .init(timestamp: "2026-07-31 10:00:03", order: 1), original: "Person 2", current: "Person 2", words: 0),
            .init(place: .init(timestamp: "2026-07-31 10:00:05", order: 0), original: "Person 1", current: "Person 1", words: 0),
        ])
    }

    @Test func aPathAlreadyListedIsNotAddedAgain() throws {
        let (store, dir) = store()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try addSample(store)
        #expect(try store.add(path: "/notes/a.md", start: start, duration: nil, title: nil, app: nil, you: nil, entries: []) == nil)
        #expect(try store.meetings().count == 1)
    }

    @Test func meetingsAreNewestFirstAndKeptAfterReopening() throws {
        let (store, dir) = store()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try addSample(store, path: "/old.md")
        _ = try addSample(store, path: "/new.md", start: start.addingTimeInterval(3600))
        let reopened = MeetingStore(file: dir.appending(path: "meetings.sqlite"))
        #expect(try reopened.meetings().map(\.path) == ["/new.md", "/old.md"])
        #expect(try reopened.meeting(reopened.meetings()[1].id)?.path == "/old.md" && reopened.meeting(999) == nil)
    }

    @Test func renameRelinkAndRemove() throws {
        let (store, dir) = store()
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = try addSample(store)
        let other = try addSample(store, path: "/b.md")
        try store.rename(id, title: nil)
        try store.relink(id, path: "/moved.md")
        #expect(try store.meetings().first { $0.id == id }.map { [$0.title, $0.path] } == [nil, "/moved.md"])
        try store.remove(id)
        #expect(try store.meetings().map(\.id) == [other])
        #expect(try store.people(id).isEmpty && store.lines(id).isEmpty)
        #expect(try store.lines(other).count == 4)
    }

    @Test func nameGiveMergeNewPersonAndReset() throws {
        let (store, dir) = store()
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = try addSample(store)
        try store.setName(id, person: "Person 1", to: "Olena K.")
        try store.give(id, line: .init(timestamp: "2026-07-31 10:00:01", order: 0), to: "Person 2")
        try store.merge(id, person: "Person 2", into: "Person 1")
        #expect(try store.lines(id).map(\.current) == ["Person 1", "Person 1", "Person 1", "Person 1"])
        let added = try store.newPerson(id)
        #expect(added == "Person 3")
        try store.give(id, line: .init(timestamp: "2026-07-31 10:00:05", order: 0), to: added)
        #expect(try store.lines(id).map(\.current) == ["Person 1", "Person 1", "Person 1", "Person 3"])
        try store.reset(id)
        #expect(try store.lines(id).map(\.current) == ["Me", "Person 1", "Person 2", "Person 1"])
        #expect(try store.people(id).first { $0.key == "Person 1" }?.name == "Olena K.") // names stay
        try store.setName(id, person: "Person 1", to: nil)
        #expect(try store.people(id).first { $0.key == "Person 1" }?.name == nil)
    }

    @Test func newPersonTakesTheNextFreeNumber() throws {
        let (store, dir) = store()
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = try #require(try store.add(path: "/a.md", start: start, duration: nil, title: nil, app: nil, you: nil,
                                            entries: [entry("Person 7", 1), entry("Olena", 2)]))
        #expect(try store.newPerson(id) == "Person 8")
        #expect(try store.newPerson(id) == "Person 9")
    }

    @Test func knownNamesAreEveryRealNameNewestMeetingFirst() throws {
        let (store, dir) = store()
        defer { try? FileManager.default.removeItem(at: dir) }
        let old = try addSample(store, path: "/old.md")
        let new = try addSample(store, path: "/new.md", start: start.addingTimeInterval(3600))
        let this = try addSample(store, path: "/this.md", start: start.addingTimeInterval(7200))
        try store.setName(old, person: "Person 1", to: "Olena K.")
        try store.setName(old, person: "Person 2", to: "Marko D.")
        try store.setName(new, person: "Person 2", to: "Olena K.")
        try store.setName(new, person: "Person 1", to: "Anna")
        try store.setName(this, person: "Person 1", to: "Only here")
        // A note added by hand: its labels are names, except the live label and "Person N".
        _ = try store.add(path: "/added.md", start: start.addingTimeInterval(-3600), duration: nil, title: nil, app: nil, you: nil,
                          entries: [entry(MeetingNote.callLabel, 1), entry("Olha Barbara", 2), entry("Person 4", 3)])
        #expect(try store.knownNames() == ["Me", "Only here", "Anna", "Olena K.", "Marko D.", "Olha Barbara"])
    }

    // Persons (voices design §5, §7)

    @Test func namesAreTheSameIgnoringCaseAccentsAndScript() {
        #expect(Names.key("ОЛЕНА") == Names.key("Olena") && Names.key(" Oléna ") == Names.key("olena"))
        #expect(Names.key("Олена") != Names.key("Олег"))
        #expect([" ", "Person 3", MeetingNote.callLabel].allSatisfy { Names.key($0) == nil })
    }

    @Test func aNameLinksToThePersonWithItOrMakesOne() throws {
        let (store, dir) = store()
        defer { try? FileManager.default.removeItem(at: dir) }
        let old = try addSample(store, path: "/old.md")
        let new = try addSample(store, path: "/new.md", start: start.addingTimeInterval(3600))
        try store.setName(old, person: "Person 1", to: "Olena K.")
        try store.setName(new, person: "Person 2", to: "OLENA K.") // the same person, shown as she was named first
        let olena = try #require(try store.people(old)[1].person)
        #expect(try store.people(new)[2] == .init(key: "Person 2", name: "Olena K.", person: olena))
        // "you" keeps a name for this note only, and stays You.
        try store.setName(new, person: "Me", to: "Ivan")
        #expect(try store.people(new)[0] == .init(key: "Me", name: "Ivan", person: 1))
        #expect(try store.people(old)[0] == .init(key: "Me", name: nil, person: 1))
        // A typo, then the right name: the typo's person goes with its last meeting.
        try store.setName(new, person: "Person 1", to: "Mrako")
        let typo = try #require(try store.people(new)[1].person)
        try store.setName(new, person: "Person 1", to: nil)
        try store.setName(new, person: "Person 1", to: "Mrako")
        #expect(try store.people(new)[1].person != typo)
        // A label that is a name is that person; "Person N" and the live label are nobody.
        let added = try #require(try store.add(path: "/added.md", start: start.addingTimeInterval(-3600), duration: nil, title: nil,
                                               app: nil, you: nil, entries: [entry("olena k.", 1), entry("Person 4", 2), entry(MeetingNote.callLabel, 3)]))
        #expect(try store.people(added).map(\.person) == [olena, nil, nil])
        // Removing the meetings where Olena is leaves no Olena; naming her again makes a new person.
        try store.remove(old)
        try store.remove(new)
        try store.remove(added)
        _ = try addSample(store)
        try store.setName(try store.meetings()[0].id, person: "Person 1", to: "Olena K.")
        #expect(try store.people(try store.meetings()[0].id)[1].person != olena)
    }

    @Test func aMeetingKeepsEachLinesWordsTalkTimeAndVoiceSample() throws {
        let (store, dir) = store()
        defer { try? FileManager.default.removeItem(at: dir) }
        var vector = [Float](repeating: 0, count: VoiceSample.size)
        vector[3] = 1
        let voice = try #require(VoiceSample(vector))
        let second = MeetingNote.Place(timestamp: "2026-07-31 10:00:03", order: 1)
        let id = try #require(try store.add(path: "/a.md", start: start, duration: 60, title: nil, app: nil, you: "Me",
                                            entries: [.init(label: "Me", timestamp: "2026-07-31 10:00:01", text: "три слова тут", line: 0),
                                                      .init(label: "Person 1", timestamp: "2026-07-31 10:00:03", text: "one", line: 2),
                                                      .init(label: "Person 2", timestamp: "2026-07-31 10:00:03", text: "two words", line: 4)],
                                            samples: [second: voice], seconds: [second: 1.5]))
        let lines = try store.lines(id)
        #expect(lines.map(\.words) == [3, 1, 2] && lines.map(\.seconds) == [nil, nil, 1.5])
        let raw = SQLiteFile(file: dir.appending(path: "meetings.sqlite"), schema: [])
        #expect(try raw.rows("SELECT timestamp, ord, vector FROM samples") { ($0.text(0), $0.int(1), VoiceSample(blob: $0.blob(2))) }
            .map { "\($0.0!) \($0.1) \($0.2 == voice)" } == ["2026-07-31 10:00:03 1 true"])
    }

    @Test func removingAMeetingDeletesItsVoiceSamples() throws {
        let (store, dir) = store()
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = try addSample(store)
        let other = try addSample(store, path: "/b.md")
        let raw = SQLiteFile(file: dir.appending(path: "meetings.sqlite"), schema: [])
        for meeting in [id, other] {
            try raw.run("INSERT INTO samples VALUES (?, '2026-07-31 10:00:03', 0, x'00')", [meeting])
            try raw.run("INSERT INTO declined VALUES (?, 'Person 1', 1)", [meeting])
        }
        try store.remove(id)
        #expect(try raw.rows("SELECT meeting FROM samples UNION ALL SELECT meeting FROM declined") { $0.int(0) } == [other, other])
    }

    @Test func twoPeopleWithOneNameGoToTheOneSeenMostRecently() throws {
        let (store, dir) = store()
        defer { try? FileManager.default.removeItem(at: dir) }
        let older = try addSample(store, path: "/older.md")
        let newer = try addSample(store, path: "/newer.md", start: start.addingTimeInterval(3600))
        try store.setName(older, person: "Person 1", to: "Olena")
        let first = try #require(try store.people(older)[1].person)
        // A second Olena, as Keep both will make: the store is changed by hand here.
        let file = dir.appending(path: "meetings.sqlite")
        try SQLiteFile(file: file, schema: []).run("INSERT INTO persons (id, name) VALUES (99, 'Olena')")
        try SQLiteFile(file: file, schema: []).run("UPDATE people SET person = 99 WHERE meeting = ? AND key = 'Person 2'", [newer])
        let later = try addSample(store, path: "/later.md", start: start.addingTimeInterval(7200))
        try store.setName(later, person: "Person 1", to: "olena")
        #expect(try store.people(later)[1].person == 99)
        #expect(first != 99)
    }

    @Test func version1KeepsEverythingAndItsNamesBecomePersons() throws {
        let (_, dir) = store()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "meetings.sqlite")
        let v1 = SQLiteFile(file: file, schema: MeetingStore.schema)
        let day = start.timeIntervalSince1970
        try v1.run("INSERT INTO meetings (id, path, start, you) VALUES (1, '/a.md', ?, 'Me'), (2, '/b.md', ?, 'Іван'), (3, '/c.md', ?, NULL)",
                   [day, day + 3600, day - 3600])
        // a: you, Person 1 named "Олена", Person 2 unnamed. b (newest): you named for this note, Person 1 named "ОЛЕНА".
        // c (added by hand): labels "olena" and the live label.
        try v1.run("""
            INSERT INTO people (meeting, key, name) VALUES (1, 'Me', NULL), (1, 'Person 1', 'Олена'), (1, 'Person 2', 'Person 5'),
              (2, 'Іван', 'Ivan B.'), (2, 'Person 1', 'ОЛЕНА'), (3, 'olena', NULL), (3, '\(MeetingNote.callLabel)', NULL)
            """)
        try v1.run("INSERT INTO lines VALUES (1, '2026-07-31 10:00:01', 0, 'Person 1', 'Person 2')")

        let store = MeetingStore(file: file)
        #expect(try store.meetings().map(\.id) == [2, 1, 3])
        #expect(try store.lines(1) == [.init(place: .init(timestamp: "2026-07-31 10:00:01", order: 0), original: "Person 1", current: "Person 2")])
        let olena = try #require(try store.people(1)[1].person)
        #expect(try store.people(1) == [.init(key: "Me", name: nil, person: 1), .init(key: "Person 1", name: "ОЛЕНА", person: olena),
                                        .init(key: "Person 2", name: "Person 5")]) // a name that is no person's stays
        #expect(try store.people(2) == [.init(key: "Іван", name: "Ivan B.", person: 1), .init(key: "Person 1", name: "ОЛЕНА", person: olena)])
        #expect(try store.people(3) == [.init(key: "olena", name: "ОЛЕНА", person: olena), .init(key: MeetingNote.callLabel, name: nil)])
        #expect(try SQLiteFile(file: file, schema: []).rows("SELECT count(*) FROM persons") { $0.int(0) } == [2]) // You and Olena
        #expect(try store.knownNames() == ["Ivan B.", "ОЛЕНА", "Me"]) // "you" labels are names, as before
    }

    /// Query plans design §7.1: version 3 adds the indexes the list and a person's meetings need.
    @Test func version2GetsTheIndexesAndItsPlansUseThem() throws {
        let (_, dir) = store()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "meetings.sqlite")
        // Upgrade 2 calls name_key, which SQLite refuses at prepare time without the function.
        let v2 = SQLiteFile(file: file, schema: MeetingStore.schema, upgrades: Array(MeetingStore.upgrades.dropLast()),
                            functions: ["name_key": Names.key])
        try v2.run("INSERT INTO meetings (id, path, start, you) VALUES (1, '/a.md', ?, 'Me')", [start.timeIntervalSince1970])
        try v2.run("INSERT INTO people (meeting, key, person) VALUES (1, 'Me', 1)")
        try v2.run("INSERT INTO lines (meeting, timestamp, ord, original, current, words) VALUES (1, '2026-07-31 10:00:01', 0, 'Me', 'Me', 2)")
        #expect(try v2.rows("SELECT version FROM schema_version") { $0.int(0) } == [2])

        let store = MeetingStore(file: file)
        #expect(try store.meetings().map(\.path) == ["/a.md"])
        #expect(try store.people(1) == [.init(key: "Me", name: nil, person: 1)])
        #expect(try store.lines(1) == [.init(place: .init(timestamp: "2026-07-31 10:00:01", order: 0), original: "Me", current: "Me", words: 2)])
        #expect(try store.sqlite.rows("SELECT version FROM schema_version") { $0.int(0) } == [3])
        #expect(try store.sqlite.rows("SELECT name FROM sqlite_master WHERE type = 'index' AND name NOT LIKE 'sqlite_%' ORDER BY name") {
            $0.text(0)
        } == ["meetings_start", "people_person"])
        // Copies of the SQL meetings(limit:) and meetings(of:) build; a changed query is checked in its task's review.
        func plan(_ sql: String) throws -> String { try store.sqlite.rows("EXPLAIN QUERY PLAN \(sql)") { $0.text(3) }.joined(separator: "\n") }
        let list = try plan("SELECT id, path, title, app, start, duration, you FROM meetings ORDER BY start DESC, id DESC LIMIT ?")
        #expect(list.contains("USING INDEX meetings_start") && !list.contains("TEMP B-TREE"))
        #expect(try plan("""
            SELECT id, path, title, app, start, duration, you FROM meetings
            WHERE id IN (SELECT meeting FROM people WHERE person = ?) ORDER BY start DESC, id DESC
            """).contains("USING INDEX people_person (person=?)"))
    }

    @Test func aFailedChangeLeavesTheDatabaseAsItWas() throws {
        struct Refused: Error {}
        let (store, dir) = store()
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = try addSample(store)
        #expect(throws: Refused.self) {
            try store.transaction {
                try store.setName(id, person: "Person 1", to: "Olena K.")
                try store.merge(id, person: "Person 2", into: "Person 1")
                throw Refused()
            }
        }
        #expect(try store.people(id).allSatisfy { $0.name == nil })
        #expect(try store.lines(id).map(\.current) == ["Me", "Person 1", "Person 2", "Person 1"])
    }

    // Adding from a note (§4)

    @Test func aNoteIsAddedWithItsFrontMatterAndHeaders() throws {
        let (store, dir) = store()
        defer { try? FileManager.default.removeItem(at: dir) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        let note = dir.appending(path: "n.md")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("""
        ---
        date: 2026-07-31
        time: "10:00"
        title: "Sync"
        app: Zoom
        ---
        [Person 1] 2026-07-31 10:00:05
        hi
        [Ivan] 2026-07-31 10:12:30
        bye

        """.utf8).write(to: note)
        let id = try #require(try store.add(note: note, you: "Ivan", calendar: calendar))
        let start = calendar.date(from: DateComponents(year: 2026, month: 7, day: 31, hour: 10))!
        #expect(try store.meetings() == [.init(id: id, path: note.path, title: "Sync", app: "Zoom", start: start, duration: 750, you: "Ivan")])
        #expect(try store.lines(id).map(\.original) == ["Person 1", "Ivan"])
        #expect(try store.add(note: note, you: "Ivan", calendar: calendar) == nil) // listed already
    }

    @Test func whatTheSessionKnowsWinsAndAMissingYouIsNone() throws {
        let (store, dir) = store()
        defer { try? FileManager.default.removeItem(at: dir) }
        let note = dir.appending(path: "n.md")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("[Person 1] 2026-07-31 10:00:05\nhi\n".utf8).write(to: note)
        _ = try #require(try store.add(note: note, you: "Ivan", start: start, duration: 42))
        #expect(try store.meetings().first.map { [$0.start, $0.duration, $0.you] as [AnyHashable?] } == [start, 42.0, nil])
    }

    @Test func aFileWithoutEntriesIsNotATranscript() throws {
        let (store, dir) = store()
        defer { try? FileManager.default.removeItem(at: dir) }
        let note = dir.appending(path: "n.md")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("# Just a note\n".utf8).write(to: note)
        #expect(throws: MeetingStore.NotATranscript.self) { try store.add(note: note, you: nil) }
        #expect(try store.meetings().isEmpty)
    }

    // Changes with the note (§8)

    private let note = """
    ---
    date: 2026-07-31
    time: "10:00"
    ---
    [Ivan] 2026-07-31 10:00:01
    hi
    [Person 1] 2026-07-31 10:00:03
    yes
    [Person 2] 2026-07-31 10:00:05
    I said this in Obsidian, edited
    [Person 1] 2026-07-31 10:00:07
    ok

    """

    /// A store with the note above in `notes/n.md`.
    private func withNote() throws -> (MeetingStore, MeetingStore.Meeting, URL, URL) {
        let (store, dir) = store()
        let notes = dir.appending(path: "notes")
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        let file = notes.appending(path: "n.md")
        try Data(note.utf8).write(to: file)
        _ = try store.add(note: file, you: "Ivan")
        return (store, try #require(try store.meetings().first), file, dir)
    }

    private func headers(_ file: URL) throws -> [String] {
        try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n").filter { $0.hasPrefix("[") }
    }

    @Test func aChangeRewritesOnlyTheHeadersWhoseNameChanged() throws {
        let (store, meeting, file, dir) = try withNote()
        defer { try? FileManager.default.removeItem(at: dir) }
        try store.change([meeting]) { try store.setName(meeting.id, person: "Person 1", to: "Olena K.") }
        #expect(try headers(file) == ["[Ivan] 2026-07-31 10:00:01", "[Olena K.] 2026-07-31 10:00:03", "[Person 2] 2026-07-31 10:00:05",
                                      "[Olena K.] 2026-07-31 10:00:07"])
        #expect(try String(contentsOf: file, encoding: .utf8).contains("I said this in Obsidian, edited"))
        try store.change([meeting]) {
            try store.give(meeting.id, line: .init(timestamp: "2026-07-31 10:00:07", order: 0), to: try store.newPerson(meeting.id))
            try store.give(meeting.id, line: .init(timestamp: "2026-07-31 10:00:01", order: 0), to: "Person 2")
        }
        #expect(try headers(file) == ["[Person 2] 2026-07-31 10:00:01", "[Olena K.] 2026-07-31 10:00:03", "[Person 2] 2026-07-31 10:00:05",
                                      "[Person 3] 2026-07-31 10:00:07"])
        try store.change([meeting]) { try store.reset(meeting.id) }
        #expect(try headers(file) == ["[Ivan] 2026-07-31 10:00:01", "[Olena K.] 2026-07-31 10:00:03", "[Person 2] 2026-07-31 10:00:05",
                                      "[Olena K.] 2026-07-31 10:00:07"])
    }

    @Test func aNoteThatCannotBeWrittenChangesNothing() throws {
        let (store, meeting, file, dir) = try withNote()
        let notes = file.deletingLastPathComponent()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: notes.path)
            try? FileManager.default.removeItem(at: dir)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: notes.path) // no temp file, no rename
        #expect(throws: (any Error).self) { try store.change([meeting]) { try store.setName(meeting.id, person: "Person 1", to: "Olena") } }
        #expect(try store.people(meeting.id).first { $0.key == "Person 1" }?.name == nil)
        #expect(try headers(file)[1] == "[Person 1] 2026-07-31 10:00:03")
    }

    @Test func deletedLinesLeaveTheNoteAndTheStoreAndLaterLinesOfTheirSecondMoveUp() throws {
        let (store, dir) = store()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "d.md")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("""
        ---
        date: 2026-07-31
        time: "10:00"
        ---
        [Ivan] 2026-07-31 10:00:01
        hello all
        [Person 1] 2026-07-31 10:00:03
        hi
        [Person 2] 2026-07-31 10:00:03
        hey
        [Person 1] 2026-07-31 10:00:07
        ok

        ## My notes
        keep this

        """.utf8).write(to: file)
        func at(_ second: Int, _ order: Int) -> MeetingNote.Place { .init(timestamp: "2026-07-31 10:00:0\(second)", order: order) }
        func sample(_ axis: Int) -> VoiceSample {
            var vector = [Float](repeating: 0, count: VoiceSample.size)
            vector[axis] = 1
            return VoiceSample(vector)!
        }
        let id = try #require(try store.add(note: file, you: "Ivan", samples: [at(1, 0): sample(1), at(3, 0): sample(3), at(3, 1): sample(4)]))
        let meeting = try #require(try store.meeting(id))
        /// "second/order axis" of each sample kept.
        func samples() throws -> [String] {
            try store.sqlite.rows("SELECT timestamp, ord, vector FROM samples ORDER BY timestamp, ord") { row in
                VoiceSample(blob: row.blob(2)).map { "\(row.text(0)!.suffix(2))/\(row.int(1)) \($0.vector.firstIndex(of: 1)!)" }
            }
        }

        try store.delete(meeting, lines: [at(3, 0), at(9, 0)]) // a place with no line deletes nothing
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(try headers(file) == ["[Ivan] 2026-07-31 10:00:01", "[Person 2] 2026-07-31 10:00:03", "[Person 1] 2026-07-31 10:00:07"])
        #expect(!text.components(separatedBy: "\n").contains("hi") && text.hasSuffix("ok\n\n## My notes\nkeep this\n"))
        #expect(try store.lines(id).map { "\($0.place.timestamp.suffix(2))/\($0.place.order) \($0.current)" } == ["01/0 Ivan", "03/0 Person 2", "07/0 Person 1"])
        #expect(try samples() == ["01/0 1", "03/0 4"]) // Person 2's sample moved up with the line
        let page = MeetingPage.page(people: try store.people(id), lines: try store.lines(id), you: "Ivan", entries: MeetingNote.parse(text).entries)
        #expect(page.rows.map(\.person) == ["Ivan", "Person 2", "Person 1"])

        try store.delete(meeting, lines: [at(7, 0)]) // all of Person 1's lines: Person 1 leaves the meeting's people
        #expect(try String(contentsOf: file, encoding: .utf8).hasSuffix("hey\n\n## My notes\nkeep this\n")) // text added after a blank line stays
        let after = MeetingPage.page(people: try store.people(id), lines: try store.lines(id), you: "Ivan",
                                     entries: MeetingNote.parse(try String(contentsOf: file, encoding: .utf8)).entries)
        #expect(after.people.map(\.key) == ["Ivan", "Person 2"])
    }

    @Test func aLineNotPairedWithTheNoteIsNotDeleted() throws {
        let (store, meeting, file, dir) = try withNote()
        defer { try? FileManager.default.removeItem(at: dir) }
        // A second entry at 10:00:03 added in Obsidian: that second no longer pairs.
        let edited = note.replacingOccurrences(of: "yes\n", with: "yes\n[Olena] 2026-07-31 10:00:03\nme too\n")
        try Data(edited.utf8).write(to: file)
        try store.delete(meeting, lines: [.init(timestamp: "2026-07-31 10:00:03", order: 0)])
        #expect(try String(contentsOf: file, encoding: .utf8) == edited)
        #expect(try store.lines(meeting.id).count == 4)
    }

    @Test func removingKeepsTheNoteAndAFailedTrashKeepsTheRow() throws {
        let (store, meeting, file, dir) = try withNote()
        defer { try? FileManager.default.removeItem(at: dir) }
        let gone = MeetingStore.Meeting(id: meeting.id, path: dir.appending(path: "gone.md").path, title: nil, app: nil,
                                        start: meeting.start, duration: nil, you: nil)
        #expect(throws: (any Error).self) { try store.remove(gone, trash: true) } // no file to trash: the row stays
        #expect(try store.meetings().count == 1)
        try store.remove(meeting, trash: false)
        #expect(try store.meetings().isEmpty)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }
}
