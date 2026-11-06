import Foundation

/// Draft text while recording: every few seconds, transcribe the last seconds of audio
/// (port of preview.lua). At most one request in flight; late results are dropped; never pasted.
@MainActor
public final class LivePreview {
    public static let interval = 2.0
    public static let window = 20.0
    public static let minSeconds = 0.5

    public struct Deps {
        public var enabled: @MainActor () -> Bool
        public var every: @MainActor (_ seconds: Double, _ action: @escaping @MainActor () -> Void) -> any TimerToken
        /// The newest `count` samples (16 kHz) of the running recording.
        public var tail: @MainActor (_ count: Int) -> [Float]
        public var transcribe: @MainActor ([Float]) async throws -> Transcript
        public var process: @MainActor (String) -> String
        public var onText: @MainActor (String) -> Void

        public init(
            enabled: @escaping @MainActor () -> Bool,
            every: @escaping @MainActor (Double, @escaping @MainActor () -> Void) -> any TimerToken,
            tail: @escaping @MainActor (Int) -> [Float],
            transcribe: @escaping @MainActor ([Float]) async throws -> Transcript,
            process: @escaping @MainActor (String) -> String,
            onText: @escaping @MainActor (String) -> Void
        ) {
            self.enabled = enabled
            self.every = every
            self.tail = tail
            self.transcribe = transcribe
            self.process = process
            self.onText = onText
        }
    }

    /// How many drafts ran in the current recording (for statistics).
    public private(set) var requests = 0

    private let deps: Deps
    private var session = 0
    private var busy = false
    private var timer: (any TimerToken)?

    public init(_ deps: Deps) {
        self.deps = deps
    }

    public func start() {
        stop()
        requests = 0
        guard deps.enabled() else { return }
        session += 1
        let session = session
        timer = deps.every(Self.interval) { [weak self] in self?.tick(session) }
    }

    public func stop() {
        guard let timer else { return }
        timer.cancel()
        self.timer = nil
        session += 1
        busy = false
    }

    private func tick(_ session: Int) {
        guard session == self.session, !busy else { return }
        let samples = deps.tail(Int(Self.window * 16_000))
        guard Double(samples.count) / 16_000 >= Self.minSeconds else { return }
        busy = true
        requests += 1
        Task { [weak self] in
            guard let self else { return }
            let text = try? await self.deps.transcribe(samples)
            guard session == self.session else { return }
            self.busy = false
            guard let text else { return }
            let result = self.deps.process(text.text)
            if !result.isEmpty { self.deps.onText(result) }
        }
    }
}
