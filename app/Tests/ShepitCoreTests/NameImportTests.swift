import Foundation
import Testing
@testable import ShepitCore

// Import names design §5: lining a transcript file up with a meeting, and matching people to speakers.
struct NameImportTests {
    private typealias Line = NameImport.Line
    private typealias Cue = SpeakerTranscript.Cue

    /// The same random turns every run.
    private struct Dice {
        var state: UInt64
        mutating func next(_ n: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(n))
        }
    }

    private static let people = ["Me", "Person 1", "Person 2", "Person 3"]
    private static let speakers = ["Ivan B.", "Olena K.", "Marko D.", "Petro S."]

    /// 30 minutes of turns of 2–31 s with short pauses, each by one of four voices.
    private func turns(seed: UInt64, minutes: Int = 30) -> [(start: Double, end: Double, voice: Int)] {
        var dice = Dice(state: seed), turns: [(Double, Double, Int)] = [], t = 0.0
        while t < Double(minutes * 60) {
            let length = Double(2 + dice.next(30))
            turns.append((t, t + length, dice.next(4)))
            t += length + Double(dice.next(3))
        }
        return turns
    }

    private func lines(_ turns: [(start: Double, end: Double, voice: Int)], from: Double = 0) -> [Line] {
        turns.filter { $0.start >= from }.map { Line(person: Self.people[$0.voice], start: $0.start - from, length: $0.end - $0.start) }
    }

    private func cues(_ turns: [(start: Double, end: Double, voice: Int)], from: Double = 0) -> [Cue] {
        turns.filter { $0.start >= from }.map { Cue(start: $0.start - from, end: $0.end - from, speaker: Self.speakers[$0.voice]) }
    }

    @Test func aFileThatStartsLateIsFoundWhereItStarts() throws {
        let turns = turns(seed: 1)
        let alignment = try #require(NameImport.align(lines(turns), cues(turns, from: 1200)))
        #expect(alignment.shift == 1200)
        for (person, speaker) in zip(Self.people, Self.speakers) {
            #expect(alignment.matches[person]?.speaker == speaker && alignment.matches[person]?.share == 1)
        }
        #expect(Set(alignment.speakers) == Set(Self.speakers))
    }

    @Test func aFileThatStartsBeforeTheMeetingHasANegativeShift() throws {
        let turns = turns(seed: 1)
        #expect(NameImport.align(lines(turns, from: 40), cues(turns))?.shift == -40)
    }

    @Test func edgesOffByUpToASecondFindTheSameShift() throws {
        let turns = turns(seed: 1)
        var dice = Dice(state: 7)
        let moved = cues(turns, from: 1200).map {
            Cue(start: $0.start + Double(dice.next(21) - 10) / 10, end: $0.end + Double(dice.next(21) - 10) / 10, speaker: $0.speaker)
        }
        let alignment = try #require(NameImport.align(lines(turns), moved))
        #expect(alignment.shift == 1200 && alignment.matches.count == 4)
    }

    @Test func anotherMeetingsFileDoesNotLineUp() {
        #expect(NameImport.align(lines(turns(seed: 1)), cues(turns(seed: 2))) == nil)
        #expect(NameImport.align(lines(turns(seed: 1)), cues(turns(seed: 3, minutes: 10))) == nil)
        #expect(NameImport.align([], cues(turns(seed: 1))) == nil && NameImport.align(lines(turns(seed: 1)), []) == nil)
        // A cue with a broken time 7 hours in.
        #expect(NameImport.align(lines(turns(seed: 1)), cues(turns(seed: 1)) + [Cue(start: 25_200, end: 25_201, speaker: "Olena K.")]) == nil)
    }

    @Test func aMatchNeedsHalfOfTheSharedTimeAndFiveSeconds() throws {
        let turns = turns(seed: 1), end = turns.last!.end + 10
        // After the turns: Person 7 shares 40/30/30 with three speakers, Person 8 4 s and Person 9 5 s with one.
        let extra = [Line(person: "Person 7", start: end, length: 100), Line(person: "Person 8", start: end + 110, length: 4),
                     Line(person: "Person 9", start: end + 120, length: 5)]
        let said = [Cue(start: end, end: end + 40, speaker: "Ivan B."), Cue(start: end + 40, end: end + 70, speaker: "Olena K."),
                    Cue(start: end + 70, end: end + 100, speaker: "Marko D."), Cue(start: end + 110, end: end + 114, speaker: "Petro S."),
                    Cue(start: end + 120, end: end + 125, speaker: "Petro S.")]
        let alignment = try #require(NameImport.align(lines(turns) + extra, cues(turns) + said))
        #expect(alignment.shift == 0)
        #expect(alignment.matches["Person 7"] == nil && alignment.matches["Person 8"] == nil)
        #expect(alignment.matches["Person 9"] == NameImport.Match(speaker: "Petro S.", share: 1, seconds: 5))
    }

    @Test func equalScoresPickTheShiftNearestZero() {
        let lines = [Line(person: "Person 1", start: 0, length: 1), Line(person: "Person 1", start: 30, length: 1)]
        #expect(NameImport.align(lines, [Cue(start: 0, end: 1, speaker: "Olena K.")])?.shift == 0) // 0 and 30 tie
        #expect(NameImport.align(lines, [Cue(start: 30, end: 31, speaker: "Olena K.")])?.shift == 0) // -30 and 0 tie
    }

    @Test func eachSecondHasOneOwnerTheLaterLineWhereTwoOverlap() throws {
        // Person 2's line covers seconds 10–19 and is later than Person 1's 0–19: Person 1 keeps 0–9 only.
        let lines = [Line(person: "Person 1", start: 0, length: 20), Line(person: "Person 2", start: 10, length: 10)]
        let cues = [Cue(start: 0, end: 10, speaker: "Olena K."), Cue(start: 10, end: 20, speaker: "Marko D.")]
        let alignment = try #require(NameImport.align(lines, cues))
        #expect(alignment.matches == ["Person 1": .init(speaker: "Olena K.", share: 1, seconds: 10),
                                      "Person 2": .init(speaker: "Marko D.", share: 1, seconds: 10)])
    }
}
