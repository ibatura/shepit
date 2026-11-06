import Foundation

/// One stored dictation attempt (`05-statistics.md` §1). Numbers and names only — never dictated text.
public struct DictationRow: Equatable, Sendable {
    public var time: Date
    /// Seconds from GMT at the time of the dictation, so the heatmap uses the hour the user saw.
    public var tzOffset: Int
    public var outcome: DictationOutcome
    public var audioSeconds: Double
    public var waitSeconds: Double
    public var words: Int
    public var characters: Int
    public var engine: String
    public var model: String
    public var languageRequested: String
    public var languageDetected: String?
    public var appBundleID: String?
    public var appName: String?
    public var replacedTerms: [String]
    public var previewRequests: Int

    public var replacements: Int { replacedTerms.count }

    public init(
        time: Date, tzOffset: Int, outcome: DictationOutcome, audioSeconds: Double, waitSeconds: Double, words: Int,
        characters: Int, engine: String, model: String, languageRequested: String, languageDetected: String?,
        appBundleID: String?, appName: String?, replacedTerms: [String], previewRequests: Int
    ) {
        self.time = time
        self.tzOffset = tzOffset
        self.outcome = outcome
        self.audioSeconds = audioSeconds
        self.waitSeconds = waitSeconds
        self.words = words
        self.characters = characters
        self.engine = engine
        self.model = model
        self.languageRequested = languageRequested
        self.languageDetected = languageDetected
        self.appBundleID = appBundleID
        self.appName = appName
        self.replacedTerms = replacedTerms
        self.previewRequests = previewRequests
    }

    public init(_ record: DictationRecord, engine: EngineChoice, languageRequested: String, previewRequests: Int, timeZone: TimeZone = .current) {
        self.init(
            time: record.startedAt, tzOffset: timeZone.secondsFromGMT(for: record.startedAt), outcome: record.outcome,
            audioSeconds: record.audioSeconds, waitSeconds: record.waitSeconds, words: record.words, characters: record.characters,
            engine: engine.engine.rawValue, model: engine.model, languageRequested: languageRequested,
            languageDetected: record.detectedLanguage, appBundleID: record.app?.bundleID, appName: record.app?.name,
            replacedTerms: record.firedTerms, previewRequests: previewRequests)
    }

    var succeeded: Bool { outcome == .pasted || outcome == .copied }
}

public enum StatsPeriod: String, CaseIterable, Sendable {
    case day, week, month, year, all
}

/// Aggregations for the Statistics screen (`05-statistics.md` §2), all over plain rows.
public enum Stats {
    public struct EngineSpeed: Hashable, Sendable {
        public var engine: String
        public var model: String
        public var medianWait: Double
        public var medianWaitPer10s: Double
    }

    public struct WordsBucket: Equatable, Sendable {
        public var start: Date
        public var dictation: Int
        public var meetings: Int
    }

    public struct Quality: Equatable, Sendable {
        public var cancelledShare: Double
        public var failedShare: Double
        public var emptyShare: Double
        public var detectedLanguages: [String: Int]
        public var fixes: Int
        public var topTerms: [(term: String, count: Int)]

        public static func == (a: Quality, b: Quality) -> Bool {
            a.cancelledShare == b.cancelledShare && a.failedShare == b.failedShare && a.emptyShare == b.emptyShare
                && a.detectedLanguages == b.detectedLanguages && a.fixes == b.fixes
                && a.topTerms.map(\.term) == b.topTerms.map(\.term) && a.topTerms.map(\.count) == b.topTerms.map(\.count)
        }
    }

    /// The period containing `now`; nil for All.
    public static func range(_ period: StatsPeriod, now: Date, calendar: Calendar = .current) -> DateInterval? {
        component(period).flatMap { calendar.dateInterval(of: $0, for: now) }
    }

    /// The calendar period right before `range` (yesterday, last week, last month…), so DST days
    /// and months of different lengths line up.
    public static func previous(_ range: DateInterval, _ period: StatsPeriod, calendar: Calendar = .current) -> DateInterval? {
        component(period).flatMap { calendar.dateInterval(of: $0, for: range.start.addingTimeInterval(-1)) }
    }

    private static func component(_ period: StatsPeriod) -> Calendar.Component? {
        switch period {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        case .all: nil
        }
    }

    public static func dictations(_ rows: [DictationRow]) -> Int {
        rows.filter(\.succeeded).count
    }

    public static func words(_ rows: [DictationRow]) -> Int {
        rows.filter(\.succeeded).reduce(0) { $0 + $1.words }
    }

    /// Seconds saved compared with typing: words ÷ wpm − (audio + wait), never below zero per dictation.
    public static func timeSaved(_ rows: [DictationRow], wpm: Int) -> Double {
        rows.filter(\.succeeded).reduce(0) { total, row in
            total + max(0, Double(row.words) / Double(wpm) * 60 - (row.audioSeconds + row.waitSeconds))
        }
    }

