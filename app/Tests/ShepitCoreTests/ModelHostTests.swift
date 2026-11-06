import Foundation
import Testing
@testable import ShepitCore

private let modelX = EngineChoice(engine: .whispercpp, model: "large-v3-turbo")
private let modelY = EngineChoice(engine: .whisperkit, model: "large-v3")

/// Shared log of what every fake engine did, and gates the test opens to let a request finish.
private actor Recorder {
    var events: [String] = []
    var created: [EngineChoice] = []
    private var gates: [String: CheckedContinuation<Void, Never>] = [:]
    private var opened: Set<String> = []

    func log(_ event: String) { events.append(event) }
    func create(_ choice: EngineChoice) { created.append(choice) }

    func wait(for id: String) async {
        if opened.contains(id) { return }
        await withCheckedContinuation { gates[id] = $0 }
    }

    func open(_ id: String) {
        opened.insert(id)
        gates.removeValue(forKey: id)?.resume()
    }

    func count(_ event: String) -> Int { events.filter { $0 == event }.count }
    func started(_ id: String) -> Bool { events.contains("start \(id)") }
}

private actor FakeEngine: SpeechEngine {
    let choice: EngineChoice
    private let recorder: Recorder
    private var loaded = false

    init(_ choice: EngineChoice, _ recorder: Recorder) {
        self.choice = choice
        self.recorder = recorder
    }

    var capabilities: EngineCapabilities {
        EngineCapabilities(supportsPrompt: true, forcibleLanguages: [.uk], detectsLanguage: true, givesSegmentTimes: false)
    }

    var isLoaded: Bool { loaded }

    func load() async throws {
        guard !loaded else { return }
        await recorder.log("load \(choice.engine.rawValue)")
        await recorder.wait(for: "load \(choice.engine.rawValue)")
        loaded = true
    }

    func unload() async {
        loaded = false
        await recorder.log("unload \(choice.engine.rawValue)")
    }

    func transcribe(_ request: TranscriptionRequest) async throws -> Transcript {
        await recorder.log("start \(request.prompt)")
        await recorder.wait(for: request.prompt)
        await recorder.log("end \(request.prompt)")
        return Transcript(text: request.prompt, segments: [], detectedLanguage: nil)
    }
}

private func request(_ id: String) -> TranscriptionRequest {
    TranscriptionRequest(samples: [0], language: .uk, prompt: id, wantSegments: false)
}

