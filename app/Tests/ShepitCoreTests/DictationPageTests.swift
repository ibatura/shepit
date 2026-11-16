import Foundation
import Testing
@testable import ShepitCore

// Dictations and Dictionary design §5.
struct DictationPageTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        return calendar
    }()

    private func at(_ month: Int, _ day: Int, _ hour: Int = 10, _ minute: Int = 0, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func entry(_ id: Int, _ time: Date, app: String? = "Slack", words: Int = 7) -> DictationStore.Entry {
        .init(id: id, time: time, appName: app, appBundleID: nil, text: "text \(id)", words: words)
    }

    /// A day's title, then its entries' ids, as the list shows them.
    private func shown(_ lines: [DictationPage.Line]) -> [String] {
        lines.map {
            switch $0 {
            case .day(let title): title
            case .entry(let row): "\(row.entry.id)"
            }
        }
    }

    @Test func entriesAreListedByDayNewestFirst() {
        let entries = [
            entry(6, at(11, 16, 14, 2)), entry(5, at(11, 16, 0, 5)),
            entry(4, at(11, 15, 23, 59)),
            entry(3, at(11, 13, 9)), entry(2, at(11, 13, 8)),
            entry(1, at(12, 31, 18, year: 2025)),
        ]
        let lines = DictationPage.lines(entries, now: at(11, 16, 18), calendar: calendar)
        #expect(shown(lines) == ["Today", "6", "5", "Yesterday", "4", "13 November", "3", "2", "31 December 2025", "1"])
        #expect(Set(lines.map(\.id)).count == lines.count)
    }

    @Test func aRowSaysTimeAppAndWords() {
        let lines = DictationPage.lines([entry(2, at(11, 16, 14, 2)), entry(1, at(11, 16, 9, 5), app: nil, words: 1)],
                                        now: at(11, 16, 18), calendar: calendar)
        let details = lines.compactMap { if case .entry(let row) = $0 { row.detail } else { nil } }
        #expect(details == ["14:02 · Slack · 7 words", "09:05 · 1 word"])
    }

    @Test func noEntriesNoLines() {
        #expect(DictationPage.lines([], now: at(11, 16), calendar: calendar).isEmpty)
    }

    @Test func whenIsTheTimeTodayAndTheDateBefore() {
        #expect(DictationPage.when(at(11, 16, 14, 2), now: at(11, 16, 18), calendar: calendar) == "14:02")
        #expect(DictationPage.when(at(11, 5, 9, 1), now: at(11, 16, 18), calendar: calendar) == "05.11 09:01")
    }

    @Test func datesAreGregorianWhateverTheCalendar() {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = calendar.timeZone
        let lines = DictationPage.lines([entry(1, at(12, 31, 18, year: 2025))], now: at(11, 16, 18), calendar: buddhist)
        #expect(shown(lines) == ["31 December 2025", "1"])
    }

    @Test func aPeriodStartsAtTheBeginningOfADay() {
        let now = at(11, 16, 18)
        let since = DictationPage.Period.allCases.map { $0.since(now, calendar: calendar) }
        #expect(since == [at(11, 16, 0), at(11, 10, 0), at(10, 16, 0), at(8, 16, 0), at(5, 16, 0), at(2, 16, 0),
                          at(11, 16, 0, year: 2025), nil])
        #expect(DictationPage.Period.allCases.map(\.title) == ["Today", "Last 7 days", "Last month", "Last 3 months", "Last 6 months",
                                                               "Last 9 months", "Last year", "All history"])
    }

    @Test func keptSaysHowLongHistoryStays() {
        #expect(DictationPage.kept(days: 0) == "Kept forever")
        #expect(DictationPage.kept(days: 1) == "Kept for 1 day")
        #expect(DictationPage.kept(days: 30) == "Kept for 30 days")
    }
}
