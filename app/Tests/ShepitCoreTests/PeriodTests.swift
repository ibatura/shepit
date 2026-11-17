import Foundation
import Testing
@testable import ShepitCore

// Dictations' Show menu (Dictations and Dictionary design §5) and Statistics' period (statistics design §4).
struct PeriodTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        return calendar
    }()

    private func at(_ month: Int, _ day: Int, _ hour: Int = 10, _ minute: Int = 0, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func range(_ period: StatsPeriod, now: Date) -> DateInterval? { period.range(now: now, calendar: calendar) }
    private func previous(_ period: StatsPeriod, now: Date) -> DateInterval? { period.previous(now: now, calendar: calendar) }

    @Test func aPeriodStartsAtTheBeginningOfADay() {
        let now = at(11, 16, 18)
        let since = Period.allCases.map { $0.since(now, calendar: calendar) }
        #expect(since == [at(11, 16, 0), at(11, 10, 0), at(10, 16, 0), at(8, 16, 0), at(5, 16, 0), at(2, 16, 0),
                          at(11, 16, 0, year: 2025), nil])
        #expect(Period.allCases.map(\.title) == ["Today", "Last 7 days", "Last month", "Last 3 months", "Last 6 months",
                                                 "Last 9 months", "Last year", "All history"])
    }

    @Test func aPresetRunsFromItsFirstDayToNow() {
        let now = at(11, 16, 18, 30)
        #expect(range(.preset(.today), now: now) == DateInterval(start: at(11, 16, 0), end: now))
        #expect(range(.preset(.month), now: now) == DateInterval(start: at(10, 16, 0), end: now))
        #expect(range(.preset(.all), now: now) == nil)
    }

    @Test func aCustomRangeTakesWholeDaysUpToNow() {
        let now = at(11, 16, 18, 30)
        #expect(range(.custom(from: at(11, 12, 15), through: at(11, 14, 9)), now: now) == DateInterval(start: at(11, 12, 0), end: at(11, 15, 0)))
        #expect(range(.custom(from: at(11, 3), through: at(11, 3)), now: now) == DateInterval(start: at(11, 3, 0), end: at(11, 4, 0)))
        #expect(range(.custom(from: at(11, 14), through: at(11, 16)), now: now) == DateInterval(start: at(11, 14, 0), end: now))
        // An end before the start (the popover doesn't allow one) gives an empty range, not a crash.
        #expect(range(.custom(from: at(11, 14), through: at(11, 12)), now: now)?.duration == 0)
    }

    @Test func thePreviousPeriodIsAsManyDaysBeforeUpToTheSameMoment() {
        let now = at(11, 16, 18, 30)
        #expect(previous(.preset(.today), now: now) == DateInterval(start: at(11, 15, 0), end: at(11, 15, 18, 30)))
        #expect(previous(.preset(.week), now: now) == DateInterval(start: at(11, 3, 0), end: at(11, 9, 18, 30)))
        // Last month is 16 Oct – 16 Nov, 32 days with today: the 32 days before it.
        #expect(previous(.preset(.month), now: now) == DateInterval(start: at(9, 14, 0), end: at(10, 15, 18, 30)))
        #expect(previous(.custom(from: at(11, 12), through: at(11, 14)), now: now) == DateInterval(start: at(11, 9, 0), end: at(11, 12, 0)))
        #expect(previous(.custom(from: at(11, 14), through: at(11, 16)), now: now) == DateInterval(start: at(11, 11, 0), end: at(11, 13, 18, 30)))
        #expect(previous(.preset(.all), now: now) == nil)
    }

    @Test func thePreviousPeriodCrossesMonthEndsAndClockChanges() throws {
        // A custom range over a month end: 30 Nov – 2 Dec, against 27–29 Nov.
        let december = previous(.custom(from: at(11, 30), through: at(12, 2)), now: at(12, 10))
        #expect(december == DateInterval(start: at(11, 27, 0), end: at(11, 30, 0)))
        // Kyiv's clocks went back on 25 Oct 2026, so that day had 25 hours: yesterday until this time still starts
        // at midnight and ends at 18:30.
        let afterChange = try #require(previous(.preset(.today), now: at(10, 26, 18, 30)))
        #expect(afterChange == DateInterval(start: at(10, 25, 0), end: at(10, 25, 18, 30)))
        #expect(afterChange.duration == 19.5 * 3600)
        let oneDay = try #require(range(.custom(from: at(10, 25), through: at(10, 25)), now: at(11, 16)))
        #expect(oneDay.duration == 25 * 3600)
    }

    @Test func bucketsFollowTheLengthOfThePeriod() {
        let now = at(11, 16, 18)
        func bucket(_ period: StatsPeriod) -> Calendar.Component { period.bucket(now: now, calendar: calendar) }
        #expect(bucket(.preset(.today)) == .hour && bucket(.custom(from: at(11, 3), through: at(11, 3))) == .hour)
        #expect(bucket(.preset(.week)) == .day && bucket(.preset(.month)) == .day)
        #expect(bucket(.custom(from: at(10, 1), through: at(10, 31))) == .day)
        #expect(bucket(.custom(from: at(10, 1), through: at(11, 2))) == .weekOfYear)
        #expect(bucket(.preset(.months3)) == .weekOfYear && bucket(.preset(.months6)) == .weekOfYear)
        #expect(bucket(.preset(.months9)) == .month && bucket(.preset(.year)) == .month && bucket(.preset(.all)) == .month)
    }

    @Test func theMenuTitle() {
        #expect(StatsPeriod.preset(.month).title(calendar: calendar) == "Last month")
        #expect(StatsPeriod.custom(from: at(11, 12), through: at(11, 16)).title(calendar: calendar) == "12 Nov – 16 Nov 2026")
        #expect(StatsPeriod.custom(from: at(11, 16), through: at(11, 16)).title(calendar: calendar) == "16 Nov 2026")
        #expect(StatsPeriod.custom(from: at(12, 28, year: 2025), through: at(1, 3)).title(calendar: calendar) == "28 Dec 2025 – 3 Jan 2026")
    }
}
