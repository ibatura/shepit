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
        let alignment = try NameImport.align(lines(turns), cues(turns, from: 1200))
        #expect(alignment.shift == 1200)
        for (person, speaker) in zip(Self.people, Self.speakers) {
            #expect(alignment.matches[person]?.speaker == speaker && alignment.matches[person]?.share == 1)
        }
        #expect(Set(alignment.speakers) == Set(Self.speakers) && Set(alignment.people) == Set(Self.people))
    }

    @Test func aFileThatStartsBeforeTheMeetingHasANegativeShift() throws {
        let turns = turns(seed: 1)
        #expect(try NameImport.align(lines(turns, from: 40), cues(turns)).shift == -40)
    }

    @Test func edgesOffByUpToASecondFindTheSameShift() throws {
        let turns = turns(seed: 1)
        var dice = Dice(state: 7)
        let moved = cues(turns, from: 1200).map {
            Cue(start: $0.start + Double(dice.next(21) - 10) / 10, end: $0.end + Double(dice.next(21) - 10) / 10, speaker: $0.speaker)
        }
        let alignment = try NameImport.align(lines(turns), moved)
        #expect(alignment.shift == 1200 && alignment.matches.count == 4)
    }

    @Test func anotherMeetingsFileDoesNotLineUp() {
        func refused(_ lines: [Line], _ cues: [Cue]) -> Bool { (try? NameImport.align(lines, cues)) == nil }
        #expect(refused(lines(turns(seed: 1)), cues(turns(seed: 2))))
        #expect(refused(lines(turns(seed: 1)), cues(turns(seed: 3, minutes: 10))))
        #expect(refused([], cues(turns(seed: 1))) && refused(lines(turns(seed: 1)), []))
        // A cue with a broken time 7 hours in.
        #expect(refused(lines(turns(seed: 1)), cues(turns(seed: 1)) + [Cue(start: 25_200, end: 25_201, speaker: "Olena K.")]))
        #expect(NameImport.NotLinedUp().localizedDescription == "This transcript doesn't line up with this meeting.")
    }

    @Test func aMatchNeedsHalfOfTheSharedTimeAndFiveSeconds() throws {
        let turns = turns(seed: 1), end = turns.last!.end + 10
        // After the turns: Person 7 shares 40/30/30 with three speakers, Person 8 4 s and Person 9 5 s with one.
        let extra = [Line(person: "Person 7", start: end, length: 100), Line(person: "Person 8", start: end + 110, length: 4),
                     Line(person: "Person 9", start: end + 120, length: 5)]
        let said = [Cue(start: end, end: end + 40, speaker: "Ivan B."), Cue(start: end + 40, end: end + 70, speaker: "Olena K."),
                    Cue(start: end + 70, end: end + 100, speaker: "Marko D."), Cue(start: end + 110, end: end + 114, speaker: "Petro S."),
                    Cue(start: end + 120, end: end + 125, speaker: "Petro S.")]
        let alignment = try NameImport.align(lines(turns) + extra, cues(turns) + said)
        #expect(alignment.shift == 0)
        #expect(alignment.matches["Person 7"] == nil && alignment.matches["Person 8"] == nil)
        #expect(alignment.matches["Person 9"] == NameImport.Match(speaker: "Petro S.", share: 1, seconds: 5))
    }

    @Test func equalScoresPickTheShiftNearestZero() throws {
        let lines = [Line(person: "Person 1", start: 0, length: 1), Line(person: "Person 1", start: 30, length: 1)]
        #expect(try NameImport.align(lines, [Cue(start: 0, end: 1, speaker: "Olena K.")]).shift == 0) // 0 and 30 tie
        #expect(try NameImport.align(lines, [Cue(start: 30, end: 31, speaker: "Olena K.")]).shift == 0) // -30 and 0 tie
    }

    @Test func eachSecondHasOneOwnerTheLaterLineWhereTwoOverlap() throws {
        // Person 2's line covers seconds 10–19 and is later than Person 1's 0–19: Person 1 keeps 0–9 only.
        let lines = [Line(person: "Person 1", start: 0, length: 20), Line(person: "Person 2", start: 10, length: 10)]
        let cues = [Cue(start: 0, end: 10, speaker: "Olena K."), Cue(start: 10, end: 20, speaker: "Marko D.")]
        let alignment = try NameImport.align(lines, cues)
        #expect(alignment.matches == ["Person 1": .init(speaker: "Olena K.", share: 1, seconds: 10),
                                      "Person 2": .init(speaker: "Marko D.", share: 1, seconds: 10)])
    }

    @Test func theStoresLinesAreTimedByTheirSecondsOrWords() throws {
        let start = try #require(MeetingNote.date("2026-07-31 10:00:00"))
        func line(_ time: String, _ person: String, words: Int? = nil, seconds: Double? = nil) -> MeetingStore.Line {
            .init(place: .init(timestamp: "2026-07-31 \(time)", order: 0), original: person, current: person, words: words, seconds: seconds)
        }
        #expect(NameImport.timed([line("10:00:01", "Me", words: 4), line("10:00:03", "Person 1", words: 1, seconds: 7.5),
                                  line("10:00:04", MeetingNote.callLabel, words: 3), line("10:01:09", "Person 1", words: 0)], start: start) == [
            Line(person: "Me", start: 1, length: 2), // no seconds: half a second per word
            Line(person: "Person 1", start: 3, length: 7.5),
            Line(person: "Person 1", start: 69, length: 0.5), // no words either
        ])
    }
}

