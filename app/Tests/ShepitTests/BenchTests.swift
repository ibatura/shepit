import Foundation
import Testing
@testable import Shepit
import ShepitCore

private actor FakeEngine: SpeechEngine {
    let choice = EngineChoice(engine: .apple, model: "")
    let capabilities: EngineCapabilities

    init(caps: EngineCapabilities) {
        capabilities = caps
    }

    func load() async throws {}
    func unload() async {}
    var isLoaded: Bool { false }
    func transcribe(_ request: TranscriptionRequest) async throws -> Transcript {
        Transcript(text: "", segments: [], detectedLanguage: nil)
    }
}

struct BenchTests {
    @Test func rejectsUnsupportedLanguageBeforeAttemptingToLoad() async {
        let engine = FakeEngine(caps: EngineCapabilities(
            supportsPrompt: false,
            forcibleLanguages: [.en],
            detectsLanguage: false,
            givesSegmentTimes: false
        ))
        var output = ""
        let status = await Bench.run(
            arguments: ["--engine", "apple", "--language", "uk", "x.wav"],
            engineFactory: { _ in engine },
            output: { output += $0 }
        )

        #expect(output.contains("\"event\":\"error\""))
        #expect(status == 1)
    }
}
