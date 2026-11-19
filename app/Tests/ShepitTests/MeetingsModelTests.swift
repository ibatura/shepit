import Foundation
import Testing
@testable import Shepit
import ShepitCore

// Meetings design §6, §8: the questions, notices and choices of the Meetings section. The note and store changes themselves are tested in MeetingStoreTests.
@MainActor
struct MeetingsModelTests {
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

    private func rig() throws -> (MeetingsModel, MeetingStore, Int, URL, URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "meetings-model-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appending(path: "n.md")
        try Data(note.utf8).write(to: file)
        let store = MeetingStore(file: dir.appending(path: "meetings.sqlite"))
        let id = try #require(try store.add(note: file, you: "Ivan"))
        let defaults = try #require(UserDefaults(suiteName: "meetings-model-\(UUID().uuidString)"))
        let model = MeetingsModel(store: store, settings: { .defaults }, defaults: defaults)
        model.reload()
        return (model, store, id, file, dir)
    }

    private func headers(_ file: URL) throws -> [String] {
        try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n").filter { $0.hasPrefix("[") }
    }

    @Test func aNameAnotherPersonHasAsksToMergeFirst() async throws {
        let (model, store, id, file, dir) = try rig()
        defer { try? FileManager.default.removeItem(at: dir) }
        await model.name(id, person: "Person 1", typed: "Olena")
        await model.name(id, person: "Person 2", typed: "olena")
        #expect(model.question == .merge(meeting: id, person: "Person 2", into: "Person 1", name: "olena"))
        #expect(try store.people(id).first { $0.key == "Person 2" }?.name == nil) // nothing yet
        await model.answer(model.question!, yes: false)
        #expect(model.cancels == 1) // the name fields drop the typed name
        #expect(try headers(file)[2] == "[Person 2] 2026-07-31 10:00:05")
        await model.name(id, person: "Person 2", typed: "Olena")
        await model.answer(model.question!, yes: true)
        #expect(model.question == nil)
        #expect(try headers(file)[2] == "[Olena] 2026-07-31 10:00:05")
        #expect(try store.lines(id).map(\.current) == ["Ivan", "Person 1", "Person 1", "Person 1"])
    }

    @Test func aLineIsDeletedAtOnceAndAllOfAPersonsLinesAfterTheQuestion() async throws {
        let (model, store, id, file, dir) = try rig()
        defer { try? FileManager.default.removeItem(at: dir) }
        await model.delete(id, lines: [.init(timestamp: "2026-07-31 10:00:05", order: 0)])
        #expect(try headers(file) == ["[Ivan] 2026-07-31 10:00:01", "[Person 1] 2026-07-31 10:00:03", "[Person 1] 2026-07-31 10:00:07"])
        let theirs: Set<MeetingNote.Place> = [.init(timestamp: "2026-07-31 10:00:03", order: 0), .init(timestamp: "2026-07-31 10:00:07", order: 0)]
        model.question = .deleteLines(meeting: id, name: "Person 1", lines: theirs)
        await model.answer(model.question!, yes: false)
        #expect(try headers(file).count == 3)
        model.question = .deleteLines(meeting: id, name: "Person 1", lines: theirs)
        await model.answer(model.question!, yes: true)
        #expect(try headers(file) == ["[Ivan] 2026-07-31 10:00:01"])
        #expect(try store.lines(id).map(\.current) == ["Ivan"])
    }

    @Test func aNoteThatCannotBeWrittenChangesNothing() async throws {
        let (model, store, id, file, dir) = try rig()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
            try? FileManager.default.removeItem(at: dir)
        }
        let notes = dir.appending(path: "notes")
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        let locked = notes.appending(path: "n.md")
        try FileManager.default.moveItem(at: file, to: locked)
        try store.relink(id, path: locked.path)
        model.reload()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: notes.path) // no temp file, no rename
        await model.name(id, person: "Person 1", typed: "Olena")
        #expect(model.notice?.title == "Can't change n.md")
        #expect(try store.people(id).first { $0.key == "Person 1" }?.name == nil)
        #expect(try headers(locked)[1] == "[Person 1] 2026-07-31 10:00:03")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: notes.path)
    }

    @Test func aNoteGoneSinceItWasOpenedChangesNothing() async throws {
        let (model, store, id, file, dir) = try rig()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.removeItem(at: file)
        await model.name(id, person: "Person 1", typed: "Olena")
        #expect(model.notice?.title == "Can't change n.md")
        #expect(try store.people(id).first { $0.key == "Person 1" }?.name == nil)
        #expect(model.missing.contains(id))
    }

    @Test func removeFromListKeepsTheNote() async throws {
        let (model, store, id, file, dir) = try rig()
        defer { try? FileManager.default.removeItem(at: dir) }
        model.selection = .meeting(id)
        await model.answer(.remove(try #require(model.meetings.first)), yes: true)
        #expect(try store.meetings().isEmpty)
        #expect(model.selection == nil)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func theFinishedTranscriptStaysChosenAndNamePeopleOpensIt() async throws {
        let (model, _, id, _, dir) = try rig()
        defer { try? FileManager.default.removeItem(at: dir) }
        model.selection = .running
        model.added(id)
        #expect(model.selection == .meeting(id))
        model.selection = nil
        model.added(id + 1) // not chosen: nothing was running in the window
        #expect(model.selection == nil)
        model.chooseLastAdded()
        #expect(model.selection == .meeting(id + 1))
    }
}
