import Foundation
import Testing
@testable import ShepitCore

private struct Boom: Error, CustomStringConvertible {
    let description: String
}

private final class FakeTimer: TimerToken {
    let at: Date
    let action: @MainActor () -> Void
    var stopped = false
    var fired = false

    init(at: Date, action: @escaping @MainActor () -> Void) {
        self.at = at
        self.action = action
    }

    func cancel() { stopped = true }
}

/// Port of the Lua test harness: records every effect, drives time and the engine by hand.
@MainActor
private final class FakeHost: ControllerHost {
    var mode = "toggle"
    var maxRecordingSeconds = 300.0
    var dictationBlocked: String?
    var clock = Date(timeIntervalSince1970: 0)
    var log: [String] = []
    var states: [ControllerState] = []
    var notes: [String] = []
    var pasted: [(String, AppRef?)] = []
    var overlayEvents: [String] = []
    var records: [DictationRecord] = []
    var startError: String?
    var pasteOutcome = PasteOutcome.pasted
    var timers: [FakeTimer] = []
    private var pending: [CheckedContinuation<Transcript, any Error>] = []
    private(set) var transcribeCalls = 0

    func now() -> Date { clock }

    func after(_ seconds: Double, _ action: @escaping @MainActor () -> Void) -> any TimerToken {
        let timer = FakeTimer(at: clock.addingTimeInterval(seconds), action: action)
        timers.append(timer)
        return timer
    }

    func advance(_ seconds: Double) {
        clock = clock.addingTimeInterval(seconds)
        for timer in timers where !timer.stopped && !timer.fired && timer.at <= clock {
            timer.fired = true
            timer.action()
        }
    }

    func frontApp() -> AppRef? { AppRef(bundleID: "com.tinyspeck.slackmacgap", name: "Slack") }

    func startRecording() throws {
        log.append("rec.start")
        if let startError { throw Boom(description: startError) }
    }

    func stopRecording() -> [Float] {
        log.append("rec.stop")
        return [Float](repeating: 0, count: 16_000)
    }

    func cancelRecording() { log.append("rec.cancel") }

    func transcribe(_ samples: [Float]) async throws -> Transcript {
        transcribeCalls += 1
        log.append("transcribe")
        return try await withCheckedThrowingContinuation { pending.append($0) }
    }

    /// Waits until the controller asks for the `n`th recognition, then answers it.
    func answer(_ n: Int, with result: Result<String, Boom>) async throws {
        for _ in 0..<400 where transcribeCalls < n {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(transcribeCalls >= n && !pending.isEmpty)
        let continuation = pending.removeFirst()
        switch result {
        case .success(let text): continuation.resume(returning: Transcript(text: text, segments: [], detectedLanguage: "uk"))
        case .failure(let error): continuation.resume(throwing: error)
        }
    }

    func process(_ text: String) -> (text: String, fired: [String]) {
        (text.trimmingCharacters(in: .whitespaces), text.contains("кубер") ? ["Kubernetes"] : [])
    }

    func appendHistory(_ text: String) { log.append("history \(text)") }

    func paste(_ text: String, into app: AppRef?) async -> PasteOutcome {
        log.append("paste \(text)")
        pasted.append((text, app))
        return pasteOutcome
    }

    func keepFailed(_ samples: [Float]) -> URL? {
        log.append("keep")
        return URL(fileURLWithPath: "/failed/a.wav")
    }

    func setState(_ state: ControllerState) { states.append(state) }
    func notify(_ message: String) { notes.append(message) }
    func sound(_ sound: Sound) { log.append("sound \(sound)") }
    func bindCancel(_ on: Bool) { log.append("cancel \(on)") }

    func overlay(_ event: OverlayEvent) {
        switch event {
        case .recording(let date): overlayEvents.append("recording \(Int(date.timeIntervalSince1970))")
        case .transcribing: overlayEvents.append("transcribing")
        case .done(let text): overlayEvents.append("done \(text)")
        case .message(let text): overlayEvents.append("message \(text)")
        case .hide: overlayEvents.append("hide")
        }
    }

    func recordingStarted() { overlayEvents.append("start") }
    func recordingEnded() { overlayEvents.append("stop") }
    func record(_ dictation: DictationRecord) { records.append(dictation) }

    func has(_ entry: String) -> Bool { log.contains(entry) }
}

// Ported from tests/test_controller.lua (the "waits for the recorder to finalize the file" case is
// dropped: native recording is in memory, so stop is synchronous).
@MainActor
struct ControllerTests {
    private func make() -> (Controller, FakeHost) {
        let host = FakeHost()
        return (Controller(host: host), host)
    }

