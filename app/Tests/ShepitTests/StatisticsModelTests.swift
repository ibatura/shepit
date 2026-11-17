import Foundation
import Testing
@testable import Shepit
import ShepitCore

// Statistics design §4–5: what the section reads and remembers. The numbers themselves are tested in StatsTests,
// the periods in PeriodTests.
@MainActor
struct StatisticsModelTests {
    private let now = Date()

    private func rig() throws -> (StatsDatabase, UserDefaults, URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "statistics-model-\(UUID().uuidString)")
        let defaults = try #require(UserDefaults(suiteName: "statistics-model-\(UUID().uuidString)"))
        return (StatsDatabase(file: dir.appending(path: "stats.sqlite")), defaults, dir)
    }

    private func statistics(_ stats: StatsDatabase, _ defaults: UserDefaults) -> StatisticsModel {
        StatisticsModel(stats: stats, typingSpeed: { 40 }, defaults: defaults)
    }

    private func dictation(daysAgo: Double) -> DictationRow {
        DictationRow(time: now.addingTimeInterval(-daysAgo * 86_400), tzOffset: 0, outcome: .pasted, audioSeconds: 5, waitSeconds: 1,
                     words: 10, characters: 60, engine: EngineChoice(engine: .whispercpp, model: "large-v3-turbo"), languageRequested: "uk",
                     languageDetected: "uk", appBundleID: nil, appName: nil, replacedTerms: [], previewRequests: 0)
    }

    @Test func pagesAreBuiltOnAppearAndOnAPeriodChangeOnly() throws {
        let (stats, defaults, dir) = try rig()
        defer { try? FileManager.default.removeItem(at: dir) }
        try stats.insert(dictation(daysAgo: 3))
        try stats.insert(dictation(daysAgo: 40))
        try stats.insertMeeting(MeetingRecord(start: now.addingTimeInterval(-86_400), duration: 600, wordsMine: 1, wordsCall: 2, speakers: 1,
                                              engine: EngineChoice(engine: .whispercpp, model: "m"), diarizationSeconds: 1,
                                              failedChunks: 0, app: .teams))
        try stats.insertOffer(OfferRow(time: now.addingTimeInterval(-60), app: .meet, outcome: .dismissed))
        let model = statistics(stats, defaults)
        #expect(model.period == .preset(.month))
        #expect(model.pages.dictation.attempts == 0) // nothing before the section is shown

        model.reload()
        #expect(model.pages.dictation.attempts == 1)
        #expect(model.pages.meetings.apps.map(\.name) == ["Teams"])
        #expect(model.pages.meetings.offers?.rows.first { $0.outcome == "Dismissed" }?.counts == [1, 1]) // All, Google Meet
        // 40 days ago is in the 32 days before Last month: one dictation then and now.
        #expect(model.pages.overview.tiles.first?.change == "▲ 0% vs previous")
        #expect(model.pages.unit == .day && model.pages.overview.tiles.last?.link == "at 40 wpm")

        try stats.insert(dictation(daysAgo: 1))
        model.tab = .meetings
        #expect(model.pages.dictation.attempts == 1) // switching views reads nothing
        model.period = .preset(.all)
        #expect(model.pages.dictation.attempts == 3)
        #expect(model.pages.overview.tiles.allSatisfy { $0.change == nil })
    }

    @Test func theViewAndThePeriodAreRememberedACustomRangeToo() throws {
        let (stats, defaults, dir) = try rig()
        defer { try? FileManager.default.removeItem(at: dir) }
        let from = now.addingTimeInterval(-5 * 86_400)
        let model = statistics(stats, defaults)
        #expect(model.tab == .overview)
        model.tab = .dictation
        model.period = .custom(from: from, through: now)
        let again = statistics(stats, defaults)
        #expect(again.tab == .dictation)
        #expect(again.period == .custom(from: from, through: now))
        again.period = .preset(.week)
        #expect(statistics(stats, defaults).period == .preset(.week))
    }

    @Test func customOpensWithTheShownDays() throws {
        let (stats, defaults, dir) = try rig()
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = statistics(stats, defaults)
        model.period = .preset(.week)
        // The days as read, so a test across midnight doesn't fail.
        #expect(model.customDays.from == Period.week.since(model.readAt) && model.customDays.through == model.readAt)
        model.period = .preset(.all)
        #expect(model.customDays.from == Calendar.current.startOfDay(for: model.readAt))
        let from = now.addingTimeInterval(-9 * 86_400), through = now.addingTimeInterval(-2 * 86_400)
        model.period = .custom(from: from, through: through)
        #expect(model.customDays.from == from && model.customDays.through == through)
    }
}
