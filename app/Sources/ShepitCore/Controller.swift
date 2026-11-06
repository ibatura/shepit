import Foundation

public enum ControllerState: String, Sendable {
    case idle
    case recording
    case transcribing
}

public struct AppRef: Equatable, Sendable {
    public var bundleID: String?
    public var name: String

    public init(bundleID: String?, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

public enum PasteOutcome: Sendable {
    case pasted
    case copied // no Accessibility: the text is on the clipboard only
}

public enum Sound: Sendable {
    case start
    case done
    case error
}

public enum OverlayEvent: Equatable, Sendable {
    case recording(Date)
    case transcribing
    case done(String)
    case message(String)
    case hide
}

public enum DictationOutcome: String, Sendable {
    case pasted, copied, empty, cancelled, discarded, failed
}

/// One dictation attempt for statistics (`05-statistics.md` §1). Deliberately has no text field.
public struct DictationRecord: Equatable, Sendable {
    public var outcome: DictationOutcome
    public var startedAt: Date
    public var audioSeconds: Double
    public var waitSeconds: Double
    public var words: Int
    public var characters: Int
    public var detectedLanguage: String?
    public var app: AppRef?
    public var firedTerms: [String]
}

public protocol TimerToken: AnyObject {
    func cancel()
}

/// Everything the controller does to the outside world; the app implements it, tests fake it.
@MainActor
public protocol ControllerHost: AnyObject {
    var mode: String { get }
    var maxRecordingSeconds: Double { get }
    /// Why dictation can't start now (a meeting is recording and the setting blocks it), or nil.
    var dictationBlocked: String? { get }
    func now() -> Date
    func after(_ seconds: Double, _ action: @escaping @MainActor () -> Void) -> any TimerToken
    func frontApp() -> AppRef?
    func startRecording() throws
    func stopRecording() -> [Float]
    func cancelRecording()
    func transcribe(_ samples: [Float]) async throws -> Transcript
    func process(_ text: String) -> (text: String, fired: [String])
    func appendHistory(_ text: String)
    func paste(_ text: String, into app: AppRef?) async -> PasteOutcome
    func keepFailed(_ samples: [Float]) -> URL?
    func setState(_ state: ControllerState)
    func notify(_ message: String)
    func overlay(_ event: OverlayEvent)
    func sound(_ sound: Sound)
    func bindCancel(_ on: Bool)
    func recordingStarted()
    func recordingEnded()
    func record(_ dictation: DictationRecord)
}

/// Dictation state machine: idle → recording → transcribing → idle (port of src/dictation/controller.lua).
@MainActor
public final class Controller {
    public static let holdMin = 0.3
    public static let minSeconds = 0.5
    public static let transcribeTimeout = 120.0
    public static let copiedNotice = "Text copied — allow Accessibility for Shepit to paste it"

    public private(set) var state = ControllerState.idle
    /// The running recognition, so tests (and shutdown) can wait for it.
    public private(set) var transcription: Task<Void, Never>?

    private struct Recording {
        let mode: String
        let startedAt: Date
        let app: AppRef?
    }

    private let host: any ControllerHost
    private var session = 0
    private var recording: Recording?
    private var autoStop: (any TimerToken)?
    private var watchdog: (any TimerToken)?

    public init(host: any ControllerHost) {
        self.host = host
    }

    public func hotkeyDown() {
        if state == .idle {
            if let reason = host.dictationBlocked {
                host.notify(reason)
                return
            }
            start()
        } else if state == .recording, recording?.mode == "toggle" {
            stop()
        }
    }

    public func hotkeyUp() {
        if state == .recording, recording?.mode == "hold" {
            stop()
        }
    }

    public func cancel() {
        if state == .recording {
            discard("Cancelled", outcome: .cancelled)
        }
    }

    /// The recorder stopped on its own (device gone, no fallback).
    public func recorderFailed(_ message: String) {
        guard state == .recording else { return }
        host.sound(.error)
        discard("Recording failed: \(message)", outcome: .failed)
    }

    /// The recorder lost its device but kept audio: transcribe what there is.
    public func finishRecording(_ notice: String) {
        guard state == .recording else { return }
        host.notify(notice)
        stop()
    }

    private func start() {
        do {
            try host.startRecording()
        } catch {
            notify("Recording failed: \(describe(error))")
            host.sound(.error)
            return
        }
        session += 1
        let startedAt = host.now()
        recording = Recording(mode: host.mode, startedAt: startedAt, app: host.frontApp())
        let session = session
        autoStop = host.after(host.maxRecordingSeconds) { [weak self] in
            guard let self, self.session == session, self.state == .recording else { return }
            self.stop()
        }
        host.bindCancel(true)
        host.sound(.start)
        setState(.recording)
        host.overlay(.recording(startedAt))
        host.recordingStarted()
    }

    /// Leave the recording state without transcribing.
    private func discard(_ message: String?, outcome: DictationOutcome) {
        guard let recording else { return }
        autoStop?.cancel()
        autoStop = nil
        host.bindCancel(false)
        host.cancelRecording()
        host.recordingEnded()
        self.recording = nil
        record(outcome, recording, audioSeconds: host.now().timeIntervalSince(recording.startedAt))
        if let message { notify(message) } else { host.overlay(.hide) }
        setState(.idle)
    }

    private func stop() {
        guard let recording else { return }
        let held = host.now().timeIntervalSince(recording.startedAt)
        if recording.mode == "hold", held < Self.holdMin { return discard(nil, outcome: .discarded) }
        if held < Self.minSeconds { return discard("Recording too short", outcome: .discarded) }

        autoStop?.cancel()
        autoStop = nil
        host.bindCancel(false)
        let samples = host.stopRecording()
        host.recordingEnded()
        setState(.transcribing)
        host.overlay(.transcribing)
        let stoppedAt = host.now()
        let session = session
        watchdog = host.after(Self.transcribeTimeout) { [weak self] in
            guard let self, self.session == session, self.state == .transcribing else { return }
            self.fail("Transcription timed out", recording, samples, stoppedAt: stoppedAt)
        }
        transcription = Task { [weak self] in
            guard let self else { return }
            let result = await self.recognize(samples, session: session)
            guard self.session == session, self.state == .transcribing else { return } // timed out or superseded
            await self.finish(result, recording, samples, stoppedAt: stoppedAt)
        }
    }

    /// One retry on failure (`03-dictation.md` §3), unless the attempt was abandoned meanwhile.
    private func recognize(_ samples: [Float], session: Int) async -> Result<Transcript, any Error> {
        do {
            return .success(try await host.transcribe(samples))
        } catch {
            guard self.session == session, state == .transcribing else { return .failure(error) }
            do {
                return .success(try await host.transcribe(samples))
            } catch {
                return .failure(error)
            }
        }
    }

    private func finish(_ result: Result<Transcript, any Error>, _ recording: Recording, _ samples: [Float], stoppedAt: Date) async {
        watchdog?.cancel()
        watchdog = nil
        self.recording = nil
        let transcript: Transcript
        switch result {
        case .failure(let error):
            return fail("Transcription failed: \(describe(error))", recording, samples, stoppedAt: stoppedAt)
        case .success(let value):
            transcript = value
        }
        let audioSeconds = stoppedAt.timeIntervalSince(recording.startedAt)
        let processed = host.process(transcript.text)
        guard !processed.text.isEmpty else {
            record(.empty, recording, audioSeconds: audioSeconds, waitSeconds: host.now().timeIntervalSince(stoppedAt),
                   detectedLanguage: transcript.detectedLanguage, fired: processed.fired)
            notify("Nothing recognized")
            return setState(.idle)
        }
        let waitSeconds = host.now().timeIntervalSince(stoppedAt)
        host.appendHistory(processed.text) // before pasting, so the text is never lost
        let outcome = await host.paste(processed.text, into: recording.app)
        host.overlay(.done(processed.text))
        host.sound(.done)
        if outcome == .copied { notify(Self.copiedNotice) }
        record(outcome == .pasted ? .pasted : .copied, recording, audioSeconds: audioSeconds, waitSeconds: waitSeconds,
               text: processed.text, detectedLanguage: transcript.detectedLanguage, fired: processed.fired)
        setState(.idle)
    }

    private func fail(_ message: String, _ recording: Recording, _ samples: [Float], stoppedAt: Date) {
        watchdog?.cancel()
        watchdog = nil
        self.recording = nil
        let kept = host.keepFailed(samples)
        notify(kept.map { "\(message) — audio kept in \($0.path)" } ?? message)
        host.sound(.error)
        record(.failed, recording, audioSeconds: stoppedAt.timeIntervalSince(recording.startedAt),
               waitSeconds: host.now().timeIntervalSince(stoppedAt))
        setState(.idle)
    }

    private func record(
        _ outcome: DictationOutcome, _ recording: Recording, audioSeconds: Double, waitSeconds: Double = 0,
        text: String = "", detectedLanguage: String? = nil, fired: [String] = []
    ) {
        host.record(DictationRecord(
            outcome: outcome, startedAt: recording.startedAt, audioSeconds: audioSeconds, waitSeconds: waitSeconds,
            words: text.split(whereSeparator: \.isWhitespace).count, characters: text.count,
            detectedLanguage: detectedLanguage, app: recording.app, firedTerms: fired))
    }

    private func notify(_ message: String) {
        host.notify(message)
        host.overlay(.message(message))
    }

    private func setState(_ state: ControllerState) {
        self.state = state
        host.setState(state)
    }

    private func describe(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
}
