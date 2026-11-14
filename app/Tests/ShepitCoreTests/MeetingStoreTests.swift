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
            .init(timestamp: "2026-07-31 10:00:01", order: 0, original: "Me", current: "Me"),
            .init(timestamp: "2026-07-31 10:00:03", order: 0, original: "Person 1", current: "Person 1"),
            .init(timestamp: "2026-07-31 10:00:03", order: 1, original: "Person 2", current: "Person 2"),
            .init(timestamp: "2026-07-31 10:00:05", order: 0, original: "Person 1", current: "Person 1"),
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

    @Test func suggestedNamesComeFromOtherMeetingsNewestFirst() throws {
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
        #expect(try store.suggestedNames(excluding: this) == ["Anna", "Olena K.", "Marko D."])
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
}
