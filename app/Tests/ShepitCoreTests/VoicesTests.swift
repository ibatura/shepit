import Foundation
import Testing
@testable import ShepitCore

// Voices design §4: voice samples.
struct VoicesTests {
    /// A sample pointing along axis `axis` (with a little of axis 0 so two axes aren't orthogonal by accident).
    private func voice(_ axis: Int, _ weight: Float = 1) -> VoiceSample {
        var vector = [Float](repeating: 0, count: VoiceSample.size)
        vector[axis] = weight
        return VoiceSample(vector)!
    }

    @Test func aSampleIsNormalisedAndKeptAsABlob() throws {
        let sample = try #require(VoiceSample([3, 4] + [Float](repeating: 0, count: 254)))
        #expect(sample.vector[0] == 0.6 && sample.vector[1] == 0.8)
        #expect(VoiceSample(blob: sample.blob) == sample && sample.blob.count == 1024)
        #expect(VoiceSample(blob: Data([0, 1, 2])) == nil)
        #expect(VoiceSample([1, 2]) == nil && VoiceSample([Float](repeating: 0, count: 256)) == nil)
        #expect(VoiceSample.mean([voice(1), voice(2)])?.vector[1] == 1 / Float(2).squareRoot())
        #expect(VoiceSample.mean([]) == nil)
    }

    @Test func aLineGetsTheWindowsOfItsOwnSpeakerThatOverlapIt() {
        let diarization = Diarization(
            turns: [SpeakerTurn(speaker: "S1", start: 0, end: 10), SpeakerTurn(speaker: "S2", start: 10, end: 20)],
            windows: [VoiceWindow(speaker: "S1", start: 0, end: 6, sample: voice(1)), VoiceWindow(speaker: "S1", start: 4, end: 9, sample: voice(2)),
                      VoiceWindow(speaker: "S2", start: 3, end: 5, sample: voice(3)), // another voice in the same window
                      VoiceWindow(speaker: "S2", start: 12, end: 18, sample: voice(4))])
        let samples = Voices.lineSamples([1..<5, 7..<9, 12..<13, 30..<31], diarization)
        #expect(samples[0] == VoiceSample.mean([voice(1), voice(2)]))
        #expect(samples[1] == voice(2))
        #expect(samples[2] == voice(4))
        #expect(samples[3] == nil) // no speaker there
        #expect(Voices.lineSamples([1..<5], Diarization(turns: diarization.turns)) == [nil]) // no windows: Remember voices off
    }

    /// A voice near `axis`: most of it there, a little on `noise` so samples of one voice differ.
    private func near(_ axis: Int, _ noise: Int, by amount: Float = 0.2) -> VoiceSample {
        var vector = [Float](repeating: 0, count: VoiceSample.size)
        vector[axis] = 1
        vector[noise] = amount
        return VoiceSample(vector)!
    }

    private func rows(_ person: Int, meeting: Int, axis: Int, count: Int = 3) -> [Voices.Row] {
        (0..<count).map { Voices.Row(person: person, meeting: meeting, sample: near(axis, 150 + 10 * meeting + $0)) }
    }

    @Test func aPrintNeedsEnoughSamples() {
        let prints = Voices.prints(rows(1, meeting: 1, axis: 1) + rows(2, meeting: 1, axis: 2, count: 2))
        #expect(Set(prints.keys) == [1])
        #expect(prints[1]?.samples == 3 && prints[1]!.mean.similarity(near(1, 100)) > 0.95)
    }

    @Test func recognitionNeedsTheThresholdTheMarginAndOnePrintPerKey() {
        let prints = Voices.prints(rows(1, meeting: 1, axis: 1) + rows(2, meeting: 2, axis: 2))
        let one = (0..<3).map { near(1, 110 + $0) }, two = (0..<3).map { near(2, 120 + $0) }
        #expect(Voices.recognise(["Person 1": one, "Person 2": two], prints: prints) == ["Person 1": 1, "Person 2": 2])
        // Too few samples, or nobody near enough.
        #expect(Voices.recognise(["Person 1": Array(one.prefix(2)), "Person 3": (0..<3).map { near(3, 130 + $0) }], prints: prints).isEmpty)
        // Halfway between two prints: neither leads by the margin.
        let between = (0..<3).map { _ in VoiceSample([Float](repeating: 0, count: 256).enumerated().map { $0.offset == 1 || $0.offset == 2 ? 1 : 0 })! }
        #expect(Voices.recognise(["Person 1": between], prints: prints, threshold: 0.5).isEmpty)
        // Two keys near one print: only the closer gets it.
        let closer = (0..<3).map { near(1, 140 + $0, by: 0.05) }
        #expect(Voices.recognise(["Person 1": one, "Person 4": closer], prints: prints) == ["Person 4": 1])
    }