    /// Change against the previous period as a fraction; nil when there was nothing before.
    public static func delta(current: Double, previous: Double) -> Double? {
        previous == 0 ? nil : (current - previous) / previous
    }

    public static func bucketUnit(_ period: StatsPeriod) -> Calendar.Component {
        switch period {
        case .day: .hour
        case .week, .month: .day
        case .year, .all: .month
        }
    }

    /// Words per bucket start, oldest first (only buckets that have words): successful dictations and meetings
    /// (both streams) apart, for the stacked chart. A meeting counts in the bucket where it started.
    public static func wordsPerBucket(_ rows: [DictationRow], meetings: [MeetingRecord] = [], period: StatsPeriod,
                                      calendar: Calendar = .current) -> [WordsBucket] {
        let unit = bucketUnit(period)
        var buckets: [Date: WordsBucket] = [:]
        func add(_ time: Date, dictation: Int, meetings: Int) {
            guard dictation + meetings > 0, let start = calendar.dateInterval(of: unit, for: time)?.start else { return }
            buckets[start, default: WordsBucket(start: start, dictation: 0, meetings: 0)].dictation += dictation
            buckets[start, default: WordsBucket(start: start, dictation: 0, meetings: 0)].meetings += meetings
        }
        for row in rows where row.succeeded { add(row.time, dictation: row.words, meetings: 0) }
        for meeting in meetings { add(meeting.start, dictation: 0, meetings: meeting.wordsMine + meeting.wordsCall) }
        return buckets.values.sorted { $0.start < $1.start }
    }

    public static func meetingCount(_ meetings: [MeetingRecord]) -> Int { meetings.count }

    public static func meetingHours(_ meetings: [MeetingRecord]) -> Double {
        meetings.reduce(0) { $0 + $1.duration } / 3600
    }

    /// Median wait after stop per engine+model, plus per 10 s of audio so long and short dictations compare fairly.
    public static func speedByEngine(_ rows: [DictationRow]) -> [EngineSpeed] {
        let groups = Dictionary(grouping: rows.filter(\.succeeded)) { "\($0.engine)\t\($0.model)" }
        return groups.values.compactMap { group in
            guard let first = group.first else { return nil }
            let perTen = group.filter { $0.audioSeconds > 0 }.map { $0.waitSeconds / $0.audioSeconds * 10 }
            return EngineSpeed(engine: first.engine, model: first.model, medianWait: median(group.map(\.waitSeconds)),
                               medianWaitPer10s: median(perTen))
        }.sorted { ($0.engine, $0.model) < ($1.engine, $1.model) }
    }

    /// Apps by number of successful dictations: the top `limit`, the rest as "Other".
    public static func topApps(_ rows: [DictationRow], limit: Int = 8) -> [(name: String, count: Int)] {
        let counts = Dictionary(grouping: rows.filter(\.succeeded)) { $0.appName ?? "Unknown" }.mapValues(\.count)
        let sorted = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        var top = sorted.prefix(limit).map { (name: $0.key, count: $0.value) }
        let rest = sorted.dropFirst(limit).reduce(0) { $0 + $1.value }
        if rest > 0 { top.append((name: "Other", count: rest)) }
        return top
    }

    /// Successful dictations per [weekday][hour], weekday 0 = Monday, in each dictation's own local time.
    public static func heatmap(_ rows: [DictationRow]) -> [[Int]] {
        var grid = Array(repeating: Array(repeating: 0, count: 24), count: 7)
        var calendar = Calendar(identifier: .gregorian)
        for row in rows where row.succeeded {
            calendar.timeZone = TimeZone(secondsFromGMT: row.tzOffset) ?? .current
            let parts = calendar.dateComponents([.weekday, .hour], from: row.time)
            guard let weekday = parts.weekday, let hour = parts.hour else { continue }
            grid[(weekday + 5) % 7][hour] += 1 // Calendar: 1 = Sunday
        }
        return grid
    }

    public static func quality(_ rows: [DictationRow], topTerms limit: Int = 8) -> Quality {
        let total = Double(max(rows.count, 1))
        func share(_ outcome: DictationOutcome) -> Double { Double(rows.filter { $0.outcome == outcome }.count) / total }
        let detected = Dictionary(grouping: rows.compactMap(\.languageDetected)) { $0 }.mapValues(\.count)
        let terms = Dictionary(grouping: rows.flatMap(\.replacedTerms)) { $0 }.mapValues(\.count)
        let top = terms.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(limit).map { (term: $0.key, count: $0.value) }
        return Quality(cancelledShare: share(.cancelled), failedShare: share(.failed), emptyShare: share(.empty),
                       detectedLanguages: detected, fixes: rows.reduce(0) { $0 + $1.replacements }, topTerms: top)
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }
}