    private func dictate(_ ctl: Controller, _ host: FakeHost, seconds: Double = 1) {
        ctl.hotkeyDown()
        host.advance(seconds)
        ctl.hotkeyDown()
    }

    @Test func toggleStartStopTranscribePaste() async throws {
        let (ctl, host) = make()
        ctl.hotkeyDown()
        #expect(ctl.state == .recording)
        #expect(host.has("rec.start") && host.has("sound start") && host.has("cancel true"))
        host.advance(2)
        ctl.hotkeyDown()
        #expect(ctl.state == .transcribing)
        #expect(host.has("rec.stop") && host.has("cancel false"))
        try await host.answer(1, with: .success("  Привіт  "))
        await ctl.transcription?.value
        #expect(ctl.state == .idle)
        #expect(host.pasted.map(\.0) == ["Привіт"] && host.pasted.first?.1?.name == "Slack")
        #expect(host.has("history Привіт") && host.has("sound done"))
        #expect(host.states == [.recording, .transcribing, .idle])
    }

    @Test func blockedDictationDoesNotStartAndSaysWhy() {
        for mode in ["toggle", "hold"] {
            let host = FakeHost()
            host.mode = mode
            host.dictationBlocked = "Dictation is off while a meeting is recording"
            let controller = Controller(host: host)
            controller.hotkeyDown()
            controller.hotkeyUp()
            #expect(controller.state == .idle)
            #expect(host.notes == ["Dictation is off while a meeting is recording"])
            #expect(!host.log.contains("rec.start"))
        }
    }

    @Test func toggleHotkeyUpIsIgnored() {
        let (ctl, host) = make()
        ctl.hotkeyDown()
        host.advance(2)
        ctl.hotkeyUp()
        #expect(ctl.state == .recording)
    }

    @Test func holdStartOnDownStopOnUp() {
        let (ctl, host) = make()
        host.mode = "hold"
        ctl.hotkeyDown()
        host.advance(1)
        ctl.hotkeyUp()
        #expect(ctl.state == .transcribing)
    }

    @Test func holdKeyRepeatWhileRecordingDoesNotRestartOrStop() {
        let (ctl, host) = make()
        host.mode = "hold"
        ctl.hotkeyDown()
        host.advance(0.5)
        ctl.hotkeyDown()
        ctl.hotkeyDown()
        #expect(ctl.state == .recording)
        #expect(host.log.filter { $0 == "rec.start" }.count == 1)
    }

    @Test func holdTapShorterThanHoldMinIsDiscardedSilently() {
        let (ctl, host) = make()
        host.mode = "hold"
        ctl.hotkeyDown()
        host.advance(0.2)
        ctl.hotkeyUp()
        #expect(ctl.state == .idle)
        #expect(host.has("rec.cancel"))
        #expect(host.notes.isEmpty)
        #expect(host.transcribeCalls == 0)
    }

    @Test func recordingShorterThanMinSecondsIsDiscardedWithANotice() {
        let (ctl, host) = make()
        dictate(ctl, host, seconds: 0.4)
        #expect(ctl.state == .idle)
        #expect(host.has("rec.cancel"))
        #expect(host.notes == ["Recording too short"])
    }

