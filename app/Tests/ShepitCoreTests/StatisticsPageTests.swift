import Foundation
import Testing
@testable import ShepitCore

// Statistics design §5: the section's texts from small hand-made rows. The numbers are tested in StatsTests.
struct StatisticsPageTests {
    private var kyiv: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 3 * 3600)!
        calendar.firstWeekday = 2
        return calendar
    }

    @Test func overviewTilesWithTheirChangeAndTheTypingSpeed() {
        let rows = Stats.Rows(dictations: [statsRow(words: 40), statsRow(words: 20)], meetings: [meetingRow(duration: 2160)])
        let previous = Stats.Rows(dictations: [statsRow(words: 40)])
        let page = StatisticsPage.overview(rows, previous: previous, unit: .day, wpm: 40, calendar: kyiv)
        #expect(page.tiles.map(\.title) == ["Dictations", "Words", "Meetings · hours", "Time saved"])
        #expect(page.tiles.map(\.value) == ["2", "60", "1 · 0.6 h", "1 min"])
        // Twice the dictations; 40 → 60 words; no meetings before; 48 s → 66 s saved.
        #expect(page.tiles.map(\.change) == ["▲ 100% vs previous", "▲ 50% vs previous", nil, "▲ 38% vs previous"])
        #expect(page.tiles.map(\.link) == [nil, nil, nil, "at 40 wpm"])
        #expect(page.bucket == "day" && page.words.map(\.dictation) == [60])
        // All history: nothing to compare with.
        #expect(StatisticsPage.overview(rows, previous: nil, unit: .month, wpm: 40).tiles.allSatisfy { $0.change == nil })
    }

    @Test func dictationBlocks() {
        let rows = [statsRow(audio: 10, wait: 1, detected: "uk", terms: ["Kubernetes"]), statsRow(audio: 20, wait: 4, detected: "en+uk"),
                    statsRow(audio: 10, wait: 3, detected: "uk+en"), statsRow(outcome: .cancelled, detected: nil),
                    statsRow(outcome: .discarded, detected: nil)]
        let page = StatisticsPage.dictation(rows, unit: .day, calendar: kyiv)
        #expect(page.dictations == 3 && page.attempts == 4)
        #expect(page.speed == [.init(engine: "whisper.cpp large-v3-turbo", wait: "3.0 s", per10s: "2.00 s")])
        #expect(page.lines == ["whisper.cpp large-v3-turbo"] && page.points.map(\.label) == ["2.00 s"])
        #expect(page.apps == [.init(name: "Slack", value: 3, label: "3")])
        #expect(page.languages == [.init(name: "Ukrainian + English", value: "67% · 2"), .init(name: "Ukrainian", value: "33% · 1")])
        #expect(page.fixes == [.init(name: "Fixes made", value: "1"), .init(name: "Most corrected", value: "Kubernetes ×1")])
        #expect(page.failures == [.init(name: "Cancelled", value: "25% · 1"), .init(name: "Failed", value: "0% · 0"),
                                  .init(name: "Nothing recognized", value: "0% · 0")])
        #expect(page.attemptsNote == "Of 4 attempts in this period.")
        #expect(StatisticsPage.dictation([statsRow(outcome: .failed)], unit: .day).attemptsNote == "Of 1 attempt in this period.")
        #expect(StatisticsPage.dictation([statsRow()], unit: .day).fixes == [.init(name: "Fixes made", value: "0")])
    }

    @Test func meetingTilesChangeByDifferenceForTheShareAndPeople() {
        let rows = Stats.Rows(meetings: [meetingRow(duration: 3600, mine: 44, call: 56, speakers: 2, app: .teams),
                                         meetingRow(duration: 1800, mine: 0, call: 0, speakers: nil, diarization: nil, failed: 0)])
        let previous = Stats.Rows(meetings: [meetingRow(duration: 3600, mine: 40, call: 60, speakers: 3)])
        let page = StatisticsPage.meetings(rows, previous: previous)
        #expect(page.count == 2)
        #expect(page.tiles.map(\.value) == ["2", "1.5 h", "44%", "3.0"])
        #expect(page.tiles.map(\.change) == ["▲ 100% vs previous", "▲ 50% vs previous", "▲ 4 pts vs previous", "▼ 1.0 vs previous"])
        #expect(page.apps == [.init(name: "Teams", value: 1, label: "1 · 1.0 h"), .init(name: "Unknown", value: 1, label: "1 · 0.5 h")])
        #expect(page.length == [.init(name: "Average", value: "45 min"), .init(name: "Longest", value: "1 h 0 min")])
        #expect(page.lengths.map(\.label) == ["0", "0", "1", "1"])
        #expect(page.detection == [.init(name: "Ran in", value: "1 of 2 meetings"), .init(name: "Median time", value: "12 s"),
                                   .init(name: "Failed chunks", value: "1 in 1 meeting")])
        let none = StatisticsPage.meetings(Stats.Rows(), previous: nil)
        #expect(none.tiles.map(\.value) == ["0", "0 h", "–", "–"] && none.tiles.allSatisfy { $0.change == nil })
        #expect(none.detection == [.init(name: "Ran in", value: "0 of 0 meetings"), .init(name: "Failed chunks", value: "None")])
        #expect(none.offers == nil)
    }

    @Test func callOffersByOutcomeWithAColumnPerAppThatHadOffers() {
        let time = Date(timeIntervalSince1970: 0)
        let offers = [OfferRow(time: time, app: .teams, outcome: .started), OfferRow(time: time, app: .meet, outcome: .started),
                      OfferRow(time: time, app: .meet, outcome: .hidden)]
        let table = StatisticsPage.meetings(Stats.Rows(offers: offers), previous: nil).offers
        #expect(table?.columns == ["All", "Teams", "Google Meet"])
        #expect(table?.rows.map(\.outcome) == ["Started", "Started automatically", "Dismissed", "Hidden by time"])
        #expect(table?.rows.map(\.counts) == [[2, 1, 1], [0, 0, 0], [0, 0, 0], [1, 0, 1]])
    }

    @Test func texts() {
        #expect([0, 0.6, 9.96, 14.4].map(StatisticsPage.hours) == ["0 h", "0.6 h", "10.0 h", "14 h"])
        #expect([21.0, 2940, 5580].map(StatisticsPage.duration) == ["21 s", "49 min", "1 h 33 min"])
        let start = kyiv.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 14))!
        #expect([Calendar.Component.hour, .day, .weekOfYear, .month].map { StatisticsPage.title(start, $0, calendar: kyiv) }
            == ["9 Nov, 14:00", "9 Nov", "Week of 9 Nov", "Nov 2026"])
        #expect(CallApp.allCases.map(\.title) == ["Teams", "Zoom", "Google Meet"] && CallApp.title(of: "Webex") == "Webex")
    }
}
