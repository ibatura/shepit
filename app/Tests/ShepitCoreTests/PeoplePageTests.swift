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

    private func people(_ presences: [MeetingStore.Presence], _ meetings: [MeetingStore.Meeting]) -> [PeoplePage.Person] {
        PeoplePage.people(presences, meetings: meetings, you: "Ivan Batura", now: day(2026, 11, 18), calendar: calendar)
    }

    // The store gives meetings newest first.
    private var meetings: [MeetingStore.Meeting] {
        [meeting(3, day(2026, 11, 10), title: "Sprint planning"), meeting(2, day(2026, 11, 6)), meeting(1, day(2025, 12, 3))]
    }

    @Test func youFirstThenByTheLastMeeting() {
        let list = people([
            .init(person: 5, name: "Marko D.", you: false, meeting: 2, samples: 0),
            .init(person: 1, name: nil, you: true, meeting: 1, samples: 0),
            .init(person: 4, name: "Olena K.", you: false, meeting: 3, samples: 2),
            .init(person: 4, name: "Olena K.", you: false, meeting: 1, samples: 0),
            .init(person: 6, name: "Taras", you: false, meeting: 99, samples: 0), // not listed: left out
        ], meetings)
        #expect(list.map(\.name) == ["Ivan Batura", "Olena K.", "Marko D."])
        #expect(list.map(\.initials) == ["IB", "OK", "MD"])
        #expect(list.map(\.isYou) == [true, false, false])
        #expect(list.map(\.detail) == ["you · 1 meeting · last 3 Dec 2025", "2 meetings · last 10 Nov", "1 meeting · last 6 Nov"])
    }

    @Test func aPersonsVoiceAndMeetings() throws {
        let list = people([
            .init(person: 4, name: "Olena K.", you: false, meeting: 1, samples: 3),
            .init(person: 4, name: "Olena K.", you: false, meeting: 3, samples: 2),
            .init(person: 4, name: "Olena K.", you: false, meeting: 2, samples: 0),
            .init(person: 5, name: "Marko D.", you: false, meeting: 2, samples: 0),
        ], meetings)
        let olena = try #require(list.first)
        #expect(olena.voiceMeetings == 2)
        #expect(olena.voice == "Saved from 2 meetings")
        #expect(olena.meetings == [
            .init(id: 3, title: "Sprint planning", date: "10 Nov 2026, 10:00"),
            .init(id: 2, title: "Teams call", date: "6 Nov 2026, 10:00"),
            .init(id: 1, title: "Teams call", date: "3 Dec 2025, 10:00"),
        ])
        #expect(list[1].voiceMeetings == 0)
        #expect(list[1].voice == "No voice saved")
        #expect(people([.init(person: 4, name: "Olena K.", you: false, meeting: 3, samples: 1)], meetings)[0].voice == "Saved from 1 meeting")
    }
}