// Import names design §5–7: the sheet's suggestions and what Apply changes.
struct NameImportSheetTests {
    private typealias Match = NameImport.Match
    private typealias Row = NameImport.Row
    private typealias Merge = NameImport.Merge

    /// People in `matches` speak in the order the test lists them.
    private func alignment(shift: Int = 724, _ matches: KeyValuePairs<String, Match> = [:], speakers: [String] = [],
                           people: [String] = []) -> NameImport.Alignment {
        .init(shift: shift, people: people.isEmpty ? matches.map(\.key) : people, matches: Dictionary(uniqueKeysWithValues: matches.map { ($0, $1) }),
              speakers: speakers)
    }

    private func match(_ speaker: String, _ seconds: Int, _ share: Double = 0.9) -> Match {
        .init(speaker: speaker, share: share, seconds: seconds)
    }

    private func sheet(_ alignment: NameImport.Alignment, people: [MeetingStore.Person]) -> NameImport.Sheet {
        NameImport.sheet(file: "Daily.vtt", alignment: alignment, people: people, you: "Me")
    }

    @Test func theSubtitleSaysWhereTheFileStarts() {
        func subtitle(_ shift: Int) -> String { sheet(alignment(shift: shift), people: []).subtitle }
        #expect(subtitle(724) == "From Daily.vtt · the file starts 12:04 into the meeting")
        #expect(subtitle(-40) == "From Daily.vtt · the file starts 0:40 before the meeting")
        #expect(subtitle(3724) == "From Daily.vtt · the file starts 1:02:04 into the meeting")
    }

