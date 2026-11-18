import Foundation
import Testing
@testable import Shepit
import ShepitCore

// Voices design §6: the People section's list, choice and deletions. The store's part is tested in MeetingVoicesTests.
@MainActor
struct PeopleModelTests {
    private let note = """
    [Ivan] 2026-07-31 10:00:01
    hi
    [Person 1] 2026-07-31 10:00:03
    yes
    [Person 2] 2026-07-31 10:00:05
    ok

    """

    private func voice(_ axis: Int) -> VoiceSample {
        var vector = [Float](repeating: 0, count: VoiceSample.size)
        vector[axis] = 1
        return VoiceSample(vector)!
    }

    /// A meeting whose every line has a sample; Person 1 is named Olena.
    private func rig(_ defaults: UserDefaults) throws -> (PeopleModel, MeetingStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "people-model-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appending(path: "n.md")
        try Data(note.utf8).write(to: file)
        let store = MeetingStore(file: dir.appending(path: "meetings.sqlite"))
        let places = MeetingNote.places(["2026-07-31 10:00:01", "2026-07-31 10:00:03", "2026-07-31 10:00:05"])
        let id = try #require(try store.add(note: file, you: "Ivan", samples: Dictionary(uniqueKeysWithValues: places.enumerated().map { ($1, voice($0)) })))
        try store.setName(id, person: "Person 1", to: "Olena")
        let model = PeopleModel(store: store, settings: { .defaults }, defaults: defaults)
        model.reload()
        return (model, store, dir)
    }

    private func defaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "people-model-\(UUID().uuidString)"))
    }

    @Test func listsPeopleAndRemembersTheChoice() throws {
        let defaults = try defaults()
        let (model, store, dir) = try rig(defaults)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(model.people.map(\.isYou) == [true, false])
        #expect(model.people[1].name == "Olena")
        #expect(model.chosen == nil)
        model.selection = model.people[1].id
        #expect(model.chosen?.name == "Olena")
        let again = PeopleModel(store: store, settings: { .defaults }, defaults: defaults)
        again.reload()
        #expect(again.chosen?.name == "Olena")
    }

    @Test func deleteVoiceAsksFirst() throws {
        let (model, store, dir) = try rig(try defaults())
        defer { try? FileManager.default.removeItem(at: dir) }
        let olena = model.people[1]
        #expect(olena.voiceMeetings == 1)
        model.question = .deleteVoice(olena)
        model.answer(.deleteVoice(olena), yes: false)
        #expect(model.question == nil)
        #expect(model.people[1].voiceMeetings == 1)
        model.answer(.deleteVoice(olena), yes: true)
        #expect(model.people[1].voiceMeetings == 0)
        #expect(model.people[0].voiceMeetings == 1) // yours stays
        #expect(try store.unnamedVoices(1).count == 1) // and Person 2's
    }

    @Test func deleteAllVoicesAsksFirst() throws {
        let (model, store, dir) = try rig(try defaults())
        defer { try? FileManager.default.removeItem(at: dir) }
        model.answer(.deleteAll, yes: false)
        #expect(try store.voiceRows().count == 2)
        model.answer(.deleteAll, yes: true)
        #expect(try store.voiceRows().isEmpty)
        #expect(try store.unnamedVoices(1).isEmpty)
        #expect(model.people.map(\.voiceMeetings) == [0, 0])
        #expect(model.people.map(\.name) == [Settings.defaults.myName(), "Olena"]) // names stay
    }
}
