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
    public var engine: EngineChoice
    public var languageRequested: String
    public var languageDetected: String?
    public var appBundleID: String?
    public var appName: String?
    public var replacedTerms: [String]
    public var previewRequests: Int

    public var replacements: Int { replacedTerms.count }

    public init(
        time: Date, tzOffset: Int, outcome: DictationOutcome, audioSeconds: Double, waitSeconds: Double, words: Int,
        characters: Int, engine: EngineChoice, languageRequested: String, languageDetected: String?,
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
            engine: engine, languageRequested: languageRequested,
            languageDetected: record.detectedLanguage, appBundleID: record.app?.bundleID, appName: record.app?.name,
            replacedTerms: record.firedTerms, previewRequests: previewRequests)
    }

    var succeeded: Bool { outcome == .pasted || outcome == .copied }
}

/// Aggregations for the Statistics section (statistics design §5), all over plain rows: numbers keyed by what the rows
/// hold. `StatisticsPage` turns them into the section's texts.
public enum Stats {
    /// The rows of one period, read once for all three views.
    public struct Rows: Sendable {
        public var dictations: [DictationRow]
        public var meetings: [MeetingRecord]
        public var offers: [OfferRow]

        public init(dictations: [DictationRow] = [], meetings: [MeetingRecord] = [], offers: [OfferRow] = []) {
            self.dictations = dictations
            self.meetings = meetings
            self.offers = offers
        }
    }

    /// How many rows have `name`: an app, a term, a language, a length group.
    public struct Count: Hashable, Sendable {
        public var name: String
        public var count: Int
    }

    public struct EngineSpeed: Hashable, Sendable {
        public var engine: EngineChoice
        public var medianWait: Double
        public var medianWaitPer10s: Double
    }

    public struct WordsBucket: Equatable, Sendable {
        public var start: Date
        public var dictation: Int
        public var meetings: Int
    }

    public struct Failures: Equatable, Sendable {
        /// The attempts (a tap too short to record isn't one), and those cancelled, failed and with nothing recognized.
        public var attempts: Int
        public var cancelled: Int
        public var failed: Int
        public var empty: Int

        /// `count` of all attempts; 0 with none.
        public func share(_ count: Int) -> Double { Double(count) / Double(max(attempts, 1)) }
    }

    /// Dictionary replacements made, and the terms they fired for most.
    public struct Fixes: Equatable, Sendable {
        public var count: Int
        public var topTerms: [Count]
    }

    /// A point of Speed over time: one engine and model in one bucket.
    public struct SpeedPoint: Hashable, Sendable {
        public var engine: EngineChoice
        public var start: Date
        public var medianWaitPer10s: Double
    }

    public struct AppMeetings: Equatable, Sendable {
        /// Nil: a meeting Shepit couldn't tie to an app.
        public var app: CallApp?
        public var count: Int
        public var hours: Double
    }

    public struct Lengths: Equatable, Sendable {
        public var average: TimeInterval
        public var longest: TimeInterval
        /// Under 15 min, 15–30, 30–60 and over an hour; a meeting of 15 min exactly is in 15–30.
        public var groups: [Count]
    }

    public struct SpeakerDetection: Equatable, Sendable {
        /// Meetings where it ran, and the median time it took.
        public var meetings: Int
        public var medianSeconds: Double
        /// Chunks of audio that weren't recognized, and in how many meetings.
        public var failedChunks: Int
        public var meetingsWithFailedChunks: Int
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

    /// Words per bucket start, oldest first (only buckets that have words): successful dictations and meetings
    /// (both streams) apart, for the stacked chart. A meeting counts in the bucket where it started.
    public static func wordsPerBucket(_ rows: [DictationRow], meetings: [MeetingRecord] = [], unit: Calendar.Component,
                                      calendar: Calendar = .current) -> [WordsBucket] {
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
        Dictionary(grouping: rows.filter(\.succeeded), by: \.engine).map { engine, group in
            EngineSpeed(engine: engine, medianWait: median(group.map(\.waitSeconds)),
                        medianWaitPer10s: median(group.filter { $0.audioSeconds > 0 }.map(per10s)))
        }.sorted { order($0.engine) < order($1.engine) }
    }

    /// Speed over time: the median wait per 10 s of audio per engine and model in each bucket, by engine, then oldest
    /// first. A bucket with fewer than 3 dictations of an engine is left out of its line, so one slow dictation draws
    /// no spike. Only the 4 engines and models used most in `rows` get a line, so the chart stays readable (statistics
    /// design §11); the speed table lists them all.
    public static func speedOverTime(_ rows: [DictationRow], unit: Calendar.Component, calendar: Calendar = .current) -> [SpeedPoint] {
        struct Key: Hashable { let engine: EngineChoice, start: Date }
        let timed = rows.filter { $0.succeeded && $0.audioSeconds > 0 }
        let uses = Dictionary(grouping: timed, by: \.engine).mapValues(\.count)
        let lines = Set(uses.keys.sorted { (-uses[$0, default: 0], order($0)) < (-uses[$1, default: 0], order($1)) }.prefix(4))
        var groups: [Key: [Double]] = [:]
        for row in timed where lines.contains(row.engine) {
            guard let start = calendar.dateInterval(of: unit, for: row.time)?.start else { continue }
            groups[Key(engine: row.engine, start: start), default: []].append(per10s(row))
        }
        return groups.compactMap { key, waits in
            waits.count < 3 ? nil : SpeedPoint(engine: key.engine, start: key.start, medianWaitPer10s: median(waits))
        }.sorted { (order($0.engine), $0.start) < (order($1.engine), $1.start) }
    }

