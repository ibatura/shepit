import Foundation
import Testing
@testable import ShepitCore

func statsRow(
    _ time: String = "2026-10-20 10:00:00", outcome: DictationOutcome = .pasted, audio: Double = 10, wait: Double = 2,
    words: Int = 20, engine: EngineID = .whispercpp, model: String = "large-v3-turbo", app: String? = "Slack",
    detected: String? = "uk", terms: [String] = [], tzOffset: Int = 3 * 3600
) -> DictationRow {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: tzOffset)
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return DictationRow(
        time: formatter.date(from: time)!, tzOffset: tzOffset, outcome: outcome, audioSeconds: audio, waitSeconds: wait,
        words: words, characters: words * 6, engine: EngineChoice(engine: engine, model: model), languageRequested: "uk", languageDetected: detected,
        appBundleID: app.map { "app.\($0)" }, appName: app, replacedTerms: terms, previewRequests: 3)
}

func meetingRow(_ time: String = "2026-10-20 10:00:00", duration: TimeInterval = 3600, mine: Int = 100, call: Int = 300,
                speakers: Int? = 2, diarization: Double? = 12.5, failed: Int = 1, app: CallApp? = nil) -> MeetingRecord {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 3 * 3600)
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return MeetingRecord(start: formatter.date(from: time)!, duration: duration, wordsMine: mine, wordsCall: call, speakers: speakers,
                         engine: EngineChoice(engine: .whispercpp, model: "large-v3-turbo"), diarizationSeconds: diarization, failedChunks: failed,
                         app: app)
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

    @Test func deltaAgainstThePreviousPeriod() {
        #expect(Stats.delta(current: 15, previous: 10) == 0.5)
        #expect(Stats.delta(current: 3, previous: 0) == nil)
    }

    @Test func wordsPerBucket() {
        let rows = [statsRow("2026-10-20 10:05:00", words: 3), statsRow("2026-10-20 10:50:00", words: 4),
                    statsRow("2026-10-20 12:00:00", words: 5), statsRow("2026-10-20 12:10:00", outcome: .failed, words: 9)]
        #expect(Stats.wordsPerBucket(rows, unit: .hour, calendar: kyiv).map(\.dictation) == [7, 5])
        #expect(Stats.wordsPerBucket(rows, unit: .day, calendar: kyiv).map(\.dictation) == [12])
    }

    @Test func meetingWordsStackOnDictationWordsInTheBucketWhereTheMeetingStarted() {
        let rows = [statsRow("2026-10-20 10:05:00", words: 3)]
        let meetings = [meetingRow("2026-10-20 10:30:00", mine: 100, call: 200), meetingRow("2026-10-20 14:00:00", mine: 10, call: 0),
                        meetingRow("2026-10-20 15:00:00", mine: 0, call: 0)]
        let day = Stats.wordsPerBucket(rows, meetings: meetings, unit: .hour, calendar: kyiv)
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
                    statsRow(audio: 10, wait: 9, engine: .parakeet, model: "parakeet-tdt-0.6b-v3"),
                    statsRow(outcome: .failed, audio: 10, wait: 100)]
        #expect(Stats.speedByEngine(rows) == [
            .init(engine: EngineChoice(engine: .parakeet, model: "parakeet-tdt-0.6b-v3"), medianWait: 9, medianWaitPer10s: 9),
            .init(engine: EngineChoice(engine: .whispercpp, model: "large-v3-turbo"), medianWait: 3, medianWaitPer10s: 1),
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
                    statsRow(outcome: .cancelled, detected: nil), statsRow(outcome: .failed, detected: nil),
                    statsRow(outcome: .discarded, detected: nil)]
        let failures = Stats.failures(rows) // a tap too short to record isn't an attempt
        #expect(failures == .init(attempts: 4, cancelled: 1, failed: 1, empty: 0))
        #expect(failures.share(failures.cancelled) == 0.25 && failures.share(failures.empty) == 0)
        #expect(Stats.failures([]).share(0) == 0)
        #expect(Stats.fixes(rows) == .init(count: 3, topTerms: [.init(name: "Kubernetes", count: 2), .init(name: "GitHub", count: 1)]))
    }

    // Statistics design §5.2–5.3: the new numbers.

    private func day(_ day: Int) -> Date { kyiv.date(from: DateComponents(year: 2026, month: 10, day: day))! }

    @Test func languagesOfSuccessfulDictationsMostUsedFirst() {
        let rows = [statsRow(detected: "uk"), statsRow(detected: "uk"), statsRow(detected: "uk"), statsRow(detected: "en"),
                    statsRow(detected: "uk+en"), statsRow(detected: "en+uk"), statsRow(detected: "pl+en"), statsRow(detected: nil),
                    statsRow(outcome: .failed, detected: "uk")]
        let languages = Stats.languages(rows)
        #expect(languages.map(\.name) == ["uk", "uk+en", "en", "en+pl"])
        #expect(languages.map(\.count) == [3, 2, 1, 1])
        #expect(Stats.languages([statsRow(detected: nil)]).isEmpty)
    }

    @Test func speedOverTimeLeavesOutBucketsWithFewerThanThreeDictationsOfAnEngine() {
        let parakeet = (1...3).map { statsRow("2026-10-21 0\($0):00:00", audio: 10, wait: 5, engine: .parakeet, model: "v3") }
        let rows = [
            // 20 Oct: 1, 2 and 3 s per 10 s of audio; the one with no audio is left out.
            statsRow("2026-10-20 09:00:00", audio: 10, wait: 1), statsRow("2026-10-20 10:00:00", audio: 20, wait: 4),
            statsRow("2026-10-20 11:00:00", audio: 10, wait: 3), statsRow("2026-10-20 12:00:00", audio: 0, wait: 50),
            // 21 Oct: two whisper.cpp dictations and a failed one, too few for a point.
            statsRow("2026-10-21 09:00:00"), statsRow("2026-10-21 10:00:00"), statsRow("2026-10-21 11:00:00", outcome: .failed),
        ] + parakeet
        #expect(Stats.speedOverTime(rows, unit: .day, calendar: kyiv) == [
            .init(engine: EngineChoice(engine: .parakeet, model: "v3"), start: day(21), medianWaitPer10s: 5),
            .init(engine: EngineChoice(engine: .whispercpp, model: "large-v3-turbo"), start: day(20), medianWaitPer10s: 2),
        ])
    }

    @Test func speedOverTimeDrawsTheFourMostUsedEnginesOnly() {
        // Five models with 7, 6, 5, 4 and 3 dictations on one day; the least used one is left out.
        let rows = (3...7).flatMap { count in (0..<count).map { _ in statsRow("2026-10-20 09:00:00", model: "m\(count)") } }
        #expect(Stats.speedOverTime(rows, unit: .day, calendar: kyiv).map(\.engine.model) == ["m4", "m5", "m6", "m7"])
    }

    @Test func meetingsByAppInAFixedOrderWithUnknownLast() {
        let apps = Stats.meetingsByApp([meetingRow(duration: 1800, app: .meet), meetingRow(duration: 3600),
                                        meetingRow(duration: 1800, app: .teams), meetingRow(duration: 5400, app: .teams)])
        #expect(apps.map(\.app) == [.teams, .meet, nil])
        #expect(apps.map(\.count) == [2, 1, 1])
        #expect(apps.map(\.hours) == [2, 0.5, 1])
        #expect(Stats.meetingsByApp([]).isEmpty)
    }

    @Test func yourShareOfTheMeetingsWords() {
        #expect(Stats.yourShare([meetingRow(mine: 100, call: 300), meetingRow(mine: 100, call: 0)]) == 0.4)
        #expect(Stats.yourShare([meetingRow(mine: 0, call: 0)]) == nil)
    }

    @Test func peoplePerMeetingCountsYouAndLeavesOutMeetingsWithoutSpeakers() {
        // 2 + you, 4 + you; detection that didn't run or placed no line is left out.
        #expect(Stats.peoplePerMeeting([meetingRow(speakers: 2), meetingRow(speakers: 4), meetingRow(speakers: 0),
                                        meetingRow(speakers: nil)]) == 4)
        #expect(Stats.peoplePerMeeting([meetingRow(speakers: nil), meetingRow(speakers: 0)]) == nil)
    }

    @Test func meetingLengthsWithAnEdgeInTheLongerGroup() {
        let lengths = Stats.lengths([14.5, 15, 20, 30, 45, 60, 95.5].map { meetingRow(duration: $0 * 60) })
        #expect(lengths.groups.map(\.name) == ["Under 15 min", "15–30 min", "30–60 min", "Over an hour"])
        #expect(lengths.groups.map(\.count) == [1, 2, 2, 2])
        #expect(lengths.average == 40 * 60)
        #expect(lengths.longest == 95.5 * 60)
        let none = Stats.lengths([])
        #expect(none.average == 0 && none.longest == 0 && none.groups.map(\.count) == [0, 0, 0, 0])
    }

    @Test func speakerDetectionTimesAndFailedChunks() {
        let meetings = [meetingRow(diarization: 10, failed: 0), meetingRow(diarization: 30, failed: 2),
                        meetingRow(diarization: 20, failed: 0), meetingRow(diarization: nil, failed: 3)]
        #expect(Stats.speakerDetection(meetings) == .init(meetings: 3, medianSeconds: 20, failedChunks: 5, meetingsWithFailedChunks: 2))
        #expect(Stats.speakerDetection([]) == .init(meetings: 0, medianSeconds: 0, failedChunks: 0, meetingsWithFailedChunks: 0))
    }

    @Test func offersByOutcomeInTotalAndPerApp() {
        let rows = [(CallApp.teams, CallOffer.Outcome.started), (.teams, .dismissed), (.teams, .started), (.meet, .hidden),
                    (.zoom, .startedAutomatically)].map { OfferRow(time: day(20), app: $0.0, outcome: $0.1) }
        #expect(Stats.offers(rows, ending: .started) == 2)
        #expect(Stats.offers(rows, ending: .started, in: .teams) == 2)
        #expect(Stats.offers(rows, ending: .started, in: .meet) == 0)
        #expect(Stats.offers(rows, ending: .hidden, in: .meet) == 1)
        #expect(Stats.offers(rows, ending: .startedAutomatically) == 1)
        #expect(Stats.offers(rows, ending: .dismissed, in: .zoom) == 0)
    }
}
