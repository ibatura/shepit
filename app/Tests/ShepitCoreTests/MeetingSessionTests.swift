import Foundation
import Testing
@testable import ShepitCore

// Spec §5.1–5.5, §5.10, §6, with fake audio, voice detection, recognition and speakers.

@MainActor
private final class FakeAudio: MeetingAudioSource {
    var startError: Error?
    var onStart: (() -> Void)?
    private(set) var started = false
    private(set) var stopped = false
    private var onSamples: (@Sendable ([Float], Int) -> Void)?
    private var onFailure: (@MainActor (String) -> Void)?
    private var index = 0

    func start(onSamples: @escaping @Sendable ([Float], Int) -> Void, onFailure: @escaping @MainActor (String) -> Void) throws -> String? {
        onStart?()
        if let startError { throw startError }
        started = true
        self.onSamples = onSamples
        self.onFailure = onFailure
        return nil
    }

    func stop() { stopped = true }

    func push(_ samples: [Float]) {
        onSamples?(samples, index)
        index += samples.count
    }

    func fail(_ message: String) { onFailure?(message) }
}

/// Loud frames are speech.
private struct FakeVAD: VoiceDetector {
    func probability(_ frame: [Float]) async throws -> Float { (frame.map(abs).max() ?? 0) > 0.1 ? 0.9 : 0.05 }
}

private struct Unrecognizable: Error {}

/// Tells the streams apart by loudness: 0.5 is "my" speech, 0.3 the call's, 0.2 a lone ".", 0.7 can't be recognized.
private let fakeTranscribe: @Sendable ([Float], String?) async throws -> Transcript = { samples, _ in
    let peak = samples.map(abs).max() ?? 0
    if peak > 0.6 { throw Unrecognizable() }
    let text = peak > 0.4 ? "мій текст" : peak > 0.25 ? "їхній текст" : "."
    return Transcript(text: text, segments: [Segment(text: text, start: 0, end: Double(samples.count) / 16_000)], detectedLanguage: nil)
}

private func seconds(_ s: Double, _ amplitude: Float = 0) -> [Float] {
    [Float](repeating: amplitude, count: Int(s * 16_000))
}

