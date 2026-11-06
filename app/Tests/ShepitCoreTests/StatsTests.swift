import Foundation
import Testing
@testable import ShepitCore

func statsRow(
    _ time: String = "2026-10-20 10:00:00", outcome: DictationOutcome = .pasted, audio: Double = 10, wait: Double = 2,
    words: Int = 20, engine: String = "whispercpp", model: String = "large-v3-turbo", app: String? = "Slack",
    detected: String? = "uk", terms: [String] = [], tzOffset: Int = 3 * 3600
) -> DictationRow {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: tzOffset)
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return DictationRow(
        time: formatter.date(from: time)!, tzOffset: tzOffset, outcome: outcome, audioSeconds: audio, waitSeconds: wait,
        words: words, characters: words * 6, engine: engine, model: model, languageRequested: "uk", languageDetected: detected,
        appBundleID: app.map { "app.\($0)" }, appName: app, replacedTerms: terms, previewRequests: 3)
}

func meetingRow(_ time: String = "2026-10-20 10:00:00", duration: TimeInterval = 3600, mine: Int = 100, call: Int = 300,
                speakers: Int? = 2, diarization: Double? = 12.5, failed: Int = 1) -> MeetingRecord {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 3 * 3600)
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return MeetingRecord(start: formatter.date(from: time)!, duration: duration, wordsMine: mine, wordsCall: call, speakers: speakers,
                         engine: EngineChoice(engine: .whispercpp, model: "large-v3-turbo"), diarizationSeconds: diarization, failedChunks: failed)
}

