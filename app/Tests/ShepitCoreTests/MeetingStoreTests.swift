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
        #expect(try store.people(id) == [.init(key: "Me", name: nil), .init(key: "Person 1", name: nil), .init(key: "Person 2", name: nil)])
        #expect(try store.lines(id) == [
            .init(place: .init(timestamp: "2026-07-31 10:00:01", order: 0), original: "Me", current: "Me"),
            .init(place: .init(timestamp: "2026-07-31 10:00:03", order: 0), original: "Person 1", current: "Person 1"),
            .init(place: .init(timestamp: "2026-07-31 10:00:03", order: 1), original: "Person 2", current: "Person 2"),
            .init(place: .init(timestamp: "2026-07-31 10:00:05", order: 0), original: "Person 1", current: "Person 1"),
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
}