    @Test func modeChangeMidRecordingAppliesToTheNextRecordingOnly() {
        let (ctl, host) = make()
        ctl.hotkeyDown()
        host.mode = "hold"
        host.advance(1)
        ctl.hotkeyUp()
        #expect(ctl.state == .recording)
        ctl.hotkeyDown()
        #expect(ctl.state == .transcribing)
    }

    @Test func pressesWhileTranscribingAreIgnored() {
        let (ctl, host) = make()
        dictate(ctl, host)
        ctl.hotkeyDown()
        ctl.hotkeyUp()
        ctl.cancel()
        #expect(ctl.state == .transcribing)
    }

    @Test func cancelDiscardsTheRecording() {
        let (ctl, host) = make()
        ctl.hotkeyDown()
        host.advance(3)
        ctl.cancel()
        #expect(ctl.state == .idle)
        #expect(host.has("rec.cancel") && host.has("cancel false"))
        #expect(host.notes == ["Cancelled"])
        #expect(host.transcribeCalls == 0)
    }

    @Test func cancelInIdleDoesNothing() {
        let (ctl, host) = make()
        ctl.cancel()
        #expect(ctl.state == .idle)
        #expect(host.notes.isEmpty)
    }

    @Test func autoStopAtMaxRecordingSecondsTranscribes() async throws {
        let (ctl, host) = make()
        host.maxRecordingSeconds = 10
        ctl.hotkeyDown()
        host.advance(10)
        #expect(ctl.state == .transcribing)
        try await host.answer(1, with: .success("ok"))
        await ctl.transcription?.value
    }

    @Test func autoStopTimerIsCancelledWhenStoppedManually() async throws {
        let (ctl, host) = make()
        host.maxRecordingSeconds = 10
        dictate(ctl, host, seconds: 2)
        try await host.answer(1, with: .success("ok"))
        await ctl.transcription?.value
        ctl.hotkeyDown() // second recording starts at t=2
        host.advance(9)  // first auto-stop would fire at t=10
        #expect(ctl.state == .recording)
        #expect(host.timers.first?.stopped == true)
    }

    @Test func emptyResultNoticeNoPaste() async throws {
        let (ctl, host) = make()
        dictate(ctl, host)
        try await host.answer(1, with: .success("   "))
        await ctl.transcription?.value
        #expect(ctl.state == .idle)
        #expect(host.pasted.isEmpty)
        #expect(host.notes == ["Nothing recognized"])
    }

    @Test func transcriptionErrorRetriesOnceThenKeepsFailedAudio() async throws {
        let (ctl, host) = make()
        dictate(ctl, host)
        try await host.answer(1, with: .failure(Boom(description: "engine crashed")))
        try await host.answer(2, with: .failure(Boom(description: "server unreachable")))
        await ctl.transcription?.value
        #expect(ctl.state == .idle)
        #expect(host.transcribeCalls == 2)
        #expect(host.notes == ["Transcription failed: server unreachable — audio kept in /failed/a.wav"])
        #expect(host.has("keep") && host.has("sound error"))
    }

    @Test func retrySucceedsAfterOneFailure() async throws {
        let (ctl, host) = make()
        dictate(ctl, host)
        try await host.answer(1, with: .failure(Boom(description: "once")))
        try await host.answer(2, with: .success("Привіт"))
        await ctl.transcription?.value
        #expect(host.pasted.map(\.0) == ["Привіт"])
        #expect(!host.has("keep"))
    }

    @Test func watchdogTimeoutReturnsToIdleAndLateResultIsIgnored() async throws {
        let (ctl, host) = make()
        dictate(ctl, host)
        host.advance(Controller.transcribeTimeout)
        #expect(ctl.state == .idle)
        #expect(host.notes == ["Transcription timed out — audio kept in /failed/a.wav"])
        #expect(host.has("keep"))
        try await host.answer(1, with: .success("late text"))
        await ctl.transcription?.value
        #expect(host.pasted.isEmpty)
        #expect(ctl.state == .idle)
    }

