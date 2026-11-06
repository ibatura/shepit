import Foundation
import Testing
@testable import ShepitCore

private struct Down: Error {}

private final class Ticker: TimerToken {
    let seconds: Double
    let action: @MainActor () -> Void
    var stopped = false

    init(_ seconds: Double, _ action: @escaping @MainActor () -> Void) {
        self.seconds = seconds
        self.action = action
    }

    func cancel() { stopped = true }
}

@MainActor
private final class Harness {
    var enabled = true
    var seconds = 3.0 // audio recorded so far
    var timers: [Ticker] = []
    var texts: [String] = []
    var asked: [Int] = []
    private var pending: [CheckedContinuation<Transcript, any Error>] = []
    lazy var preview = LivePreview(.init(
        enabled: { [unowned self] in self.enabled },
        every: { [unowned self] seconds, action in
            let timer = Ticker(seconds, action)
            self.timers.append(timer)
            return timer
        },
        tail: { [unowned self] count in [Float](repeating: 0, count: min(count, Int(self.seconds * 16_000))) },
        transcribe: { [unowned self] samples in
            self.asked.append(samples.count)
            return try await withCheckedThrowingContinuation { self.pending.append($0) }
        },
        process: { $0.trimmingCharacters(in: .whitespaces) },
        onText: { [unowned self] in self.texts.append($0) }))

    func tick() { timers.last?.action() }

    /// Waits for the `n`th request, then answers it and lets the result land.
    func answer(_ n: Int, _ text: String?) async throws {
        for _ in 0..<400 where asked.count < n || pending.isEmpty {
            try await Task.sleep(for: .milliseconds(5))
        }
        let continuation = pending.removeFirst()
        if let text {
            continuation.resume(returning: Transcript(text: text, segments: [], detectedLanguage: nil))
        } else {
            continuation.resume(throwing: Down())
        }
        try await Task.sleep(for: .milliseconds(20))
    }
}

// Ported from tests/test_preview.lua (snapshots of a WAV file become the newest samples in memory).
@MainActor
struct LivePreviewTests {
    @Test func startSchedulesTicksEveryInterval() {
        let h = Harness()
        h.preview.start()
        #expect(h.timers.count == 1)
        #expect(h.timers.first?.seconds == LivePreview.interval)
    }

    @Test func tickTakesTheLastWindowSecondsAndShowsProcessedText() async throws {
        let h = Harness()
        h.seconds = 30
        h.preview.start()
        h.tick()
        try await h.answer(1, "  Привіт  ")
        #expect(h.asked == [Int(LivePreview.window * 16_000)])
        #expect(h.texts == ["Привіт"])
    }

    @Test func tickIsSkippedWhileARequestIsInFlight() async throws {
        let h = Harness()
        h.preview.start()
        h.tick(); h.tick()
        #expect(h.preview.requests == 1)
        try await h.answer(1, "a")
        h.tick()
        #expect(h.preview.requests == 2)
    }

    @Test func tooShortAudioSendsNothing() {
        let h = Harness()
        h.seconds = 0.3
        h.preview.start()
        h.tick()
        h.seconds = 0
        h.tick()
        #expect(h.asked.isEmpty)
    }

    @Test func emptyResultsAndErrorsAreIgnored() async throws {
        let h = Harness()
        h.preview.start()
        h.tick(); try await h.answer(1, "   ")
        h.tick(); try await h.answer(2, nil)
        #expect(h.texts.isEmpty)
        h.tick()
        #expect(h.preview.requests == 3)
    }

    @Test func resultsAfterStopAreDiscarded() async throws {
        let h = Harness()
        h.preview.start()
        h.tick()
        h.preview.stop()
        #expect(h.timers.first?.stopped == true)
        try await h.answer(1, "late")
        #expect(h.texts.isEmpty)
    }

    @Test func resultFromAPreviousRecordingDoesNotLeakIntoTheNext() async throws {
        let h = Harness()
        h.preview.start()
        h.tick()
        h.preview.stop()
        h.preview.start()
        try await h.answer(1, "old text")
        #expect(h.texts.isEmpty)
        h.tick()
        #expect(h.preview.requests == 1) // not blocked by the stale in-flight request
    }

    @Test func disabledPreviewDoesNothing() {
        let h = Harness()
        h.enabled = false
        h.preview.start()
        #expect(h.timers.isEmpty)
        h.preview.stop()
    }

    @Test func countsRequestsPerRecording() async throws {
        let h = Harness()
        h.preview.start()
        h.tick(); try await h.answer(1, "a")
        h.tick(); try await h.answer(2, "b")
        #expect(h.preview.requests == 2)
        h.preview.start()
        #expect(h.preview.requests == 0)
    }
}