    @Test func theCheckCountsEachMeetingsPeopleAgainstTheOtherMeetings() {
        // Olena (1) in meetings 1 and 2, Marko (2) only in meeting 2, and person 3 in meeting 3 sounds like Olena: in meeting 3
        // they are taken for her (wrong); in meetings 1 and 2 Olena is too close to person 3's print to tell (missed).
        // Marko has no print elsewhere and is left alone.
        let alike = rows(1, meeting: 1, axis: 1) + rows(1, meeting: 2, axis: 1) + rows(2, meeting: 2, axis: 2) + rows(3, meeting: 3, axis: 1)
        #expect(Voices.check(alike, match: .mean, threshold: 0.8) == .init(wrong: 1, missed: 2, unknown: 1))
        let apart = rows(1, meeting: 1, axis: 1) + rows(1, meeting: 2, axis: 1) + rows(2, meeting: 2, axis: 2)
        #expect(Voices.check(apart, match: .mean, threshold: 0.8) == .init(recognised: 2, unknown: 1))
        #expect(Voices.check(apart, match: .mean, threshold: 0.99) == .init(missed: 2, unknown: 1))
        // Nearest sample: in meeting 2 a voice like one sample of meeting 1's spread print, not like its mean.
        let spread = [near(5, 6, by: 0), near(6, 5, by: 0), near(7, 5, by: 0)].map { Voices.Row(person: 5, meeting: 1, sample: $0) }
            + (0..<3).map { Voices.Row(person: 5, meeting: 2, sample: near(5, 150 + $0, by: 0.1)) }
        #expect(Voices.check(spread, match: .mean, threshold: 0.8) == .init(missed: 2))
        #expect(Voices.check(spread, match: .nearest, threshold: 0.8) == .init(recognised: 1, missed: 1))
    }

    @Test func yourSamplesAreTheVoiceOfMostOfYourLines() {
        func window(_ speaker: String, _ start: Double, _ axis: Int) -> VoiceWindow {
            VoiceWindow(speaker: speaker, start: start, end: start + 10, sample: near(axis, 200))
        }
        let turns = [SpeakerTurn(speaker: "S1", start: 0, end: 20), SpeakerTurn(speaker: "S2", start: 20, end: 30),
                     SpeakerTurn(speaker: "S1", start: 30, end: 40)]
        let diarization = Diarization(turns: turns, windows: [window("S1", 0, 1), window("S2", 20, 2), window("S1", 30, 1)])
        let samples = Voices.yourSamples([1..<5, 21..<25, 31..<35], diarization)
        #expect(samples.map { $0 != nil } == [true, false, true]) // the room's voice gets none
        #expect(samples[0]!.similarity(near(1, 200)) > 0.99)
        // A tie: the first voice by name.
        #expect(Voices.yourSamples([1..<5, 21..<25], diarization).map { $0 != nil } == [true, false])
        #expect(Voices.yourSamples([], diarization).isEmpty)
    }

    @Test func yourSpeechIsYourFirstLinesUpToTheLimitWhereverTheyAre() {
        let speech = Voices.speech(of: [1000..<1001.5, 1200..<1201, 1300..<1302], upTo: 2)
        #expect(speech.ranges == [16_000_000..<16_024_000, 19_200_000..<19_216_000]) // 2.5 s: the third isn't needed
        #expect(speech.lines == [0..<1.5, 1.5..<2.5])
        #expect(Voices.speech(of: [], upTo: 600).ranges.isEmpty)
    }

    @Test func suggestionsAreTheMeetingsWhereRecognitionNamesThePerson() {
        let prints = Voices.prints(rows(1, meeting: 1, axis: 1) + rows(2, meeting: 2, axis: 2))
        let olena = (0..<3).map { near(1, 110 + $0) }, marko = (0..<3).map { near(2, 120 + $0) }
        let unnamed = [
            10: ["Person 1": olena, "Person 2": marko],
            11: ["Person 1": marko],
            12: ["Person 3": (0..<3).map { near(3, 130 + $0) }], // nobody
            13: ["Person 1": olena, "Person 2": (0..<3).map { near(1, 140 + $0, by: 0.05) }], // the closer one
        ]
        #expect(Voices.suggestions(1, unnamed: unnamed, prints: prints) == [10: "Person 1", 13: "Person 2"])
        #expect(Voices.suggestions(3, unnamed: unnamed, prints: prints).isEmpty) // no print
    }
}
