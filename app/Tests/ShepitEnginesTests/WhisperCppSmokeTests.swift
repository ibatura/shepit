import Foundation
import ShepitCore
import Testing
@testable import ShepitEngines

private let turbo = EngineChoice(engine: .whispercpp, model: "large-v3-turbo")

@Suite(.enabled(if: ModelCatalog.isDownloaded(turbo)), .serialized)
struct WhisperCppSmokeTests {
    private func fixture() throws -> [Float] {
        let url = try #require(Bundle.module.url(forResource: "hello", withExtension: "wav", subdirectory: "Fixtures"))
        return try AudioFile.load(url)
    }

    private func transcribe(_ samples: [Float], prompt: String = "") async throws -> Transcript {
        let engine = WhisperCppEngine(model: "large-v3-turbo")
        try await engine.load()
        let transcript = try await engine.transcribe(
            TranscriptionRequest(samples: samples, language: .en, prompt: prompt, wantSegments: true))
        await engine.unload()
        return transcript
    }

    @Test func transcribesFixture() async throws {
        let transcript = try await transcribe(try fixture())
        let text = transcript.text.lowercased()
        #expect(text.contains("test"))
        #expect(text.contains("speech"))
        #expect(transcript.segments.count >= 1)
        #expect(try #require(transcript.segments.first).start >= 0)
    }

    @Test func silenceDoesNotThrow() async throws {
        let transcript = try await transcribe([Float](repeating: 0, count: 16_000))
        #expect(transcript.text.count < 40)
    }

    @Test func promptAccepted() async throws {
        _ = try await transcribe(try fixture(), prompt: "Kubernetes, GitHub")
    }

    @Test func missingVADFailsBeforeLoadingModel() async throws {
        let vad = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)/ggml-silero-v6.2.0.bin")
        let engine = WhisperCppEngine(model: "large-v3-turbo", vadModel: vad)
        await #expect(throws: EngineError.modelMissing(vad.path)) { try await engine.load() }
        #expect(vad.path.contains("silero"))
        #expect(await engine.isLoaded == false)
    }
}

struct WhisperCppEngineTests {
    @Test func missingModelThrowsModelMissing() async throws {
        let engine = WhisperCppEngine(model: "no-such-model")
        let path = ModelCatalog.folder(for: EngineChoice(engine: .whispercpp, model: "no-such-model"))!.path
        await #expect(throws: EngineError.modelMissing(path)) { try await engine.load() }
    }

    @Test func factoryMakesWhisperCppEngine() {
        let engine = try? EngineFactory.make(turbo)
        #expect(engine is WhisperCppEngine)
    }
}
