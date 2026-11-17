import Foundation

/// The Statistics section as plain data (statistics design §5): each view's tiles, bars, lines and charts with their
/// texts, from the rows of the period and of the one before. The views in the window only draw it.
public enum StatisticsPage {
    /// A headline number with its change against the previous period ("▲ 12% vs previous"); no change for All history
    /// or with nothing before. `link` is the text of a link under it ("at 40 wpm").
    public struct Tile: Equatable, Sendable {
        public var title: String
        public var value: String
        public var change: String?
        public var link: String?
    }

    /// A bar: its name, its length and the text beside it ("Teams", 8, "8 · 6.0 h").
    public struct Bar: Equatable, Sendable {
        public var name: String
        public var value: Double
        public var label: String
    }

    /// A line of a block: "Average", "49 min".
    public struct Line: Equatable, Sendable {
        public var name: String
        public var value: String
    }

    // MARK: Overview (§5.1)

    public struct Overview: Equatable, Sendable {
        /// Dictations, Words, Meetings · hours, Time saved.
        public var tiles: [Tile]
        /// "hour", "day", "week", "month": the bars of Words per day.
        public var bucket: String
        public var words: [Stats.WordsBucket]
    }

    public static func overview(_ rows: Stats.Rows, previous: Stats.Rows?, unit: Calendar.Component, wpm: Int,
                                calendar: Calendar = .current) -> Overview {
        func tile(_ title: String, _ value: String, link: String? = nil, _ number: (Stats.Rows) -> Double) -> Tile {
            Tile(title: title, value: value, change: previous.flatMap { change(number(rows), number($0)) }, link: link)
        }
        let meetings = rows.meetings
        return Overview(
            tiles: [
                tile("Dictations", Stats.dictations(rows.dictations).formatted()) { Double(Stats.dictations($0.dictations)) },
                tile("Words", Stats.words(rows.dictations).formatted()) { Double(Stats.words($0.dictations)) },
                tile("Meetings · hours", "\(meetings.count) · \(hours(Stats.meetingHours(meetings)))") { Stats.meetingHours($0.meetings) },
                tile("Time saved", duration(Stats.timeSaved(rows.dictations, wpm: wpm)), link: "at \(wpm) wpm") {
                    Stats.timeSaved($0.dictations, wpm: wpm)
                },
            ],
            bucket: name(unit), words: Stats.wordsPerBucket(rows.dictations, meetings: meetings, unit: unit, calendar: calendar))
    }

    // MARK: Dictation (§5.2)

    public struct Dictation: Equatable, Sendable {
        /// Successful dictations and all attempts (taps too short to record left out): the view shows its blocks only
        /// with the first, Failures with the second.
        public var dictations: Int
        public var attempts: Int
        public var speed: [Speed]
        /// The lines of Speed over time in the order of their colours, and their points.
        public var lines: [String]
        public var points: [SpeedPoint]
        /// "hour", "day", "week", "month".
        public var bucket: String
        public var apps: [Bar]
        /// Successful dictations per [weekday][hour], Monday first.
        public var heatmap: [[Int]]
        public var languages: [Line]
        public var fixes: [Line]
        public var failures: [Line]
        /// "Of 269 attempts in this period."
        public var attemptsNote: String
    }

    /// A row of the speed table: "whisper.cpp large-v3-turbo", "2.4 s", "1.15 s".
    public struct Speed: Equatable, Sendable {
        public var engine, wait, per10s: String
    }

    /// A point of Speed over time and its tooltip text ("1.15 s").
    public struct SpeedPoint: Equatable, Sendable {
        public var line: String
        public var start: Date
        public var seconds: Double
        public var label: String
    }

