import Foundation
import Testing
@testable import ShepitCore

// Meetings design §5, §6, §8.
struct MeetingPageTests {
    private typealias Line = MeetingStore.Line
    private typealias Person = MeetingStore.Person

    private func entry(_ label: String?, _ second: Int, _ text: String = "one two", line: Int = 0) -> MeetingNote.Entry {
        .init(label: label, timestamp: label == nil ? "" : stamp(second), text: text, line: line)
    }

    private func stamp(_ second: Int) -> String { "2026-07-31 10:00:\(String(format: "%02d", second))" }

    private func line(_ second: Int, _ order: Int = 0, _ original: String, _ current: String? = nil) -> Line {
        Line(place: .init(timestamp: stamp(second), order: order), original: original, current: current ?? original)
    }

    // Pairing

    @Test func entriesPairWithLinesByTimestampAndOrder() {
        let entries = [entry("Me", 1), entry("Person 1", 3), entry("Person 2", 3), entry(nil, 0), entry("X", 9)]
        let lines = [line(1, 0, "Me"), line(3, 0, "Person 1"), line(3, 1, "Person 2")]
        #expect(MeetingPage.pair(entries, lines) == [lines[0], lines[1], lines[2], nil, nil])
    }

    @Test func aSecondWithEntriesAddedOrDeletedIsLeftUnpaired() {
        let lines = [line(1, 0, "Me"), line(3, 0, "Person 1"), line(3, 1, "Person 2")]
        #expect(MeetingPage.pair([entry("Me", 1), entry("Person 1", 3)], lines) == [lines[0], nil])
        #expect(MeetingPage.pair([entry("Me", 1), entry("Me", 1)], lines) == [nil, nil])
    }

    // The page of one meeting

    private let people = [Person(key: "Me", name: nil), Person(key: "Person 1", name: "Olena K."), Person(key: "Person 2", name: nil),
                          Person(key: "Person 3", name: nil)]

    @Test func peopleRowsShowWhoHasLinesWithSharesOfWords() {
        let note = [entry("Me", 1, "a b c"), entry("Person 2", 2, "a"), entry("Person 1", 3, "a b c d e f"),
                    entry("Person 1", 4, MeetingQueue.failedText), entry(nil, 0, "⚠ Запис перервано о 10:01:00")]
        let lines = [line(1, 0, "Me"), line(2, 0, "Person 2"), line(3, 0, "Person 1"), line(4, 0, "Person 3", "Person 1")]
        let page = MeetingPage.page(people: people, lines: lines, you: "Me", entries: note)
        #expect(page.people.map(\.key) == ["Me", "Person 2", "Person 1"]) // Person 3 has no lines left
        #expect(page.people.map(\.name) == ["Me", "Person 2", "Olena K."])
        #expect(page.people.map(\.named) == [true, false, true])
        #expect(page.people.map(\.initials) == ["M", "P2", "OK"])
        #expect(page.people.map(\.isYou) == [true, false, false])
        #expect(page.people.map(\.share) == [0.3, 0.1, 0.6])
        #expect(page.people[0].mergeTargets.isEmpty)
        #expect(page.people[1].mergeTargets == ["Me", "Person 1"])
        #expect(page.canReset)
    }