    /// Engines in a fixed order: by engine, then model.
    private static func order(_ engine: EngineChoice) -> String { "\(engine.engine.rawValue)\t\(engine.model)" }

    private static func per10s(_ row: DictationRow) -> Double { row.waitSeconds / row.audioSeconds * 10 }

    /// The languages successful dictations were recognized in, most used first, as codes. With Ukrainian or English
    /// chosen the engines report that language; Auto-detect reports what it found in the order spoken, so "en+uk" counts
    /// as "uk+en" (the settings' order).
    public static func languages(_ rows: [DictationRow]) -> [Count] {
        let known = Settings.languages.map(\.value)
        func key(_ code: String) -> String {
            code.split(separator: "+").map(String.init)
                .sorted { (known.firstIndex(of: $0) ?? known.count, $0) < (known.firstIndex(of: $1) ?? known.count, $1) }
                .joined(separator: "+")
        }
        return mostFirst(Dictionary(grouping: rows.filter(\.succeeded).compactMap(\.languageDetected), by: key).mapValues(\.count))
    }

    /// Apps by number of successful dictations: the top `limit`, the rest as "Other".
    public static func topApps(_ rows: [DictationRow], limit: Int = 8) -> [Count] {
        let sorted = mostFirst(Dictionary(grouping: rows.filter(\.succeeded)) { $0.appName ?? "Unknown" }.mapValues(\.count))
        let rest = sorted.dropFirst(limit).reduce(0) { $0 + $1.count }
        return sorted.prefix(limit) + (rest > 0 ? [Count(name: "Other", count: rest)] : [])
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

    public static func failures(_ rows: [DictationRow]) -> Failures {
        func count(_ outcome: DictationOutcome) -> Int { rows.filter { $0.outcome == outcome }.count }
        return Failures(attempts: rows.count - count(.discarded), cancelled: count(.cancelled), failed: count(.failed), empty: count(.empty))
    }

    public static func fixes(_ rows: [DictationRow], topTerms limit: Int = 8) -> Fixes {
        let terms = mostFirst(Dictionary(grouping: rows.flatMap(\.replacedTerms)) { $0 }.mapValues(\.count))
        return Fixes(count: rows.reduce(0) { $0 + $1.replacements }, topTerms: Array(terms.prefix(limit)))
    }

    /// Meetings and hours per app in `CallApp`'s order, then the meetings Shepit couldn't tie to an app (all of those
    /// stored before 2026-11-17). Apps without meetings are left out.
    public static func meetingsByApp(_ meetings: [MeetingRecord]) -> [AppMeetings] {
        let groups = Dictionary(grouping: meetings, by: \.app)
        return (CallApp.allCases.map(Optional.some) + [nil]).compactMap { app in
            groups[app].map { AppMeetings(app: app, count: $0.count, hours: meetingHours($0)) }
        }
    }

    /// Your words ÷ all words of the meetings; nil when they have none.
    public static func yourShare(_ meetings: [MeetingRecord]) -> Double? {
        let mine = meetings.reduce(0) { $0 + $1.wordsMine }, all = meetings.reduce(0) { $0 + $1.wordsMine + $1.wordsCall }
        return all == 0 ? nil : Double(mine) / Double(all)
    }

    /// People in a meeting on average: the speakers speaker detection found, plus you. Meetings where it didn't run, or
    /// placed no line (0 speakers, though someone on the call spoke), are left out; nil when none is left.
    public static func peoplePerMeeting(_ meetings: [MeetingRecord]) -> Double? {
        let people = meetings.compactMap { $0.speakers.flatMap { $0 > 0 ? $0 + 1 : nil } }
        return people.isEmpty ? nil : Double(people.reduce(0, +)) / Double(people.count)
    }

    public static func lengths(_ meetings: [MeetingRecord]) -> Lengths {
        let edges: [TimeInterval] = [15 * 60, 30 * 60, 60 * 60]
        var counts = [0, 0, 0, 0]
        for meeting in meetings { counts[edges.filter { meeting.duration >= $0 }.count] += 1 } // the group is the edges passed
        let names = ["Under 15 min", "15–30 min", "30–60 min", "Over an hour"]
        return Lengths(average: meetings.isEmpty ? 0 : meetings.reduce(0) { $0 + $1.duration } / Double(meetings.count),
                       longest: meetings.map(\.duration).max() ?? 0, groups: zip(names, counts).map(Count.init))
    }

    public static func speakerDetection(_ meetings: [MeetingRecord]) -> SpeakerDetection {
        let times = meetings.compactMap(\.diarizationSeconds)
        return SpeakerDetection(meetings: times.count, medianSeconds: median(times), failedChunks: meetings.reduce(0) { $0 + $1.failedChunks },
                                meetingsWithFailedChunks: meetings.filter { $0.failedChunks > 0 }.count)
    }

    /// Call offers that ended with `outcome`, in `app` or in every app when nil.
    public static func offers(_ rows: [OfferRow], ending outcome: CallOffer.Outcome, in app: CallApp? = nil) -> Int {
        rows.filter { $0.outcome == outcome && (app == nil || $0.app == app) }.count
    }

    /// Most first, then by name.
    private static func mostFirst(_ counts: [String: Int]) -> [Count] {
        counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(Count.init)
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }
}

/// One call offer and how it ended (call offer design §5.7). No call name.
public struct OfferRow: Equatable, Sendable {
    public var time: Date
    public var app: CallApp
    public var outcome: CallOffer.Outcome

    public init(time: Date, app: CallApp, outcome: CallOffer.Outcome) {
        self.time = time
        self.app = app
        self.outcome = outcome
    }
}
