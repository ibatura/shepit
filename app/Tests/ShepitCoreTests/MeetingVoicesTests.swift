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
}