struct StatsTests {
    private var kyiv: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 3 * 3600)!
        calendar.firstWeekday = 2
        return calendar
    }

    @Test func timeSavedFormula() {
        // 40 words at 40 wpm = 60 s of typing − (10 + 2) = 48 s; a negative saving counts as 0; failures count 0.
        let rows = [statsRow(words: 40), statsRow(audio: 30, wait: 5, words: 10), statsRow(outcome: .failed, words: 0),
                    statsRow(outcome: .copied, audio: 5, wait: 1, words: 20)]
        #expect(Stats.timeSaved(rows, wpm: 40) == 48 + 0 + 24)
    }

    @Test func dictationsAndWordsCountOnlyPastedAndCopied() {
        let rows = [statsRow(words: 5), statsRow(outcome: .copied, words: 7), statsRow(outcome: .empty, words: 0), statsRow(outcome: .cancelled)]
        #expect(Stats.dictations(rows) == 2)
        #expect(Stats.words(rows) == 12)
    }

    @Test func periodRangesAndPreviousPeriod() throws {
        let now = statsRow("2026-10-22 15:30:00").time
        let day = try #require(Stats.range(.day, now: now, calendar: kyiv))
        #expect(day.duration == 86_400)
        #expect(Stats.previous(day, .day, calendar: kyiv)?.end == day.start)
        // 31-day October: the previous period is exactly September, not "31 days back".
        let october = try #require(Stats.range(.month, now: now, calendar: kyiv))
        let september = try #require(Stats.previous(october, .month, calendar: kyiv))
        #expect(september.start == statsRow("2026-09-01 00:00:00").time && september.end == october.start)
        #expect(Stats.range(.all, now: now) == nil)
        let week = try #require(Stats.range(.week, now: now, calendar: kyiv))
        #expect(week.contains(now) && week.duration == 7 * 86_400)
    }

    @Test func deltaAgainstThePreviousPeriod() {
        #expect(Stats.delta(current: 15, previous: 10) == 0.5)
        #expect(Stats.delta(current: 3, previous: 0) == nil)
    }

    @Test func bucketsByPeriod() {
        #expect(Stats.bucketUnit(.day) == .hour)
        #expect(Stats.bucketUnit(.week) == .day && Stats.bucketUnit(.month) == .day)
        #expect(Stats.bucketUnit(.year) == .month && Stats.bucketUnit(.all) == .month)
        let rows = [statsRow("2026-10-20 10:05:00", words: 3), statsRow("2026-10-20 10:50:00", words: 4),
                    statsRow("2026-10-20 12:00:00", words: 5), statsRow("2026-10-20 12:10:00", outcome: .failed, words: 9)]
        #expect(Stats.wordsPerBucket(rows, period: .day, calendar: kyiv).map(\.dictation) == [7, 5])
        #expect(Stats.wordsPerBucket(rows, period: .week, calendar: kyiv).map(\.dictation) == [12])
    }

    @Test func meetingWordsStackOnDictationWordsInTheBucketWhereTheMeetingStarted() {
        let rows = [statsRow("2026-10-20 10:05:00", words: 3)]
        let meetings = [meetingRow("2026-10-20 10:30:00", mine: 100, call: 200), meetingRow("2026-10-20 14:00:00", mine: 10, call: 0),
                        meetingRow("2026-10-20 15:00:00", mine: 0, call: 0)]
        let day = Stats.wordsPerBucket(rows, meetings: meetings, period: .day, calendar: kyiv)
        #expect(day.map(\.dictation) == [3, 0])
        #expect(day.map(\.meetings) == [300, 10])
    }

    @Test func meetingCountAndHours() {
        let meetings = [meetingRow(duration: 1800), meetingRow(duration: 5400)]
        #expect(Stats.meetingCount(meetings) == 2)
        #expect(Stats.meetingHours(meetings) == 2)
        #expect(Stats.meetingHours([]) == 0)
    }

    @Test func medianWaitPerEngineAndPer10sOfAudio() {
        let rows = [statsRow(audio: 10, wait: 1), statsRow(audio: 20, wait: 3), statsRow(audio: 40, wait: 4),
                    statsRow(audio: 10, wait: 9, engine: "parakeet", model: "parakeet-tdt-0.6b-v3"),
                    statsRow(outcome: .failed, audio: 10, wait: 100)]
        #expect(Stats.speedByEngine(rows) == [
            .init(engine: "parakeet", model: "parakeet-tdt-0.6b-v3", medianWait: 9, medianWaitPer10s: 9),
            .init(engine: "whispercpp", model: "large-v3-turbo", medianWait: 3, medianWaitPer10s: 1),
        ])
    }

    @Test func topAppsWithOther() {
        var rows: [DictationRow] = []
        for (i, app) in ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J"].enumerated() {
            rows += Array(repeating: statsRow(app: app), count: 10 - i)
        }
        let top = Stats.topApps(rows)
        #expect(top.count == 9)
        #expect(top.first?.name == "A" && top.first?.count == 10)
        #expect(top.last?.name == "Other" && top.last?.count == 2 + 1)
    }

    @Test func heatmapHourWeekdayInTheDictationsOwnTimeZone() {
        // 2026-10-20 is a Tuesday; 10:00 in Kyiv (UTC+3) stays 10:00 whatever the test machine's zone is.
        let grid = Stats.heatmap([statsRow("2026-10-20 10:00:00"), statsRow("2026-10-20 10:30:00"), statsRow(outcome: .cancelled)])
        #expect(grid.count == 7 && grid[0].count == 24)
        #expect(grid[1][10] == 2)
        #expect(grid.joined().reduce(0, +) == 2)
    }

    @Test func qualitySignals() {
        let rows = [statsRow(terms: ["Kubernetes", "GitHub"]), statsRow(detected: "en", terms: ["Kubernetes"]),
                    statsRow(outcome: .cancelled, detected: nil), statsRow(outcome: .failed, detected: nil)]
        let q = Stats.quality(rows)
        #expect(q.cancelledShare == 0.25 && q.failedShare == 0.25 && q.emptyShare == 0)
        #expect(q.detectedLanguages == ["uk": 1, "en": 1])
        #expect(q.fixes == 3)
        #expect(q.topTerms.map(\.term) == ["Kubernetes", "GitHub"])
        #expect(q.topTerms.map(\.count) == [2, 1])
    }
}
