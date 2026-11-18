import Foundation
import Testing
@testable import ShepitCore

// Voices design §4, §5: samples in the meetings store, prints that follow corrections, recognition.
struct MeetingVoicesTests {
    private let start = Date(timeIntervalSince1970: 1_785_484_800)

    private func voice(_ axis: Int, _ noise: Int) -> VoiceSample {
        var vector = [Float](repeating: 0, count: VoiceSample.size)
        vector[axis] = 1
        vector[noise] = 0.2
        return VoiceSample(vector)!
    }

    /// A note in `dir` with an entry per label (seconds 1, 2, 3…), listed in `store` with a sample per entry whose
    /// voice is in `voices` (by label: the axis).
    private func meeting(_ store: MeetingStore, _ dir: URL, _ name: String, start: Date, labels: [String],
                         voices: [String: Int]) throws -> MeetingStore.Meeting {
        let timestamps = labels.indices.map { "2026-07-31 10:00:\(String(format: "%02d", $0 + 1))" }
        let note = zip(labels, timestamps).map { "[\($0)] \($1)\ntext\n" }.joined(separator: "\n")
        let file = dir.appending(path: "\(name).md")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(note.utf8).write(to: file)
        var samples: [MeetingNote.Place: VoiceSample] = [:]
        for (index, place) in MeetingNote.places(timestamps).enumerated() {
            if let axis = voices[labels[index]] { samples[place] = voice(axis, 100 + index) }
        }
        let id = try #require(try store.add(note: file, you: "Me", start: start, samples: samples))
        return try #require(try store.meetings().first { $0.id == id })
    }