/// Polls until `condition` holds (other tasks run in between); fails after ~2 s.
private func eventually(_ condition: () async -> Bool) async throws {
    for _ in 0..<400 {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("condition never became true")
}

struct ModelHostTests {
    private func makeHost(
        _ recorder: Recorder,
        dictation: EngineChoice = modelX,
        preview: EngineChoice = modelX,
        idleSleep: @escaping @Sendable (Duration) async throws -> Void = { _ in try await Task.sleep(for: .seconds(3600)) }
    ) async -> ModelHost {
        let host = ModelHost(factory: { choice in
            Task { await recorder.create(choice) }
            return FakeEngine(choice, recorder)
        }, sleep: idleSleep)
        await host.setChoices([.dictation: dictation, .preview: preview, .meetings: dictation])
        return host
    }

    private func openLoads(_ recorder: Recorder) async {
        await recorder.open("load whispercpp")
        await recorder.open("load whisperkit")
    }

    @Test func sameChoiceSharesInstance() async throws {
        let recorder = Recorder()
        let host = await makeHost(recorder)
        await openLoads(recorder)
        await recorder.open("a")
        await recorder.open("b")
        _ = try await host.transcribe(.dictation, request("a"))
        _ = try await host.transcribe(.preview, request("b"))
        try await eventually { await recorder.created == [modelX] }
        #expect(await recorder.count("load whispercpp") == 1)
    }

    @Test func loadsOnceUnderConcurrentRequests() async throws {
        let recorder = Recorder()
        let host = await makeHost(recorder)
        await recorder.open("a")
        await recorder.open("b")
        async let first = host.transcribe(.dictation, request("a"))
        async let second = host.transcribe(.preview, request("b"))
        try await eventually { await recorder.count("load whispercpp") == 1 }
        await openLoads(recorder)
        _ = try await (first, second)
        #expect(await recorder.count("load whispercpp") == 1)
    }

    @Test func dictationRunsBeforeQueuedMeetingChunksAndMeetingChunksAreNeverDropped() async throws {
        let recorder = Recorder()
        let host = await makeHost(recorder)
        await openLoads(recorder)
        let running = Task { try await host.transcribe(.meetings, request("m1")) }
        try await eventually { await recorder.events.contains("start m1") }
        let m2 = Task { try await host.transcribe(.meetings, request("m2")) }
        try await eventually { await host.queuedCount(modelX) == 1 }
        let m3 = Task { try await host.transcribe(.meetings, request("m3")) }
        try await eventually { await host.queuedCount(modelX) == 2 }
        let dictation = Task { try await host.transcribe(.dictation, request("d")) }
        try await eventually { await host.queuedCount(modelX) == 3 }
        for id in ["m1", "d", "m2", "m3"] { await recorder.open(id) }
        _ = try await (running.value, dictation.value, m2.value, m3.value)
        #expect(await recorder.events.filter { $0.hasPrefix("start") } == ["start m1", "start d", "start m2", "start m3"])
    }

    @Test func dictationRunsBeforeQueuedPreview() async throws {
        let recorder = Recorder()
        let host = await makeHost(recorder)
        await openLoads(recorder)
        let running = Task { try await host.transcribe(.preview, request("p1")) }
        try await eventually { await recorder.events.contains("start p1") }
        let queuedPreview = Task { try await host.transcribe(.preview, request("p2")) }
        try await eventually { await host.queuedCount(modelX) == 1 }
        let dictation = Task { try await host.transcribe(.dictation, request("d")) }
        try await eventually { await host.queuedCount(modelX) == 2 }
        for id in ["p1", "d", "p2"] { await recorder.open(id) }
        _ = try await (running.value, dictation.value, queuedPreview.value)
        #expect(await recorder.events.filter { $0.hasPrefix("start") } == ["start p1", "start d", "start p2"])
    }

    @Test func newerPreviewCancelsQueued() async throws {
        let recorder = Recorder()
        let host = await makeHost(recorder)
        await openLoads(recorder)
        let running = Task { try await host.transcribe(.preview, request("p1")) }
        try await eventually { await recorder.events.contains("start p1") }
        let stale = Task { try await host.transcribe(.preview, request("p2")) }
        try await eventually { await host.queuedCount(modelX) == 1 }
        let fresh = Task { try await host.transcribe(.preview, request("p3")) }
        await #expect(throws: CancellationError.self) { try await stale.value }
        await recorder.open("p1")
        await recorder.open("p3")
        _ = try await (running.value, fresh.value)
        #expect(await !recorder.events.contains("start p2"))
    }

    @Test func differentModelsRunInParallel() async throws {
        let recorder = Recorder()
        let host = await makeHost(recorder, dictation: modelX, preview: modelY)
        await openLoads(recorder)
        let dictation = Task { try await host.transcribe(.dictation, request("d")) }
        let preview = Task { try await host.transcribe(.preview, request("p")) }
        try await eventually { let d = await recorder.started("d"); let p = await recorder.started("p"); return d && p }
        await recorder.open("d")
        await recorder.open("p")
        _ = try await (dictation.value, preview.value)
    }

    @Test func changingChoiceLoadsNewAndUnloadsUnused() async throws {
        let recorder = Recorder()
        let host = await makeHost(recorder)
        await openLoads(recorder)
        await host.preload([.dictation])
        await host.setChoices([.dictation: modelY, .preview: modelY, .meetings: modelY])
        try await eventually { let unloaded = await recorder.count("unload whispercpp"); let loaded = await recorder.count("load whisperkit"); return unloaded == 1 && loaded == 1 }
    }

    @Test func idleUnloadAfterMinutesAndLoadsAgainOnNextUse() async throws {
        let recorder = Recorder()
        let host = await makeHost(recorder, idleSleep: { _ in })
        await host.setIdleUnload(minutes: 5)
        await openLoads(recorder)
        await recorder.open("a")
        await recorder.open("b")
        _ = try await host.transcribe(.dictation, request("a"))
        try await eventually { await recorder.events.contains("unload whispercpp") }
        _ = try await host.transcribe(.dictation, request("b"))
        #expect(await recorder.count("load whispercpp") == 2)
    }

    @Test func reportsEachLoadOnce() async throws {
        let recorder = Recorder()
        let loads = Recorder()
        let host = ModelHost(factory: { FakeEngine($0, recorder) }, onLoad: { choice, seconds in
            Task { await loads.log("\(choice.engine.rawValue) \(seconds >= 0)") }
        })
        await host.setChoices([.dictation: modelX, .preview: modelX])
        await openLoads(recorder)
        await recorder.open("a")
        await recorder.open("b")
        _ = try await host.transcribe(.dictation, request("a"))
        _ = try await host.transcribe(.preview, request("b"))
        try await eventually { await loads.events == ["whispercpp true"] }
    }

    @Test func zeroIdleMinutesNeverUnloads() async throws {
        let recorder = Recorder()
        let host = await makeHost(recorder, idleSleep: { _ in })
        await openLoads(recorder)
        await recorder.open("a")
        _ = try await host.transcribe(.dictation, request("a"))
        try await Task.sleep(for: .milliseconds(50))
        #expect(await !recorder.events.contains("unload whispercpp"))
    }
}
