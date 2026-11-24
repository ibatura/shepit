import Foundation
import Testing
@testable import Shepit
@testable import ShepitCore

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

    @Test func deleteVoiceAsksFirst() async throws {
        let (model, store, dir) = try rig(try defaults())
        defer { try? FileManager.default.removeItem(at: dir) }
        let olena = model.people[1]
        #expect(olena.voiceMeetings == 1)
        model.question = .deleteVoice(olena)
        await model.answer(.deleteVoice(olena), yes: false)
        #expect(model.question == nil)
        #expect(model.people[1].voiceMeetings == 1)
        await model.answer(.deleteVoice(olena), yes: true)
        #expect(model.people[1].voiceMeetings == 0)
        #expect(model.people[0].voiceMeetings == 1) // yours stays
        #expect(try store.unnamedVoices(1).count == 1) // and Person 2's
    }

    @Test func deleteAllVoicesAsksFirst() async throws {
        let (model, store, dir) = try rig(try defaults())
        defer { try? FileManager.default.removeItem(at: dir) }
        await model.answer(.deleteAll, yes: false)
        #expect(try store.voiceRows().count == 2)
        await model.answer(.deleteAll, yes: true)
        #expect(try store.voiceRows().isEmpty)
        #expect(try store.unnamedVoices(1).isEmpty)
        #expect(model.people.map(\.voiceMeetings) == [0, 0])
        #expect(model.people.map(\.name) == [Settings.defaults.myName(), "Olena"]) // names stay
    }

    @Test func renameAsksWhenAnotherPersonHasTheName() async throws {
        let (model, store, dir) = try rig(try defaults())
        defer { try? FileManager.default.removeItem(at: dir) }
        let meeting = try #require(try store.meetings().first)
        try store.change([meeting]) { try store.setName(meeting.id, person: "Person 2", to: "Marko") }
        model.reload()
        let olena = try #require(model.people.first { $0.name == "Olena" }), marko = try #require(model.people.first { $0.name == "Marko" })
        for typed in ["", " Olena ", "Person 4"] { await model.rename(olena, typed: typed) } // nothing to save
        #expect(model.question == nil)
        await model.rename(olena, typed: "marko")
        #expect(model.question == .taken(olena, name: "marko", by: marko))
        #expect(model.people.map(\.name) == [Settings.defaults.myName(), "Olena", "Marko"])
        await model.rename(olena, typed: " Olena K. ")
        #expect(model.people.map(\.name) == [Settings.defaults.myName(), "Olena K.", "Marko"])
        await model.rename(model.people[1], typed: "marko")
        await model.keepBoth(try #require(model.question))
        #expect(model.question == nil)
        #expect(model.people.map(\.name) == [Settings.defaults.myName(), "marko", "Marko"])
    }

    @Test func renameAsksAlsoForTheNameOfSomeoneWithNoLinesLeft() async throws {
        let (model, store, dir) = try rig(try defaults())
        defer { try? FileManager.default.removeItem(at: dir) }
        let meeting = try #require(try store.meetings().first)
        try store.change([meeting]) { try store.setName(meeting.id, person: "Person 2", to: "Marko") }
        let marko = try #require(try store.people(meeting.id)[2].person)
        try store.give(meeting.id, line: .init(timestamp: "2026-07-31 10:00:05", order: 0), to: "Person 1") // Marko's only line
        model.reload()
        #expect(!model.people.contains { $0.id == marko }) // not listed
        await model.rename(try #require(model.people.first { $0.name == "Olena" }), typed: "MARKO")
        guard case .taken(_, "MARKO", let other) = model.question else { Issue.record("no question"); return }
        #expect(other.id == marko && other.name == "Marko")
    }

    @Test func mergeChoosesTheOtherPerson() async throws {
        let (model, store, dir) = try rig(try defaults())
        defer { try? FileManager.default.removeItem(at: dir) }
        let meeting = try #require(try store.meetings().first)
        try store.change([meeting]) { try store.setName(meeting.id, person: "Person 2", to: "Marko") }
        model.reload()
        model.selection = model.people[1].id
        await model.merge(model.people[1], into: model.people[2])
        #expect(model.people.map(\.name) == [Settings.defaults.myName(), "Marko"])
        #expect(model.chosen?.name == "Marko")
        #expect(model.notice == nil)
    }

    @Test func suggestionsForTheChosenPersonWhileRememberVoicesIsOn() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "people-model-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = MeetingStore(file: dir.appending(path: "meetings.sqlite"))
        let times = ["2026-07-31 10:00:01", "2026-07-31 10:00:02", "2026-07-31 10:00:03"]
        var ids: [Int] = []
        for name in ["old", "new"] {
            let file = dir.appending(path: "\(name).md")
            try Data(times.map { "[Person 1] \($0)\nyes\n" }.joined(separator: "\n").utf8).write(to: file)
            let samples = Dictionary(uniqueKeysWithValues: MeetingNote.places(times).map { ($0, voice(1)) })
            ids.append(try #require(try store.add(note: file, you: "Ivan", samples: samples)))
        }
        try store.setName(ids[0], person: "Person 1", to: "Olena")
        var settings = Settings.defaults
        let model = PeopleModel(store: store, settings: { settings }, defaults: try defaults())
        model.reload()
        model.selection = try #require(model.people.first { $0.name == "Olena" }).id
        #expect(model.suggestions.isEmpty) // Remember voices is off
        settings.rememberVoices = true
        model.reload()
        #expect(model.suggestions.isEmpty) // until the prints are read, off the main thread
        await model.reading?.value
        #expect(model.suggestions.map(\.key) == ["Person 1"])
        model.selection = nil
        #expect(model.suggestions.isEmpty)
        model.selection = model.people.first { $0.name == "Olena" }?.id
        #expect(model.reading == nil && model.suggestions.map(\.key) == ["Person 1"]) // the store didn't change: read once
        let olena = try #require(model.chosen)
        await model.name(olena, suggestions: model.suggestions, checked: [ids[1]])
        #expect(try store.people(ids[1])[0].person == olena.id)
        #expect(model.suggestions.isEmpty)
    }

    @Test func talkAndMeetingsFollowThePeriodWhichIsRemembered() throws {
        let defaults = try defaults()
        let (model, store, dir) = try rig(defaults)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(model.talk.isEmpty && model.meetingRows.isEmpty) // nobody chosen
        model.selection = model.people[1].id
        model.period = .preset(.all)
        #expect(model.talk.map(\.value) == ["1", "–", "1", "33%"])
        #expect(model.meetingRows.map(\.talk) == ["– · 1 words"])
        model.period = .preset(.today)
        #expect(model.talk.map(\.value) == ["0", "–", "–", "–"])
        #expect(model.meetingRows.isEmpty)
        #expect(PeopleModel(store: store, settings: { .defaults }, defaults: defaults).period == .preset(.today))
    }

    @Test func wordsOfOlderMeetingsAreFilledOnce() async throws {
        let (model, store, dir) = try rig(try defaults())
        defer { try? FileManager.default.removeItem(at: dir) }
        try SQLiteFile(file: dir.appending(path: "meetings.sqlite"), schema: []).run("UPDATE lines SET words = NULL")
        model.reload()
        model.selection = model.people[1].id
        model.period = .preset(.all)
        #expect(model.talk.map(\.value) == ["1", "–", "–", "–"])
        await model.fillWords()
        #expect(model.talk.map(\.value) == ["1", "–", "1", "33%"])
        try SQLiteFile(file: dir.appending(path: "meetings.sqlite"), schema: []).run("UPDATE lines SET words = NULL")
        await model.fillWords() // once per run
        #expect(try store.meetingsWithoutWords().count == 1)
    }
}