    private func setUp() -> (MeetingStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "meeting-voices-\(UUID().uuidString)")
        return (MeetingStore(file: dir.appending(path: "meetings.sqlite")), dir)
    }

    private func headers(_ meeting: MeetingStore.Meeting) throws -> [String] {
        try String(contentsOf: URL(fileURLWithPath: meeting.path), encoding: .utf8).components(separatedBy: "\n")
            .filter { $0.hasPrefix("[") }.map { String($0.prefix { $0 != "]" }.dropFirst()) }
    }

    @Test func aPrintFollowsTheCorrections() throws {
        let (store, dir) = setUp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = try meeting(store, dir, "a", start: start, labels: ["Person 1", "Person 1", "Person 1", "Person 2", "Person 2"],
                            voices: ["Person 1": 1, "Person 2": 2])
        #expect(try store.voiceRows().isEmpty) // nobody named yet
        try store.setName(a.id, person: "Person 1", to: "Olena")
        let olena = try #require(try store.people(a.id)[0].person)
        func count() throws -> Int { try store.voiceRows().filter { $0.person == olena }.count }
        #expect(try count() == 3)
        try store.give(a.id, line: .init(timestamp: "2026-07-31 10:00:01", order: 0), to: "Person 2")
        #expect(try count() == 2)
        try store.reset(a.id)
        #expect(try count() == 3)
        try store.merge(a.id, person: "Person 2", into: "Person 1")
        #expect(try count() == 5)
        #expect(try store.voiceRows(except: a.id).isEmpty)
        try store.remove(a.id)
        #expect(try store.voiceRows().isEmpty)
    }

    @Test func aNewMeetingsPeopleAreNamedByVoiceInTheNoteToo() throws {
        let (store, dir) = setUp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let three = ["Person 1", "Person 1", "Person 1", "Person 2", "Person 2", "Person 2"]
        let old = try meeting(store, dir, "old", start: start, labels: ["Me"] + three, voices: ["Person 1": 1, "Person 2": 2])
        try store.setName(old.id, person: "Person 1", to: "Olena")
        try store.merge(old.id, person: "Person 2", into: "Me") // your voice heard through the call
        let new = try meeting(store, dir, "new", start: start.addingTimeInterval(86_400),
                              labels: ["Me"] + three + ["Person 3", "Person 3", "Person 3"],
                              voices: ["Person 1": 1, "Person 2": 2, "Person 3": 3])
        #expect(try store.recognise(new) == 2)
        let people = try store.people(new.id)
        #expect(people.first { $0.key == "Person 1" }.map { ($0.name, $0.recognised) } ?? (nil, false) == ("Olena", true))
        #expect(try store.lines(new.id).filter { $0.original == "Person 2" }.allSatisfy { $0.current == "Me" })
        #expect(people.first { $0.key == "Person 3" }?.person == nil) // nobody like that
        #expect(try headers(new) == ["Me", "Olena", "Olena", "Olena", "Me", "Me", "Me", "Person 3", "Person 3", "Person 3"])
        #expect(try store.recognise(new) == 0) // only people with no person yet
        // A name changed by the author drops the mark.
        try store.setName(new.id, person: "Person 1", to: "Olena K.")
        #expect(try store.people(new.id).first { $0.key == "Person 1" }?.recognised == false)
    }

    @Test func unnamedVoicesGoAfterThirtyDays() throws {
        let (store, dir) = setUp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let labels = ["Person 1", "Person 1", "Person 1", "Person 2"]
        let old = try meeting(store, dir, "old", start: start, labels: labels, voices: ["Person 1": 1, "Person 2": 2])
        let new = try meeting(store, dir, "new", start: start.addingTimeInterval(20 * 86_400), labels: labels, voices: ["Person 1": 1, "Person 2": 2])
        try store.setName(old.id, person: "Person 1", to: "Olena")
        try store.forgetUnnamedVoices(before: start.addingTimeInterval(86_400))
        #expect(try store.voiceRows().count == 3) // Olena's, kept
        #expect(try store.unnamedVoices(old.id).isEmpty)
        #expect(try store.unnamedVoices(new.id).mapValues(\.count) == ["Person 1": 3, "Person 2": 1])
    }

    // MARK: People (voices design §6)

    @Test func summariesAndPresencesAreThePeopleWithLinesInEachMeeting() throws {
        let (store, dir) = setUp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = try meeting(store, dir, "a", start: start, labels: ["Me", "Person 1", "Person 1", "Person 2"],
                            voices: ["Person 1": 1, "Person 2": 2])
        let b = try meeting(store, dir, "b", start: start + 3600, labels: ["Me", "Person 1", "Person 2", "Person 3"], voices: [:])
        try store.setName(a.id, person: "Person 1", to: "Olena")
        try store.setName(a.id, person: "Person 2", to: "Marko")
        try store.give(a.id, line: .init(timestamp: "2026-07-31 10:00:04", order: 0), to: "Person 1") // Marko has no line left in a
        try store.setName(b.id, person: "Person 1", to: "Olena")
        try store.setName(b.id, person: "Person 2", to: "OLENA") // one person twice in a meeting: one presence
        let you = try #require(try store.people(a.id)[0].person), olena = try #require(try store.people(a.id)[1].person)
        func presences(_ person: Int, since: Date? = nil) throws -> [MeetingStore.Presence] {
            try store.presences(of: person, since: since).sorted { $0.meeting < $1.meeting }
        }
        #expect(try presences(you) == [.init(meeting: a.id, words: 1, meetingWords: 4), .init(meeting: b.id, words: 1, meetingWords: 4)])
        #expect(try presences(olena) == [.init(meeting: a.id, words: 3, meetingWords: 4),
                                         .init(meeting: b.id, words: 2, meetingWords: 4)]) // both her labels in b: once
        #expect(try presences(olena, since: start + 1) == [.init(meeting: b.id, words: 2, meetingWords: 4)])
        #expect(try MeetingStore(file: dir.appending(path: "none.sqlite")).presences(of: you).isEmpty)
        // People's list: a row each, the meetings counted once; Marko has no line left.
        #expect(try store.summaries().sorted { $0.person < $1.person } == [
            .init(person: you, name: nil, you: true, meetings: 2, last: start + 3600, voiceMeetings: 0),
            .init(person: olena, name: "Olena", you: false, meetings: 2, last: start + 3600, voiceMeetings: 1),
        ])
        #expect(try MeetingStore(file: dir.appending(path: "none.sqlite")).summaries().isEmpty)
    }

    @Test func deleteVoiceTakesOnlyThatPersonsSamples() throws {
        let (store, dir) = setUp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = try meeting(store, dir, "a", start: start, labels: ["Person 1", "Person 2"], voices: ["Person 1": 1, "Person 2": 2])
        let b = try meeting(store, dir, "b", start: start + 3600, labels: ["Person 1", "Person 2"], voices: ["Person 1": 1, "Person 2": 3])
        try store.setName(a.id, person: "Person 1", to: "Olena")
        try store.setName(a.id, person: "Person 2", to: "Marko")
        try store.setName(b.id, person: "Person 1", to: "Olena")
        let olena = try #require(try store.people(a.id)[0].person)
        try store.deleteVoice(olena)
        #expect(try store.summaries().first { $0.person == olena }.map { [$0.meetings, $0.voiceMeetings] } == [2, 0]) // she stays
        #expect(try store.voiceRows().count == 1) // Marko's
        #expect(try store.unnamedVoices(b.id).mapValues(\.count) == ["Person 2": 1])
        try store.deleteAllVoices()
        #expect(try store.voiceRows().isEmpty)
        #expect(try store.unnamedVoices(b.id).isEmpty)
        #expect(try store.people(a.id).map(\.name) == ["Olena", "Marko"]) // names stay
    }

    /// Biometric data: every way out overwrites the sample, not only unlinks it (macOS's default `secure_delete = FAST`
    /// leaves freed pages as they were).
    @Test func deletedVoicesLeaveNoTraceInTheFile() throws {
        let (store, dir) = setUp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let named = try meeting(store, dir, "a", start: start, labels: ["Person 1"], voices: ["Person 1": 1])
        _ = try meeting(store, dir, "b", start: start, labels: ["Person 1"], voices: ["Person 1": 2])
        let removed = try meeting(store, dir, "c", start: start, labels: ["Person 1"], voices: ["Person 1": 3])
        let kept = try meeting(store, dir, "d", start: start + 40 * 86_400, labels: ["Person 1"], voices: ["Person 1": 4])
        try store.setName(named.id, person: "Person 1", to: "Olena")
        try store.setName(kept.id, person: "Person 1", to: "Marko")
        func inFile(_ axis: Int) throws -> Bool { try Data(contentsOf: dir.appending(path: "meetings.sqlite")).range(of: voice(axis, 100).blob) != nil }
        #expect(try inFile(1) && inFile(2) && inFile(3) && inFile(4))
        try store.deleteVoice(try #require(try store.people(named.id)[0].person))
        try store.forgetUnnamedVoices(before: start + 30 * 86_400)
        try store.remove(removed.id)
        #expect(try !inFile(1) && !inFile(2) && !inFile(3))
        #expect(try inFile(4))
        try store.deleteAllVoices()
        #expect(try !inFile(4))
    }

    // MARK: Rename and merge across meetings (voices design §6)

    /// Names a meeting's person in the store and the note, as the Meetings section does.
    private func name(_ store: MeetingStore, _ meeting: MeetingStore.Meeting, _ key: String, _ name: String) throws {
        try store.change([meeting]) { try store.setName(meeting.id, person: key, to: name) }
    }

    private func text(_ meeting: MeetingStore.Meeting) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: meeting.path), encoding: .utf8)
    }

    @Test func renameChangesThePersonInEveryMeetingAndNote() throws {
        let (store, dir) = setUp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = try meeting(store, dir, "a", start: start, labels: ["Me", "Person 1", "Person 2"], voices: [:])
        let b = try meeting(store, dir, "b", start: start + 86_400, labels: ["Person 1", "Me"], voices: [:])
        let c = try meeting(store, dir, "c", start: start + 2 * 86_400, labels: ["Person 1"], voices: [:])
        try name(store, a, "Person 1", "Olena")
        try name(store, b, "Person 1", "olena")
        try name(store, c, "Person 1", "Olena")
        let olena = try #require(try store.people(a.id)[1].person)
        try Data((try text(b) + "added in Obsidian\n").utf8).write(to: URL(fileURLWithPath: b.path))
        try FileManager.default.removeItem(atPath: c.path) // a missing note changes only the store
        try store.rename(person: olena, to: "Olena K.")
        #expect(try headers(a) == ["Me", "Olena K.", "Person 2"])
        #expect(try headers(b) == ["Olena K.", "Me"])
        #expect(try text(b).hasSuffix("added in Obsidian\n"))
        #expect(try [a, b, c].map { try store.people($0.id).first { $0.person == olena }?.name } == ["Olena K.", "Olena K.", "Olena K."])
    }

    @Test func aNoteThatCannotBeWrittenLeavesEveryNoteAndTheStore() throws {
        let (store, dir) = setUp()
        let locked = dir.appending(path: "locked")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            try? FileManager.default.removeItem(at: dir)
        }
        // Written newest first: the oldest note, the last one, fails after the other two were written.
        let a = try meeting(store, dir, "a", start: start + 2 * 86_400, labels: ["Person 1"], voices: [:])
        let b = try meeting(store, dir, "b", start: start + 86_400, labels: ["Person 1"], voices: [:])
        let c = try meeting(store, locked, "c", start: start, labels: ["Person 1"], voices: [:])
        for meeting in [a, b, c] { try name(store, meeting, "Person 1", "Olena") }
        let olena = try #require(try store.people(a.id)[0].person)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path) // no temp file, no rename
        let error = #expect(throws: MeetingStore.NoteNotChanged.self) { try store.rename(person: olena, to: "Olena K.") }
        #expect(error?.path == c.path)
        #expect(try [a, b, c].map { try headers($0) } == [["Olena"], ["Olena"], ["Olena"]])
        #expect(try [a, b, c].map { try store.people($0.id)[0].name } == ["Olena", "Olena", "Olena"])
    }

    @Test func mergeMovesEveryMeetingOfThePersonToTheOther() throws {
        let (store, dir) = setUp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = try meeting(store, dir, "a", start: start, labels: ["Me", "Person 1", "Person 2"], voices: ["Person 1": 1, "Person 2": 2])
        let b = try meeting(store, dir, "b", start: start + 86_400, labels: ["Person 1", "Me"], voices: ["Person 1": 1])
        try name(store, a, "Person 1", "Olena")
        try name(store, a, "Person 2", "Marko")
        try name(store, b, "Person 1", "Olena")
        let olena = try #require(try store.people(a.id)[1].person), marko = try #require(try store.people(a.id)[2].person)
        try store.merge(person: olena, into: marko, myName: "Me")
        // In a meeting with both, her lines go to his label; elsewhere her label becomes him.
        #expect(try headers(a) == ["Me", "Marko", "Marko"])
        #expect(try store.lines(a.id).map(\.current) == ["Me", "Person 2", "Person 2"])
        #expect(try headers(b) == ["Marko", "Me"])
        #expect(try store.people(b.id)[0].person == marko)
        #expect(try store.voiceRows().filter { $0.person == marko }.count == 3) // her samples count for him
        #expect(try !store.summaries().contains { $0.person == olena })
        #expect(try !store.knownNames().contains("Olena")) // she is gone
    }

    @Test func mergeIntoYouMakesThePersonYou() throws {
        let (store, dir) = setUp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = try meeting(store, dir, "a", start: start, labels: ["Me", "Person 1"], voices: [:])
        let b = try meeting(store, dir, "b", start: start + 86_400, labels: ["Ivan", "Person 1"], voices: [:]) // a note with no "Me"
        try name(store, a, "Person 1", "Ivan") // your voice through the call, named by hand
        let you = try #require(try store.people(a.id)[0].person), ivan = try #require(try store.people(b.id)[0].person)
        #expect(try store.people(a.id)[1].person == ivan)
        try store.merge(person: ivan, into: you, myName: "Ivan B.")
        #expect(try headers(a) == ["Me", "Me"])
        #expect(try headers(b) == ["Ivan B.", "Person 1"])
        #expect(try store.meeting(b.id)?.you == "Ivan")
        #expect(try store.people(b.id)[0] == .init(key: "Ivan", name: "Ivan B.", person: you))
        #expect(try store.presences(of: you).map(\.meeting).sorted() == [a.id, b.id])
        #expect(try !store.summaries().contains { $0.person == ivan })
    }

    // MARK: May also be in (voices design §6)

    @Test func suggestedVoicesLeaveOutThePersonsMeetingsNamedPeopleAndDeclinedOnes() throws {
        let (store, dir) = setUp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let three = ["Person 1", "Person 1", "Person 1"]
        let a = try meeting(store, dir, "a", start: start, labels: three, voices: ["Person 1": 1])
        let b = try meeting(store, dir, "b", start: start + 86_400, labels: three + ["Person 2"], voices: ["Person 1": 1, "Person 2": 2])
        let c = try meeting(store, dir, "c", start: start + 2 * 86_400, labels: three + ["Person 2"], voices: ["Person 1": 1, "Person 2": 1])
        try name(store, a, "Person 1", "Olena")
        try name(store, b, "Person 2", "Marko")
        let olena = try #require(try store.people(a.id)[0].person), marko = try #require(try store.people(b.id)[1].person)
        func counts(_ person: Int) throws -> [Int: [String: Int]] { try store.suggestedVoices(for: person).mapValues { $0.mapValues(\.count) } }
        #expect(try counts(olena) == [b.id: ["Person 1": 3], c.id: ["Person 1": 3, "Person 2": 1]])

        try store.nameSuggested(olena, named: [b.id: "Person 1"], declined: [c.id: "Person 1"])
        #expect(try store.people(b.id)[0] == .init(key: "Person 1", name: "Olena", person: olena)) // named by the author
        #expect(try headers(b) == ["Olena", "Olena", "Olena", "Marko"])
        #expect(try counts(olena) == [c.id: ["Person 2": 1]])
        // A person named meanwhile keeps their name.
        try name(store, c, "Person 2", "Taras")
        try store.nameSuggested(olena, named: [c.id: "Person 2"], declined: [:])
        #expect(try store.people(c.id)[1].name == "Taras")

        // Merged into Marko, Olena's declined ones are his.
        try store.merge(person: olena, into: marko, myName: "Me")
        #expect(try counts(marko).isEmpty)
    }

    // MARK: Who talked how much (voices design §6)

    @Test func presencesCountWordsAndTalkTimeAndOlderMeetingsGetTheirWords() throws {
        let (store, dir) = setUp()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appending(path: "n.md")
        let times = (1...4).map { "2026-07-31 10:00:0\($0)" }
        let note = zip(["Me", "Person 1", "Person 1", "Person 2"], ["one two three", "four five", MeetingQueue.failedText, "six"])
        try Data(zip(note, times).map { "[\($0.0)] \($1)\n\($0.1)\n" }.joined(separator: "\n").utf8).write(to: file)
        let places = MeetingNote.places(times)
        let id = try #require(try store.add(note: file, you: "Me", seconds: [places[0]: 2.5, places[1]: 1.5]))
        try store.setName(id, person: "Person 1", to: "Olena")
        let people = try store.people(id).compactMap(\.person) // you, Olena
        func presences() throws -> [MeetingStore.Presence] { try people.flatMap { try store.presences(of: $0) } }
        #expect(try presences().map(\.words) == [3, 2]) // a line not recognised has no words
        #expect(try presences().map(\.seconds) == [2.5, 1.5])
        #expect(try presences().map(\.meetingWords) == [6, 6])

        // A meeting listed before words were kept gets them from its note.
        #expect(try store.meetingsWithoutWords().isEmpty)
        try SQLiteFile(file: dir.appending(path: "meetings.sqlite"), schema: []).run("UPDATE lines SET words = NULL")
        #expect(try presences().map(\.words) == [nil, nil])
        #expect(try store.meetingsWithoutWords().map(\.id) == [id])
        let entries = MeetingNote.parse(try String(contentsOf: file, encoding: .utf8)).entries
        try store.fillWords(id, entries: entries)
        #expect(try presences().map(\.words) == [3, 2])
        #expect(try presences().map(\.meetingWords) == [6, 6])
        #expect(try store.meetingsWithoutWords().isEmpty)
        // Only where there are none: a note edited later doesn't change them.
        try store.fillWords(id, entries: entries.map { var entry = $0; entry.text += " more"; return entry })
        #expect(try presences().map(\.words) == [3, 2])
    }
}
