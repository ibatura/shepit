import Foundation
import Observation
import ShepitCore

/// What the Statistics section shows (statistics design §4–5): the view, the period, and the three views' pages built
/// from the stored rows of the period and of the one before it. The rows are read on appear, on a change of period,
/// when something is recorded and when the day changes, once for all three views; nothing is read while the section
/// isn't shown.
@MainActor
@Observable
final class StatisticsModel {
    enum Tab: String, CaseIterable {
        case overview = "Overview", dictation = "Dictation", meetings = "Meetings"
    }

    /// The three views as the section draws them, and the bars of their charts over time.
    struct Pages {
        var overview: StatisticsPage.Overview
        var dictation: StatisticsPage.Dictation
        var meetings: StatisticsPage.Meetings
        var unit: Calendar.Component

        init(_ rows: Stats.Rows, previous: Stats.Rows?, unit: Calendar.Component, wpm: Int) {
            overview = StatisticsPage.overview(rows, previous: previous, unit: unit, wpm: wpm)
            dictation = StatisticsPage.dictation(rows.dictations, unit: unit)
            meetings = StatisticsPage.meetings(rows, previous: previous)
            self.unit = unit
        }
    }

    /// Remembered in the app's preferences, like Dictations' period.
    var tab: Tab { didSet { defaults.set(tab.rawValue, forKey: "statisticsView") } }
    var period: StatsPeriod {
        didSet {
            guard period != oldValue else { return }
            defaults.set(period, section: "statistics")
            reload()
        }
    }
    /// Empty until the section is shown.
    private(set) var pages: Pages

    @ObservationIgnored private let stats: StatsDatabase
    /// Settings → History and privacy, for Time saved.
    @ObservationIgnored private let typingSpeed: () -> Int
    @ObservationIgnored private let defaults: UserDefaults

    init(stats: StatsDatabase, typingSpeed: @escaping () -> Int, defaults: UserDefaults = .standard) {
        self.stats = stats
        self.typingSpeed = typingSpeed
        self.defaults = defaults
        tab = defaults.string(forKey: "statisticsView").flatMap(Tab.init) ?? .overview
        let period = defaults.period(section: "statistics")
        self.period = period
        pages = Pages(Stats.Rows(), previous: nil, unit: period.bucket(now: Date()), wpm: typingSpeed())
    }

    func reload() {
        let now = Date()
        do {
            let rows = try read(period.range(now: now))
            let previous = try period.previous(now: now).map(read)
            pages = Pages(rows, previous: previous, unit: period.bucket(now: now), wpm: typingSpeed())
        } catch {
            NSLog("Shepit statistics: %@", String(describing: error))
        }
    }

    private func read(_ range: DateInterval?) throws -> Stats.Rows {
        Stats.Rows(dictations: try stats.dictations(in: range), meetings: try stats.meetings(in: range), offers: try stats.offers(in: range))
    }
}