    public static func dictation(_ rows: [DictationRow], unit: Calendar.Component, calendar: Calendar = .current) -> Dictation {
        let points = Stats.speedOverTime(rows, unit: unit, calendar: calendar).map {
            SpeedPoint(line: $0.engine.title, start: $0.start, seconds: $0.medianWaitPer10s, label: seconds($0.medianWaitPer10s, digits: 2))
        }
        let languages = Stats.languages(rows), detected = languages.reduce(0) { $0 + $1.count }
        let fixes = Stats.fixes(rows), failures = Stats.failures(rows)
        func failure(_ name: String, _ count: Int) -> Line { Line(name: name, value: "\(percent(failures.share(count))) · \(count)") }
        return Dictation(
            dictations: Stats.dictations(rows), attempts: failures.attempts,
            speed: Stats.speedByEngine(rows).map {
                Speed(engine: $0.engine.title, wait: seconds($0.medianWait, digits: 1), per10s: seconds($0.medianWaitPer10s, digits: 2))
            },
            lines: points.map(\.line).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }, points: points, bucket: name(unit),
            apps: Stats.topApps(rows).map { Bar(name: $0.name, value: Double($0.count), label: "\($0.count)") },
            heatmap: Stats.heatmap(rows),
            languages: languages.map { Line(name: language($0.name), value: "\(percent(Double($0.count) / Double(detected))) · \($0.count)") },
            fixes: [Line(name: "Fixes made", value: "\(fixes.count)")]
                + (fixes.topTerms.isEmpty ? [] : [Line(name: "Most corrected", value: fixes.topTerms.map { "\($0.name) ×\($0.count)" }.joined(separator: ", "))]),
            failures: [failure("Cancelled", failures.cancelled), failure("Failed", failures.failed), failure("Nothing recognized", failures.empty)],
            attemptsNote: "Of \(count(failures.attempts, "attempt")) in this period.")
    }

    /// "uk+en" → "Ukrainian + English"; a code Shepit has no name for stays as it is.
    private static func language(_ key: String) -> String {
        key.split(separator: "+").map { code in Settings.languages.first { $0.value == code }?.title ?? String(code) }.joined(separator: " + ")
    }

    // MARK: Meetings (§5.3)

    public struct Meetings: Equatable, Sendable {
        public var count: Int
        /// Meetings, Hours, Your share of words, People per meeting.
        public var tiles: [Tile]
        public var apps: [Bar]
        /// Average and Longest, then the meetings by length.
        public var length: [Line]
        public var lengths: [Bar]
        public var detection: [Line]
        /// Nil when the period has no offers.
        public var offers: Offers?
    }

    /// How the call panel's offers ended: an outcome a row, "All" and then each app with offers a column.
    public struct Offers: Equatable, Sendable {
        public var columns: [String]
        public var rows: [OfferLine]
    }

    public struct OfferLine: Equatable, Sendable {
        public var outcome: String
        public var counts: [Int]
    }

    public static func meetings(_ rows: Stats.Rows, previous: Stats.Rows?) -> Meetings {
        let meetings = rows.meetings, before = previous?.meetings
        let share = Stats.yourShare(meetings), people = Stats.peoplePerMeeting(meetings)
        let lengths = Stats.lengths(meetings), detection = Stats.speakerDetection(meetings)
        return Meetings(
            count: meetings.count,
            tiles: [
                Tile(title: "Meetings", value: "\(meetings.count)",
                     change: before.flatMap { change(Double(meetings.count), Double($0.count)) }),
                Tile(title: "Hours", value: hours(Stats.meetingHours(meetings)),
                     change: before.flatMap { change(Stats.meetingHours(meetings), Stats.meetingHours($0)) }),
                // A share and an average change by their difference: 40% → 44% is "▲ 4 pts", not "▲ 10%".
                Tile(title: "Your share of words", value: share.map(percent) ?? "–",
                     change: difference(share, before.flatMap(Stats.yourShare)) { "\(Int(($0 * 100).rounded())) pts" }),
                Tile(title: "People per meeting", value: people.map { String(format: "%.1f", $0) } ?? "–",
                     change: difference(people, before.flatMap(Stats.peoplePerMeeting)) { String(format: "%.1f", $0) }),
            ],
            apps: Stats.meetingsByApp(meetings).map {
                Bar(name: $0.app?.title ?? "Unknown", value: Double($0.count), label: "\($0.count) · \(hours($0.hours))")
            },
            length: [Line(name: "Average", value: duration(lengths.average)), Line(name: "Longest", value: duration(lengths.longest))],
            lengths: lengths.groups.map { Bar(name: $0.name, value: Double($0.count), label: "\($0.count)") },
            detection: [Line(name: "Ran in", value: "\(detection.meetings) of \(count(meetings.count, "meeting"))")]
                + (detection.meetings > 0 ? [Line(name: "Median time", value: duration(detection.medianSeconds))] : [])
                + [Line(name: "Failed chunks", value: detection.failedChunks == 0 ? "None"
                        : "\(detection.failedChunks) in \(count(detection.meetingsWithFailedChunks, "meeting"))")],
            offers: offers(rows.offers))
    }

    private static func offers(_ rows: [OfferRow]) -> Offers? {
        guard !rows.isEmpty else { return nil }
        let apps = CallApp.allCases.filter { app in rows.contains { $0.app == app } }
        return Offers(columns: ["All"] + apps.map(\.title), rows: CallOffer.Outcome.allCases.map { outcome in
            OfferLine(outcome: title(outcome), counts: ([nil] + apps.map(Optional.some)).map { Stats.offers(rows, ending: outcome, in: $0) })
        })
    }

    private static func title(_ outcome: CallOffer.Outcome) -> String {
        switch outcome {
        case .started: "Started"
        case .startedAutomatically: "Started automatically"
        case .dismissed: "Dismissed"
        case .hidden: "Hidden by time"
        }
    }

    // MARK: Texts

    /// A bucket in a tooltip: "16 Nov, 14:00", "16 Nov", "Week of 9 Nov", "Nov 2026".
    public static func title(_ start: Date, _ unit: Calendar.Component, calendar: Calendar = .current) -> String {
        let format = switch unit {
        case .hour: "d MMM, HH:mm"
        case .day: "d MMM"
        case .weekOfYear: "'Week of' d MMM"
        default: "MMM yyyy"
        }
        return DateFormatter.english(format, calendar).string(from: start)
    }

    /// "hour", "day", "week", "month".
    static func name(_ unit: Calendar.Component) -> String {
        switch unit {
        case .hour: "hour"
        case .day: "day"
        case .weekOfYear: "week"
        default: "month"
        }
    }

    /// "▲ 12% vs previous"; nil when there was nothing before.
    static func change(_ current: Double, _ previous: Double) -> String? {
        Stats.delta(current: current, previous: previous).map { arrow($0 >= 0) + percent(abs($0)) + " vs previous" }
    }

    /// "▲ 4 pts vs previous"; nil when either is missing.
    static func difference(_ current: Double?, _ previous: Double?, _ text: (Double) -> String) -> String? {
        guard let current, let previous else { return nil }
        return arrow(current >= previous) + text(abs(current - previous)) + " vs previous"
    }

    private static func arrow(_ up: Bool) -> String { up ? "▲ " : "▼ " }

    static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    /// "0 h", "0.6 h", "14 h".
    static func hours(_ value: Double) -> String {
        value == 0 ? "0 h" : value < 10 ? String(format: "%.1f h", value) : "\(Int(value.rounded())) h"
    }

    /// "21 s", "49 min", "1 h 33 min".
    static func duration(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        if minutes >= 60 { return "\(minutes / 60) h \(minutes % 60) min" }
        return minutes > 0 ? "\(minutes) min" : "\(Int(seconds)) s"
    }

    private static func seconds(_ value: Double, digits: Int) -> String { String(format: "%.\(digits)f s", value) }

    /// "1 meeting", "3 meetings".
    private static func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
}
