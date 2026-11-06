import Foundation
import Testing
@testable import ShepitCore

struct MeetingNamesTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        return calendar
    }()

    /// 2026-11-06 is a Friday.
    private func at(_ day: Int, _ hour: Int, _ minute: Int, month: Int = 11) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func entry(_ title: String, _ start: Date, _ app: String? = nil) -> MeetingNames.Entry {
        .init(title: title, app: app, start: start)
    }

    @Test func aWeeklyMeetingIsNamedLikeLastWeek() {
        let entries = [entry("Old sync", at(23, 17, 0, month: 10)), entry("Sprint Planning + Review", at(30, 17, 2, month: 10))]
        #expect(MeetingNames.repeating(entries, at: at(6, 16, 55), app: "Teams", calendar: calendar) == "Sprint Planning + Review")
    }

    @Test func farInTimeOfDayOrOtherWeekdayOrTooOldIsNoRepeat() {
        #expect(MeetingNames.repeating([entry("A", at(30, 16, 30, month: 10))], at: at(6, 17, 0), app: nil, calendar: calendar) == nil)
        #expect(MeetingNames.repeating([entry("A", at(5, 17, 0))], at: at(6, 17, 0), app: nil, calendar: calendar) == nil) // once, Thursday
        #expect(MeetingNames.repeating([entry("A", at(25, 17, 0, month: 9))], at: at(6, 17, 0), app: nil, calendar: calendar) == nil)
    }

    @Test func todaysEarlierMeetingIsNotARepeat() {
        #expect(MeetingNames.repeating([entry("A", at(6, 9, 0))], at: at(6, 9, 10), app: nil, calendar: calendar) == nil)
    }

    @Test func aDailyMeetingNeedsTwoOtherDays() {
        let twice = [entry("Standup", at(4, 10, 0)), entry("Standup", at(5, 10, 5))]
        #expect(MeetingNames.repeating(twice, at: at(6, 10, 0), app: nil, calendar: calendar) == "Standup")
        #expect(MeetingNames.repeating([entry("Standup", at(5, 10, 0))], at: at(6, 10, 0), app: nil, calendar: calendar) == nil)
    }

    @Test func anotherKnownAppDoesNotCount() {
        let entries = [entry("Zoom thing", at(30, 17, 0, month: 10), "Zoom")]
        #expect(MeetingNames.repeating(entries, at: at(6, 17, 0), app: "Meet", calendar: calendar) == nil)
        #expect(MeetingNames.repeating(entries, at: at(6, 17, 0), app: nil, calendar: calendar) == "Zoom thing")
    }

    @Test func recentNamesAreDistinctNewestFirst() {
        let entries = [entry("A", at(1, 9, 0)), entry("B", at(2, 9, 0)), entry("a", at(3, 9, 0)), entry("C", at(4, 9, 0))]
        #expect(MeetingNames.recent(entries) == ["C", "a", "B"])
        #expect(MeetingNames.recent(entries, limit: 2) == ["C", "a"])
    }

    @Test func addingSkipsEmptyAndKeepsTheNewest() {
        #expect(MeetingNames.adding([], title: "  ", app: nil, start: at(1, 9, 0)).isEmpty)
        var entries: [MeetingNames.Entry] = []
        for index in 0..<(MeetingNames.kept + 5) { entries = MeetingNames.adding(entries, title: "M\(index)", app: nil, start: at(1, 9, 0)) }
        #expect(entries.count == MeetingNames.kept)
        #expect(entries.first?.title == "M5")
    }

    @Test func savedNamesLoadBack() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: MeetingNames.fileName)
        let entries = [entry("Weekly sync", at(6, 17, 0), "Meet")]
        try MeetingNames.save(entries, to: file)
        #expect(MeetingNames.load(file) == entries)
        #expect(MeetingNames.load(file.appending(path: "missing")).isEmpty)
    }
}

struct MeetPageNameTests {
    @Test func theNameAfterTheClock() {
        #expect(MeetingTitle.meetPageName(["16:29", "|", "Weekly sync"]) == "Weekly sync")
        #expect(MeetingTitle.meetPageName(["Ivan Batura", "4:29 PM", "Design review"]) == "Design review")
    }

    @Test func aQuickMeetingCodeOrNoClockIsNoName() {
        #expect(MeetingTitle.meetPageName(["16:29", "|", "qbu-gkgc-bjh"]) == nil)
        #expect(MeetingTitle.meetPageName(["Weekly sync"]) == nil)
        #expect(MeetingTitle.meetPageName(["16:29"]) == nil)
    }

    @Test func clocks() {
        for text in ["16:29", "4:29 PM", "4:29pm", "9:05 a.m."] { #expect(MeetingTitle.isClock(text), "\(text)") }
        for text in ["Weekly sync", "1629", "16:2"] { #expect(!MeetingTitle.isClock(text), "\(text)") }
    }
}