    @Test func transcriptRowsShowTheStoredPersonOrTheNotesLabel() {
        let note = [entry("Me", 1, "hi"), entry("Edited by hand", 3, "yes"), entry("Person 9", 7, "added"), entry(nil, 0, "⚠ stop")]
        let lines = [line(1, 0, "Me", "Person 1"), line(3, 0, "Person 2")]
        let page = MeetingPage.page(people: people, lines: lines, you: "Me", entries: note)
        #expect(page.rows == [
            .init(name: "Olena K.", time: "10:00:01", text: "hi", place: .init(timestamp: stamp(1), order: 0), person: "Person 1"),
            .init(name: "Person 2", time: "10:00:03", text: "yes", place: .init(timestamp: stamp(3), order: 0), person: "Person 2"),
            .init(name: "Person 9", time: "10:00:07", text: "added", place: nil, person: nil),
            .init(name: nil, time: "", text: "⚠ stop", place: nil, person: nil),
        ])
        #expect(!MeetingPage.page(people: people, lines: [line(1, 0, "Me")], you: "Me", entries: note).canReset)
    }

    // Changes

    @Test func relabelledRewritesOnlyHeadersWhoseShownNameChanged() {
        let note = "[Me] \(stamp(1))\nhi\n[Person 1] \(stamp(3))\nyes\n[Typed by hand] \(stamp(5))\nok\n[Person 2] \(stamp(7))\nadded\n"
        let lines = [line(1, 0, "Me"), line(3, 0, "Person 1"), line(5, 0, "Person 1")]
        let before = (people: people, lines: lines)
        var named = people
        named[1].name = "Olena K." // already was: unchanged
        named[2].name = "Marko"
        var given = lines
        given[0].current = "Person 2"
        given[2].current = "Person 2"
        #expect(MeetingPage.relabelled(note, before: before, after: (named, given))
                == "[Marko] \(stamp(1))\nhi\n[Person 1] \(stamp(3))\nyes\n[Marko] \(stamp(5))\nok\n[Person 2] \(stamp(7))\nadded\n")
        #expect(MeetingPage.relabelled(note, before: before, after: before) == note)
    }

    @Test func aNameAnotherPersonHasIsAClash() {
        let lines = [line(1, 0, "Me"), line(3, 0, "Person 1"), line(5, 0, "Person 2")]
        #expect(MeetingPage.clash(people: people, lines: lines, person: "Person 2", name: " olena k. ") == "Person 1")
        #expect(MeetingPage.clash(people: people, lines: lines, person: "Person 1", name: "Person 2") == "Person 2")
        #expect(MeetingPage.clash(people: people, lines: lines, person: "Person 2", name: "Person 3") == nil) // no lines
        #expect(MeetingPage.clash(people: people, lines: lines, person: "Person 1", name: "Olena K.") == nil) // itself
    }

    @Test func namesAreOneLineAndEmptyMeansNone() {
        #expect(MeetingPage.name(" Olena\n K. ") == "Olena K.")
        #expect(MeetingPage.name("  ") == nil)
    }

    // The list

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private func day(_ month: Int, _ day: Int, _ hour: Int = 10, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func meeting(_ id: Int, _ start: Date, title: String? = nil, app: String? = "Teams", duration: TimeInterval? = 48 * 60) -> MeetingStore.Meeting {
        .init(id: id, path: "/\(id).md", title: title, app: app, start: start, duration: duration, you: "Me")
    }

    @Test func theListIsGroupedByWeekThenMonth() {
        // Thursday 12 Nov 2026; the week starts on Monday 9 Nov.
        let meetings = [meeting(1, day(11, 10), title: "Sprint planning"), meeting(2, day(11, 9, 15, 30), app: "Zoom"),
                        meeting(3, day(11, 6, 12), title: "Weekly sync", app: nil, duration: nil), meeting(4, day(10, 3, 9, 5), app: nil),
                        meeting(5, day(9, 30))]
        let groups = MeetingPage.list(meetings, missing: [3], running: nil, now: day(11, 12, 18), calendar: calendar)
        #expect(groups.map(\.title) == ["This week", "Last week", "October 2026", "September 2026"])
        #expect(groups[0].rows == [.init(id: 1, title: "Sprint planning", detail: "Tue 10:00 · 48 min · Teams"),
                                   .init(id: 2, title: "Zoom call", detail: "Mon 15:30 · 48 min · Zoom")])
        #expect(groups[1].rows == [.init(id: 3, title: "Weekly sync", detail: "Fri 12:00 · note not found")])
        #expect(groups[2].rows == [.init(id: 4, title: "Meeting", detail: "3 Oct, 09:05 · 48 min")])
    }

    @Test func theRunningTranscriptComesFirst() {
        let running = { (state: MeetingState) in
            MeetingPage.list([meeting(1, day(11, 10))], missing: [], running: .init(state: state, title: "Weekly sync", app: .teams),
                             now: day(11, 12), calendar: calendar).first?.rows.first
        }
        #expect(running(.recording(elapsed: 754, waiting: 2)) == .init(id: nil, title: "Weekly sync", detail: "Recording · 12:34 · Teams"))
        #expect(running(.finishing(left: 3))?.detail == "Finishing (3 left)")
        #expect(running(.detectingSpeakers)?.detail == "Detecting speakers…")
        #expect(running(.done(speakers: 2))?.id == 1) // no running row once it is done
    }

    @Test func theFactsOfAMeeting() {
        #expect(MeetingPage.facts(meeting(1, day(11, 10, 9, 5)), calendar: calendar) == ["Teams", "10 Nov 2026, 09:05", "48 min"])
        #expect(MeetingPage.facts(meeting(1, day(11, 10), app: nil, duration: nil), calendar: calendar) == ["10 Nov 2026, 10:00"])
    }

    @Test func namesMatchAnywhereInAnyScript() {
        let names = ["Ivan Batura", "Олена К.", "Marko D.", "José"]
        #expect(MeetingPage.matching(names, typed: "Іван") == ["Ivan Batura"])
        #expect(MeetingPage.matching(names, typed: "bat") == ["Ivan Batura"])
        #expect(MeetingPage.matching(names, typed: "olena") == ["Олена К."])
        #expect(MeetingPage.matching(names, typed: "jose") == ["José"])
        #expect(MeetingPage.matching(names, typed: " ") == names)
        #expect(MeetingPage.matching(names, typed: "zz").isEmpty)
    }
}