    @Test func lateResultFromAnOldSessionDoesNotAffectANewRecording() async throws {
        let (ctl, host) = make()
        dictate(ctl, host)
        let old = ctl.transcription
        host.advance(Controller.transcribeTimeout)
        ctl.hotkeyDown()
        try await host.answer(1, with: .success("late text"))
        await old?.value
        #expect(ctl.state == .recording)
        #expect(host.pasted.isEmpty)
    }

    @Test func noRetryAfterTimeout() async throws {
        let (ctl, host) = make()
        dictate(ctl, host)
        host.advance(Controller.transcribeTimeout)
        try await host.answer(1, with: .failure(Boom(description: "late failure")))
        await ctl.transcription?.value
        #expect(host.transcribeCalls == 1)
        #expect(host.records.map(\.outcome) == [.failed])
    }

    @Test func recorderStartFailureNoticeAndStayIdle() {
        let (ctl, host) = make()
        host.startError = "no input device"
        ctl.hotkeyDown()
        #expect(ctl.state == .idle)
        #expect(host.notes == ["Recording failed: no input device"])
        #expect(!host.has("cancel true"))
    }

    @Test func recorderFailingWhileRecordingNoticeAndIdle() {
        let (ctl, host) = make()
        ctl.hotkeyDown()
        ctl.recorderFailed("can't open input device")
        #expect(ctl.state == .idle)
        #expect(host.notes == ["Recording failed: can't open input device"])
        #expect(host.has("cancel false") && host.has("sound error"))
    }

    @Test func recorderFailureAfterANormalStopIsIgnored() {
        let (ctl, host) = make()
        dictate(ctl, host)
        ctl.recorderFailed("")
        #expect(ctl.state == .transcribing)
        #expect(host.notes.isEmpty)
    }

    // Native additions

    @Test func lostDeviceTranscribesWhatWasRecorded() async throws {
        let (ctl, host) = make()
        ctl.hotkeyDown()
        host.advance(2)
        ctl.finishRecording("Microphone disconnected")
        #expect(ctl.state == .transcribing)
        #expect(host.notes == ["Microphone disconnected"])
        try await host.answer(1, with: .success("Текст"))
        await ctl.transcription?.value
        #expect(host.pasted.map(\.0) == ["Текст"])
        ctl.finishRecording("ignored when idle")
        #expect(host.notes == ["Microphone disconnected"])
    }

    @Test func historyWrittenBeforePaste() async throws {
        let (ctl, host) = make()
        dictate(ctl, host)
        try await host.answer(1, with: .success("Текст"))
        await ctl.transcription?.value
        let history = try #require(host.log.firstIndex(of: "history Текст"))
        let paste = try #require(host.log.firstIndex(of: "paste Текст"))
        #expect(history < paste)
    }

    @Test func noAccessibilityCopiesAndSaysSo() async throws {
        let (ctl, host) = make()
        host.pasteOutcome = .copied
        dictate(ctl, host)
        try await host.answer(1, with: .success("Текст"))
        await ctl.transcription?.value
        #expect(host.notes == [Controller.copiedNotice])
        #expect(host.records.map(\.outcome) == [.copied])
    }