    @Test func eachRowIsTickedOnlyForSomeoneWithNoName() {
        let people: [MeetingStore.Person] = [
            .init(key: "Me", name: nil), .init(key: "Person 1", name: nil), .init(key: "Person 2", name: "OLENA K."),
            .init(key: "Person 3", name: "Marko", person: 4, recognised: true), .init(key: "Person 4", name: nil),
        ]
        let sheet = sheet(alignment(["Me": match("Ivan B.", 300), "Person 1": match("Petro S.", 200, 0.75),
                                     "Person 2": match("Olena K.", 100), "Person 3": match("Marko D.", 50)],
                                    speakers: ["Olena K.", "Ivan B.", "Petro S.", "Marko D.", "Anna V."], people: people.map(\.key)), people: people)
        #expect(sheet.rows == [
            Row(key: "Person 1", label: "Person 1", name: "Petro S.", share: 0.75, alreadyNamed: false, ticked: true),
            Row(key: "Person 2", label: "OLENA K.", name: "", share: 0.9, alreadyNamed: true, ticked: false),
            Row(key: "Person 3", label: "Marko", name: "Marko D.", share: 0.9, alreadyNamed: false, ticked: false),
            Row(key: "Person 4", label: "Person 4", name: "", share: nil, alreadyNamed: false, ticked: false),
        ])
        #expect(sheet.merges.isEmpty && sheet.others == ["Anna V."])
    }

    @Test func aSpeakerMatchedTwiceGoesToWhoeverSharesMostAndTheOthersMergeIntoThem() {
        let people: [MeetingStore.Person] = [
            .init(key: "Me", name: nil), .init(key: "Person 1", name: nil), .init(key: "Person 2", name: "Olena"),
            .init(key: "Person 3", name: nil), .init(key: "Person 4", name: nil), .init(key: "Person 5", name: "Marko"),
            .init(key: "Person 6", name: nil),
        ]
        let sheet = sheet(alignment(["Me": match("Ivan B.", 300), "Person 1": match("Ivan B.", 20), // that's you
                                     "Person 2": match("Olena K.", 200), "Person 3": match("Olena K.", 30),
                                     "Person 4": match("Petro S.", 40), "Person 5": match("Petro S.", 40), // a tie: the first
                                     "Person 6": match("Anna V.", 400)],
                                    speakers: ["Ivan B.", "Olena K.", "Petro S.", "Anna V."]), people: people)
        #expect(sheet.merges == [
            Merge(person: "Person 1", into: "Me", text: "Merge Person 1 into you: that's you in the file"),
            Merge(person: "Person 3", into: "Person 2", text: "Merge Person 3 into Olena: both are Olena K. in the file"),
        ])
        #expect(sheet.rows.map(\.name) == ["", "Olena K.", "", "Petro S.", "", "Anna V."]) // Person 5 has a name: no merge
        #expect(sheet.others.isEmpty)
    }

    @Test func youMatchingASpeakerAPersonHoldsChangesNothingForYou() {
        let people: [MeetingStore.Person] = [.init(key: "Me", name: nil), .init(key: "Person 1", name: nil)]
        let sheet = sheet(alignment(["Me": match("Olena K.", 30), "Person 1": match("Olena K.", 700)], speakers: ["Olena K."]),
                          people: people)
        #expect(sheet.rows.map(\.name) == ["Olena K."] && sheet.merges.isEmpty && sheet.others.isEmpty)
    }

    @Test func aNameAnotherPersonHereWillHaveClashes() {
        let people: [MeetingStore.Person] = [.init(key: "Me", name: "Ivan"), .init(key: "Person 1", name: nil),
                                             .init(key: "Person 2", name: "Olena K."), .init(key: "Person 3", name: nil)]
        let sheet = sheet(alignment(people: people.map(\.key)), people: people)
        func clashes(_ typed: [String: String]) -> Set<String> {
            var edited = sheet
            for index in edited.rows.indices { if let name = typed[edited.rows[index].key] { edited.rows[index].name = name } }
            return edited.clashes
        }
        #expect(clashes(["Person 1": "olena k.", "Person 3": "Marko"]) == ["Person 1"])
        #expect(clashes(["Person 1": "Marko", "Person 3": " marko "]) == ["Person 1", "Person 3"])
        #expect(clashes(["Person 1": "Іван"]) == ["Person 1"]) // your name, in another script
        #expect(clashes(["Person 2": "Marko", "Person 1": "Olena K."]).isEmpty) // Person 2 gives the name up
    }

    @Test func typingANameTicksTheRowAndEmptyingItUnticksIt() {
        var row = Row(key: "Person 3", label: "Marko", name: "Marko D.", share: 0.9, alreadyNamed: false, ticked: false)
        row.name = "Marko D." // the field saved again as it was, on losing focus
        #expect(!row.ticked)
        row.name = "Marko Do"
        #expect(row.ticked)
        row.name = "  "
        #expect(!row.ticked)
    }

    @Test func applyTakesTheTickedMergesThenTheTickedNamesAndNoNameForSomeoneMergedAway() {
        func row(_ key: String, _ name: String, ticked: Bool = true) -> Row {
            Row(key: key, label: key, name: name, share: nil, alreadyNamed: false, ticked: ticked)
        }
        var unticked = Merge(person: "Person 6", into: "Person 2", text: "")
        unticked.ticked = false
        let merge = Merge(person: "Person 3", into: "Person 2", text: "")
        var sheet = NameImport.Sheet(subtitle: "", rows: [row("Person 1", "  Petro S. "), row("Person 2", "Olena K."), row("Person 3", "Olena"),
                                                          row("Person 4", " "), row("Person 5", "Anna V.", ticked: false)],
                                     merges: [merge, unticked], others: [], names: [:])
        #expect(sheet.changes.merges == [merge] && sheet.changes.names == ["Person 1": "Petro S.", "Person 2": "Olena K."])
        #expect(sheet.canApply)
        sheet.rows = [row("Person 1", "Olena K."), row("Person 2", "Olena K.")]
        #expect(!sheet.canApply) // a clash
        sheet.rows = []
        sheet.merges = [unticked]
        #expect(!sheet.canApply) // nothing ticked
    }
}
