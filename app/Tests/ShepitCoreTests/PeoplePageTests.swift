import Foundation
import Testing
@testable import ShepitCore

// Voices design §6: the People section's list and a person.
struct PeoplePageTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        return calendar
    }()

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 10))!
    }

    private func meeting(_ id: Int, _ start: Date, title: String? = nil) -> MeetingStore.Meeting {
        MeetingStore.Meeting(id: id, path: "/m/\(id).md", title: title, app: "Teams", start: start, duration: 1800, you: "Ivan")
    }

    private func people(_ summaries: [MeetingStore.Summary]) -> [PeoplePage.Person] {
        PeoplePage.people(summaries, you: "Ivan Batura", now: day(2026, 11, 18), calendar: calendar)
    }

    // The store gives meetings newest first.
    private var meetings: [MeetingStore.Meeting] {
        [meeting(3, day(2026, 11, 10), title: "Sprint planning"), meeting(2, day(2026, 11, 6)), meeting(1, day(2025, 12, 3))]
    }

    @Test func youFirstThenByTheLastMeeting() {
        let list = people([
            .init(person: 7, name: "Taras", you: false, meetings: 1, last: day(2026, 11, 6), voiceMeetings: 0),
            .init(person: 5, name: "Marko D.", you: false, meetings: 1, last: day(2026, 11, 6), voiceMeetings: 0),
            .init(person: 1, name: nil, you: true, meetings: 1, last: day(2025, 12, 3), voiceMeetings: 0),
            .init(person: 4, name: "Olena K.", you: false, meetings: 2, last: day(2026, 11, 10), voiceMeetings: 0),
        ])
        #expect(list.map(\.name) == ["Ivan Batura", "Olena K.", "Marko D.", "Taras"]) // the same day: by number
        #expect(list.map(\.initials).prefix(3) == ["IB", "OK", "MD"])
        #expect(list.map(\.isYou) == [true, false, false, false])
        #expect(list.map(\.detail).prefix(3) == ["you · 1 meeting · last 3 Dec 2025", "2 meetings · last 10 Nov", "1 meeting · last 6 Nov"])
    }

    @Test func aPersonsVoice() {
        let list = people([
            .init(person: 1, name: nil, you: true, meetings: 3, last: day(2026, 11, 10), voiceMeetings: 1),
            .init(person: 4, name: "Olena K.", you: false, meetings: 3, last: day(2026, 11, 10), voiceMeetings: 2),
            .init(person: 5, name: "Marko D.", you: false, meetings: 2, last: day(2026, 11, 6), voiceMeetings: 1),
            .init(person: 6, name: "Taras", you: false, meetings: 1, last: day(2026, 11, 3), voiceMeetings: 0),
        ])
        #expect(list.map(\.voiceMeetings) == [1, 2, 1, 0])
        #expect(list.map(\.voice) == ["Saved from 1 meeting: your microphone and the lines given to you", "Saved from 2 meetings",
                                     "Saved from 1 meeting", "No voice saved"])
    }

    @Test func aPersonsMeetingsNewestFirst() {
        let rows = PeoplePage.meetings([
            .init(meeting: 1), // listed before words and talk time were kept
            .init(meeting: 3, words: 1240, seconds: 750, meetingWords: 4000),
            .init(meeting: 2, words: 30, meetingWords: 100),
            .init(meeting: 99), // not listed: left out
        ], meetings: meetings, calendar: calendar)
        #expect(rows == [
            .init(id: 3, title: "Sprint planning", date: "10 Nov 2026, 10:00", talk: "12 min · \(1240.formatted()) words"),
            .init(id: 2, title: "Teams call", date: "6 Nov 2026, 10:00", talk: "– · 30 words"),
            .init(id: 1, title: "Teams call", date: "3 Dec 2025, 10:00", talk: "–"),
        ])
    }

    @Test func suggestionsAreTheirMeetingsNewestFirst() {
        let rows = PeoplePage.suggestions([1: "Person 2", 3: "Person 1", 99: "Person 1"], meetings: meetings, calendar: calendar)
        #expect(rows == [.init(id: 3, title: "Sprint planning", date: "10 Nov 2026, 10:00", key: "Person 1"),
                         .init(id: 1, title: "Teams call", date: "3 Dec 2025, 10:00", key: "Person 2")])
        #expect(PeoplePage.mayAlsoBeIn(rows) == "May also be in 2 meetings")
        #expect(PeoplePage.mayAlsoBeIn(Array(rows.prefix(1))) == "May also be in 1 meeting")
    }

    @Test func whoTalkedHowMuch() {
        let olena: [MeetingStore.Presence] = [
            .init(meeting: 3, words: 120, seconds: 300, meetingWords: 400),
            .init(meeting: 2, words: 30, meetingWords: 100),
            .init(meeting: 1), // words not filled yet
        ]
        #expect(PeoplePage.talk(olena).map(\.title) == ["Meetings", "Talk time", "Words", "Share of words"])
        #expect(PeoplePage.talk(olena).map(\.value) == ["3", "5 min", "150", "30%"])
        #expect(PeoplePage.talk([.init(meeting: 2, words: 70, meetingWords: 100)])
                    .map(\.value) == ["1", "–", "70", "70%"])
        #expect(PeoplePage.talk([]).map(\.value) == ["0", "–", "–", "–"])
    }
}