    @Test func oneRecordPerOutcome() async throws {
        let (ctl, host) = make()
        dictate(ctl, host, seconds: 2)
        try await host.answer(1, with: .success(" кубер деплой "))
        await ctl.transcription?.value
        dictate(ctl, host)
        try await host.answer(2, with: .success("  "))
        await ctl.transcription?.value
        ctl.hotkeyDown(); host.advance(1); ctl.cancel()
        dictate(ctl, host, seconds: 0.4)
        dictate(ctl, host)
        try await host.answer(3, with: .failure(Boom(description: "x")))
        try await host.answer(4, with: .failure(Boom(description: "x")))
        await ctl.transcription?.value
        #expect(host.records.map(\.outcome) == [.pasted, .empty, .cancelled, .discarded, .failed])
        let pasted = try #require(host.records.first)
        #expect(pasted.audioSeconds == 2 && pasted.words == 2 && pasted.characters == 12)
        #expect(pasted.firedTerms == ["Kubernetes"] && pasted.detectedLanguage == "uk" && pasted.app?.name == "Slack")
        #expect(pasted.waitSeconds == 0) // the fake clock doesn't move during recognition
        #expect(host.records.dropFirst().allSatisfy { $0.words == 0 && $0.characters == 0 })
        #expect(zip(host.records.map(\.audioSeconds), [2, 1, 1, 0.4, 1]).allSatisfy { abs($0 - $1) < 0.001 })
    }

    @Test func noTextInTheStatisticsDatabase() async throws {
        let (ctl, host) = make()
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = StatsDatabase(file: dir.appending(path: "stats.sqlite"))
        let secret = "Таємна нарада про злиття компаній"
        dictate(ctl, host)
        try await host.answer(1, with: .success("\(secret) кубер"))
        await ctl.transcription?.value
        let record = try #require(host.records.first)
        try db.insert(DictationRow(record, engine: EngineChoice(engine: .whispercpp, model: "large-v3"), languageRequested: "uk", previewRequests: 2))
        let bytes = try Data(contentsOf: db.file)
        #expect(bytes.range(of: Data("Kubernetes".utf8)) != nil) // the search does see the file's contents
        #expect(bytes.range(of: Data(secret.utf8)) == nil)
        #expect(bytes.range(of: Data("нарада".utf8)) == nil)
        #expect(try db.dictations(in: nil).first?.replacedTerms == ["Kubernetes"]) // dictionary targets the user wrote are fine
    }

    // Overlay events

    @Test func overlayFullDictationEmitsRecordingTranscribingDone() async throws {
        let (ctl, host) = make()
        host.clock = Date(timeIntervalSince1970: 5)
        dictate(ctl, host)
        try await host.answer(1, with: .success(" Привіт "))
        await ctl.transcription?.value
        #expect(host.overlayEvents == ["recording 5", "start", "stop", "transcribing", "done Привіт"])
    }

    @Test func overlayCancelEmitsMessageAndStop() {
        let (ctl, host) = make()
        ctl.hotkeyDown(); host.advance(1); ctl.cancel()
        #expect(host.overlayEvents == ["recording 0", "start", "stop", "message Cancelled"])
    }

    @Test func overlaySilentShortHoldHides() {
        let (ctl, host) = make()
        host.mode = "hold"
        ctl.hotkeyDown(); host.advance(0.1); ctl.hotkeyUp()
        #expect(host.overlayEvents == ["recording 0", "start", "stop", "hide"])
    }

    @Test func overlayEmptyResultAndErrorsBecomeMessages() async throws {
        let (ctl, host) = make()
        dictate(ctl, host)
        try await host.answer(1, with: .success("  "))
        await ctl.transcription?.value
        #expect(host.overlayEvents.last == "message Nothing recognized")
        dictate(ctl, host)
        try await host.answer(2, with: .failure(Boom(description: "boom")))
        try await host.answer(3, with: .failure(Boom(description: "boom")))
        await ctl.transcription?.value
        #expect(host.overlayEvents.last == "message Transcription failed: boom — audio kept in /failed/a.wav")
    }

    @Test func overlayRecorderFailureEmitsStopAndMessage() {
        let (ctl, host) = make()
        ctl.hotkeyDown()
        ctl.recorderFailed("no mic")
        #expect(host.overlayEvents == ["recording 0", "start", "stop", "message Recording failed: no mic"])
    }

    @Test func overlayStartFailureEmitsOnlyAMessage() {
        let (ctl, host) = make()
        host.startError = "no mic"
        ctl.hotkeyDown()
        #expect(host.overlayEvents == ["message Recording failed: no mic"])
    }
}