@MainActor
struct MeetingSessionTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        return calendar
    }()

    private final class Clock: @unchecked Sendable {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    private struct Rig {
        let session: MeetingSession
        let mic: FakeAudio
        let call: FakeAudio
        let config: MeetingConfig
        let clock: Clock
        let root: URL
        var notices: [String] = []
        var note: String { (try? String(contentsOf: config.noteFile, encoding: .utf8)) ?? "<missing>" }
        var body: String { MeetingNote.stripFrontMatter(note) }
    }

    private func rig(speakers: (@Sendable ([Float]) async throws -> [SpeakerTurn])? = { _ in [SpeakerTurn(speaker: "S3", start: 0, end: 1000)] },
                     change: (inout MeetingConfig) -> Void = { _ in }) -> Rig {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let start = calendar.date(from: DateComponents(year: 2026, month: 7, day: 31, hour: 18, minute: 22, second: 30))!
        var config = MeetingConfig(noteFile: root.appending(path: "notes/meeting.md"), frontMatter: "---\ntags: [transcript]\n---\n",
                                   myName: "Ivan Batura", sessionDir: root.appending(path: "tmp/meeting-1", directoryHint: .isDirectory),
                                   stateDir: root.appending(path: "state", directoryHint: .isDirectory),
                                   engine: EngineChoice(engine: .whispercpp, model: "large-v3-turbo"))
        config.frameSamples = 1600
        config.echoWindow = 0 // fake streams say different words; the hold is tested in MeetingQueueTests
        config.calendar = calendar
        change(&config)
        let clock = Clock(start)
        let mic = FakeAudio(), call = FakeAudio()
        let session = MeetingSession(config: config, mic: mic, call: call,
                                     services: MeetingServices(makeVAD: { FakeVAD() }, transcribe: fakeTranscribe, speakers: speakers),
                                     now: { clock.now })
        return Rig(session: session, mic: mic, call: call, config: config, clock: clock, root: root)
    }

    private func collectNotices(_ rig: inout Rig) -> () -> [String] {
        final class Box { var items: [String] = [] }
        let box = Box()
        rig.session.onNotice = { box.items.append($0) }
        return { box.items }
    }

    /// Mic: speech 0.5–1.5 s. Call: speech 2–3 s. Both: 4 s in total.
    private func talk(_ r: Rig) {
        r.mic.push(seconds(0.5) + seconds(1, 0.5) + seconds(2.5))
        r.call.push(seconds(2) + seconds(1, 0.3) + seconds(1))
    }

    @Test func theNoteExistsBeforeCaptureStarts() throws {
        let r = rig()
        defer { try? FileManager.default.removeItem(at: r.root) }
        var existed = false
        r.mic.onStart = { existed = FileManager.default.fileExists(atPath: r.config.noteFile.path) }
        try r.session.start()
        #expect(existed)
        #expect(r.note == r.config.frontMatter)
        #expect(r.session.state == .recording(elapsed: 0, waiting: 0))
    }

    @Test func aFolderThatCannotBeCreatedFailsStartWithThePath() throws {
        let r = rig(change: { $0.noteFile = URL(fileURLWithPath: "/dev/null/notes/meeting.md") })
        defer { try? FileManager.default.removeItem(at: r.root) }
        #expect { try r.session.start() } throws: { ($0 as? MeetingError)?.errorDescription?.contains("/dev/null/notes") == true }
        #expect(!r.mic.started && !r.call.started)
    }

    @Test func aCallTapThatCannotStartStopsTheMicAndLeavesNothing() throws {
        let r = rig()
        defer { try? FileManager.default.removeItem(at: r.root) }
        r.call.startError = MeetingError("denied")
        #expect { try r.session.start() } throws: { ($0 as? MeetingError)?.errorDescription?.contains("Screen & System Audio Recording") == true }
        #expect(r.mic.stopped)
        #expect(!FileManager.default.fileExists(atPath: r.config.noteFile.path))
        #expect(!FileManager.default.fileExists(atPath: r.config.sessionDir.path))
        #expect(!FileManager.default.fileExists(atPath: r.config.stateDir.appending(path: MeetingSession.activeMeetingFile).path))
    }

    @Test func bothStreamsReachTheNoteInTimeOrderWithLiveLabels() async throws {
        let r = rig(speakers: nil)
        defer { try? FileManager.default.removeItem(at: r.root) }
        try r.session.start()
        talk(r)
        await r.session.settle()
        #expect(r.body == "[Ivan Batura] 2026-07-31 18:22:30\nмій текст\n[Співрозмовники] 2026-07-31 18:22:31\nїхній текст\n")
        await r.session.stop()
        #expect(r.body == "[Ivan Batura] 2026-07-31 18:22:30\nмій текст\n[Співрозмовники] 2026-07-31 18:22:31\nїхній текст\n")
    }

    @Test func anEntryWaitsForTheOtherStreamsOpenPhrase() async throws {
        let r = rig(speakers: nil)
        defer { try? FileManager.default.removeItem(at: r.root) }
        try r.session.start()
        r.call.push(seconds(0.2) + seconds(3, 0.3)) // the call is still talking
        r.mic.push(seconds(1) + seconds(1, 0.5) + seconds(1))
        await r.session.settle()
        #expect(r.body.isEmpty) // my phrase started after the call's open phrase
        r.call.push(seconds(1))
        await r.session.settle()
        #expect(r.body == "[Співрозмовники] 2026-07-31 18:22:30\nїхній текст\n[Ivan Batura] 2026-07-31 18:22:30\nмій текст\n")
    }

    @Test func callAudioIsKeptOnlyUntilTheSessionEnds() async throws {
        let r = rig()
        defer { try? FileManager.default.removeItem(at: r.root) }
        try r.session.start()
        talk(r)
        await r.session.settle()
        #expect(try FileManager.default.contentsOfDirectory(atPath: r.config.sessionDir.path) == ["call.wav"])
        let size = try FileManager.default.attributesOfItem(atPath: r.config.sessionDir.appending(path: "call.wav").path)[.size] as? Int
        #expect(size == 44 + 4 * 16_000 * 2) // all call audio so far, as 16-bit
        let active = r.config.stateDir.appending(path: MeetingSession.activeMeetingFile)
        #expect(try String(contentsOf: active, encoding: .utf8) == r.config.noteFile.path + "\n")
        await r.session.stop()
        #expect(!FileManager.default.fileExists(atPath: r.config.sessionDir.path))
        #expect(!FileManager.default.fileExists(atPath: active.path))
        #expect(try String(contentsOf: r.config.stateDir.appending(path: MeetingSession.lastMeetingFile), encoding: .utf8)
            == r.config.noteFile.path + "\n")
    }

    @Test func anEmptyTranscriptIsRemovedAndTheEarlierLastMeetingComesBack() async throws {
        let r = rig()
        defer { try? FileManager.default.removeItem(at: r.root) }
        let last = r.config.stateDir.appending(path: MeetingSession.lastMeetingFile)
        try FileManager.default.createDirectory(at: r.config.stateDir, withIntermediateDirectories: true)
        try Data("/earlier.md\n".utf8).write(to: last)
        try r.session.start()
        #expect(!r.session.removeEmptyNote()) // still recording
        r.clock.now += 4
        await r.session.stop()
        #expect(r.session.entries == 0)
        #expect(r.session.removeEmptyNote())
        #expect(!FileManager.default.fileExists(atPath: r.config.noteFile.path))
        #expect(try String(contentsOf: last, encoding: .utf8) == "/earlier.md\n")
    }

    @Test func anEmptyFirstTranscriptLeavesNoLastMeeting() async throws {
        let r = rig()
        defer { try? FileManager.default.removeItem(at: r.root) }
        try r.session.start()
        await r.session.stop()
        #expect(r.session.removeEmptyNote())
        #expect(!FileManager.default.fileExists(atPath: r.config.stateDir.appending(path: MeetingSession.lastMeetingFile).path))
    }

    @Test func aTranscriptWithEntriesIsNotRemoved() async throws {
        let r = rig()
        defer { try? FileManager.default.removeItem(at: r.root) }
        try r.session.start()
        talk(r)
        r.clock.now += 4
        await r.session.stop()
        #expect(r.session.entries == 2)
        #expect(!r.session.removeEmptyNote())
        #expect(FileManager.default.fileExists(atPath: r.config.noteFile.path))
    }

    @Test func stopDetectsSpeakersRelabelsAndReportsTheMeeting() async throws {
        let r = rig()
        defer { try? FileManager.default.removeItem(at: r.root) }
        var record: MeetingRecord?
        r.session.onFinished = { record = $0 }
        var states: [MeetingState] = []
        r.session.onState = { states.append($0) }
        try r.session.start()
        talk(r)
        r.clock.now += 4
        await r.session.stop()
        #expect(r.body == "[Ivan Batura] 2026-07-31 18:22:30\nмій текст\n[Person 1] 2026-07-31 18:22:31\nїхній текст\n")
        #expect(r.session.state == .done(speakers: 1))
        #expect(states.contains(.detectingSpeakers))
        let got = try #require(record)
        #expect(got.wordsMine == 2 && got.wordsCall == 2 && got.speakers == 1 && got.failedChunks == 0)
        #expect(got.duration == 4)
        #expect(got.engine == r.config.engine)
        #expect(got.diarizationSeconds != nil)
    }

    @Test func failedSpeakerDetectionKeepsLiveLabelsAndStillDeletesAudio() async throws {
        var r = rig(speakers: { _ in throw MeetingError("model broke") })
        defer { try? FileManager.default.removeItem(at: r.root) }
        let notices = collectNotices(&r)
        try r.session.start()
        talk(r)
        await r.session.stop()
        #expect(r.body.contains("[Співрозмовники] 2026-07-31 18:22:31"))
        #expect(notices().contains("Speakers not detected: model broke"))
        #expect(!FileManager.default.fileExists(atPath: r.config.sessionDir.path))
        #expect(r.session.state == .done(speakers: nil))
    }

    @Test func missingSpeakerModelStillStartsWithANotice() throws {
        var r = rig(speakers: nil)
        defer { try? FileManager.default.removeItem(at: r.root) }
        let notices = collectNotices(&r)
        try r.session.start()
        #expect(notices() == ["Speakers won't be detected: download the speaker model in Settings → Meetings"])
    }

    @Test func dictationAudioIsLeftOutOfTheTranscript() async throws {
        let r = rig(speakers: nil)
        defer { try? FileManager.default.removeItem(at: r.root) }
        try r.session.start()
        r.session.dictationStarted(at: 8_000)
        r.mic.push(seconds(0.5) + seconds(1, 0.5))
        r.session.dictationEnded(at: 24_000)
        r.mic.push(seconds(2))
        r.call.push(seconds(3.5))
        await r.session.stop()
        #expect(r.body.isEmpty)
    }

    @Test func anEntryWithoutLettersOrDigitsIsLeftOut() async throws {
        let r = rig(speakers: nil)
        defer { try? FileManager.default.removeItem(at: r.root) }
        try r.session.start()
        r.call.push(seconds(0.5) + seconds(1, 0.2) + seconds(1) + seconds(1, 0.3) + seconds(1))
        r.mic.push(seconds(4.5))
        await r.session.stop()
        #expect(r.body == "[Співрозмовники] 2026-07-31 18:22:32\nїхній текст\n")
    }

    @Test func speechWhileMutedInTheCallAppIsLeftOut() async throws {
        let r = rig(speakers: nil)
        defer { try? FileManager.default.removeItem(at: r.root) }
        try r.session.start()
        r.session.micMuted(true, at: 0)
        r.mic.push(seconds(0.5) + seconds(1, 0.5))          // said while muted
        r.session.micMuted(true, at: 24_000)                 // repeated state: no change
        r.session.dictationStarted(at: 26_000)               // a dictation inside the muted time
        r.session.dictationEnded(at: 30_000)
        r.session.micMuted(false, at: 32_000)
        r.mic.push(seconds(0.5) + seconds(1, 0.5) + seconds(2))
        r.call.push(seconds(6))
        await r.session.stop()
        #expect(r.body == "[Ivan Batura] 2026-07-31 18:22:32\nмій текст\n")
    }

    @Test func aFailedChunkLeavesAVisibleGap() async throws {
        var r = rig(speakers: nil)
        defer { try? FileManager.default.removeItem(at: r.root) }
        var record: MeetingRecord?
        r.session.onFinished = { record = $0 }
        _ = collectNotices(&r)
        try r.session.start()
        r.call.push(seconds(1) + seconds(1, 0.7) + seconds(1))
        r.mic.push(seconds(3))
        await r.session.stop()
        #expect(r.body == "[Співрозмовники] 2026-07-31 18:22:30\n⚠ не вдалося розпізнати\n")
        #expect(record?.failedChunks == 1)
        #expect(record?.wordsCall == 0)
    }

    @Test func whenOneCaptureDiesTheOtherContinues() async throws {
        var r = rig(speakers: nil)
        defer { try? FileManager.default.removeItem(at: r.root) }
        let notices = collectNotices(&r)
        try r.session.start()
        r.clock.now += 1
        r.call.fail("call audio stopped: gone")
        await r.session.settle()
        r.mic.push(seconds(0.5) + seconds(1, 0.5) + seconds(1))
        await r.session.settle()
        #expect(r.body == "⚠ Звук дзвінка перестав записуватися о 18:22:31\n[Ivan Batura] 2026-07-31 18:22:30\nмій текст\n")
        #expect(notices().contains("call audio stopped: gone"))
        #expect(r.session.state != .done(speakers: nil))
    }

    @Test func whenBothCapturesDieTheSessionEnds() async throws {
        let r = rig(speakers: nil)
        defer { try? FileManager.default.removeItem(at: r.root) }
        try r.session.start()
        r.call.fail("x")
        r.mic.fail("y")
        await r.session.settle()
        for _ in 0..<20 where r.session.state != .done(speakers: nil) { await Task.yield() }
        await r.session.settle()
        #expect(r.session.state == .done(speakers: nil))
    }

    @Test func stopsAfterThirtyMinutesWithoutSpeechAndAfterFourHours() async throws {
        for (advance, expected, silence) in [(30.0 * 60, "no speech for 30 minutes", 30.0 * 60), (4.0 * 3600, "after 4 hours", 5.0 * 3600)] {
            var r = rig(speakers: nil, change: { $0.maxSilence = silence })
            defer { try? FileManager.default.removeItem(at: r.root) }
            let notices = collectNotices(&r)
            try r.session.start()
            r.clock.now += advance - 1
            r.session.tick()
            #expect(notices().count == 1) // only the start notice
            r.clock.now += 1
            r.session.tick()
            for _ in 0..<50 where r.session.state != .done(speakers: nil) { await Task.yield() }
            #expect(notices().contains { $0.contains(expected) }, "\(notices())")
            #expect(r.session.state == .done(speakers: nil))
        }
    }

    @Test func silentCallWithASpeakingMicGivesOneNotice() async throws {
        var r = rig(speakers: nil, change: { $0.silentCallAfter = 1 })
        defer { try? FileManager.default.removeItem(at: r.root) }
        let notices = collectNotices(&r)
        try r.session.start()
        r.call.push(seconds(4))
        r.mic.push(seconds(0.2) + seconds(1.5, 0.5) + seconds(1))
        await r.session.settle()
        r.session.tick()
        r.session.tick()
        #expect(notices().filter { $0.hasPrefix("Call audio may not be recorded") }.count == 1)
    }

    @Test func aCallWithSoundGivesNoSilentCallNotice() async throws {
        var r = rig(speakers: nil, change: { $0.silentCallAfter = 1 })
        defer { try? FileManager.default.removeItem(at: r.root) }
        let notices = collectNotices(&r)
        try r.session.start()
        r.call.push(seconds(4) + [0.01])
        r.mic.push(seconds(0.2) + seconds(1.5, 0.5) + seconds(1))
        await r.session.settle()
        r.session.tick()
        #expect(!notices().contains { $0.hasPrefix("Call audio may not be recorded") })
    }

    @Test func interruptMarksTheNoteAndDeletesTheAudio() async throws {
        let r = rig()
        defer { try? FileManager.default.removeItem(at: r.root) }
        try r.session.start()
        talk(r)
        await r.session.settle()
        r.clock.now += 65
        r.session.interrupt()
        #expect(r.body.hasSuffix("⚠ Запис перервано о 18:23:35\n"))
        #expect(r.mic.stopped && r.call.stopped)
        #expect(!FileManager.default.fileExists(atPath: r.config.sessionDir.path))
        #expect(!FileManager.default.fileExists(atPath: r.config.stateDir.appending(path: MeetingSession.activeMeetingFile).path))
        #expect(r.session.state == .interrupted)
    }

    @Test func recoveryAfterACrashMarksTheNoteAndDeletesLeftoverAudio() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = root.appending(path: "state"), sessions = root.appending(path: "tmp"), note = root.appending(path: "n.md")
        for dir in [state, sessions.appending(path: "meeting-old"), sessions.appending(path: "other")] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try Data("---\n---\n[A] t\nx\n".utf8).write(to: note)
        try Data((note.path + "\n").utf8).write(to: state.appending(path: MeetingSession.activeMeetingFile))
        let at = calendar.date(from: DateComponents(year: 2026, month: 7, day: 31, hour: 9, minute: 1, second: 2))!
        #expect(MeetingSession.recover(stateDir: state, sessionsRoot: sessions, now: at, calendar: calendar) == note)
        #expect(try String(contentsOf: note, encoding: .utf8) == "---\n---\n[A] t\nx\n⚠ Запис перервано о 09:01:02\n")
        #expect(try FileManager.default.contentsOfDirectory(atPath: sessions.path) == ["other"])
        #expect(!FileManager.default.fileExists(atPath: state.appending(path: MeetingSession.activeMeetingFile).path))
        #expect(MeetingSession.recover(stateDir: state, sessionsRoot: sessions, now: at, calendar: calendar) == nil)
    }

    @Test func aMicThatCannotStartLeavesNoNoteAndNoStateFiles() throws {
        let r = rig()
        defer { try? FileManager.default.removeItem(at: r.root) }
        r.mic.startError = MeetingError("no microphone access")
        #expect(throws: MeetingError("no microphone access")) { try r.session.start() }
        #expect(!r.call.started)
        #expect(!FileManager.default.fileExists(atPath: r.config.noteFile.path))
        for name in [MeetingSession.activeMeetingFile, MeetingSession.lastMeetingFile] {
            #expect(!FileManager.default.fileExists(atPath: r.config.stateDir.appending(path: name).path), "\(name)")
        }
    }

    @Test func entriesWaitFromTheStartUntilTheOtherStreamHasAudio() async throws {
        let r = rig(speakers: nil)
        defer { try? FileManager.default.removeItem(at: r.root) }
        try r.session.start()
        r.mic.push(seconds(0.5) + seconds(1, 0.5) + seconds(1)) // the call has delivered nothing yet
        await r.session.settle()
        #expect(r.body.isEmpty)
        r.call.push(seconds(3))
        await r.session.settle()
        #expect(r.body == "[Ivan Batura] 2026-07-31 18:22:30\nмій текст\n")
    }

    @Test func aStreamThatGoesQuietWithoutAnErrorStopsHoldingTheOtherBack() async throws {
        let r = rig(speakers: nil)
        defer { try? FileManager.default.removeItem(at: r.root) }
        try r.session.start()
        r.mic.push(seconds(0.5) + seconds(1, 0.5) + seconds(1))
        await r.session.settle()
        r.clock.now += 10
        r.session.tick()
        #expect(r.body.isEmpty)
        r.clock.now += 2
        r.session.tick()
        #expect(r.body == "[Ivan Batura] 2026-07-31 18:22:30\nмій текст\n")
    }

    @Test func stopRightAfterBothCapturesDieLosesNothing() async throws {
        let r = rig(speakers: nil)
        defer { try? FileManager.default.removeItem(at: r.root) }
        try r.session.start()
        r.mic.push(seconds(0.5) + seconds(1, 0.5)) // phrase still open
        r.call.push(seconds(1.5))
        r.call.fail("x")
        r.mic.fail("y")
        await r.session.stop()
        await r.session.settle()
        #expect(r.body.contains("[Ivan Batura] 2026-07-31 18:22:30\nмій текст\n"))
        #expect(r.session.state == .done(speakers: nil))
    }

    @Test func interruptWritesHeldEntriesBeforeTheMarkerAndNothingAfter() async throws {
        let r = rig(speakers: nil)
        defer { try? FileManager.default.removeItem(at: r.root) }
        try r.session.start()
        r.call.push(seconds(0.2) + seconds(3, 0.3)) // the call's phrase is still open
        r.mic.push(seconds(1) + seconds(1, 0.5) + seconds(1))
        await r.session.settle()
        #expect(r.body.isEmpty)
        r.session.interrupt()
        await r.session.stop()
        await r.session.settle()
        #expect(r.body == "[Ivan Batura] 2026-07-31 18:22:30\nмій текст\n⚠ Запис перервано о 18:22:30\n")
        #expect(r.session.state == .interrupted)
    }

    @Test func receiveFillsGapsAndDropsOverlaps() async throws {
        let r = rig(speakers: nil)
        defer { try? FileManager.default.removeItem(at: r.root) }
        try r.session.start()
        r.call.push(seconds(3))
        await r.session.settle()
        let wav = r.config.sessionDir.appending(path: "call.wav")
        func size() throws -> Int { try FileManager.default.attributesOfItem(atPath: wav.path)[.size] as! Int }
        #expect(try size() == 44 + 3 * 32_000)
        r.call.push([]) // nothing
        await r.session.settle()
        #expect(try size() == 44 + 3 * 32_000)
    }
}
