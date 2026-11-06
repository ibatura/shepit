import Foundation
import ShepitCore
import Testing
@testable import ShepitEngines

private let parakeet = EngineChoice(engine: .parakeet, model: "parakeet-tdt-0.6b-v3")

@Suite(.enabled(if: ModelCatalog.isDownloaded(parakeet)), .serialized)
struct ParakeetSmokeTests {
    private func transcribe(_ samples: [Float]) async throws -> Transcript {
        let engine = ParakeetEngine(model: parakeet.model)
        try await engine.load()
        let transcript = try await engine.transcribe(
            TranscriptionRequest(samples: samples, language: .auto, prompt: "ignored", wantSegments: true))
        await engine.unload()
        return transcript
    }

    @Test func transcribesFixture() async throws {
        let url = try #require(Bundle.module.url(forResource: "hello", withExtension: "wav", subdirectory: "Fixtures"))
        let samples = try AudioFile.load(url)
        let transcript = try await transcribe(samples)
        #expect(transcript.text.lowercased().contains("test"))
        #expect(transcript.segments == [Segment(text: transcript.text, start: 0, end: Double(samples.count) / 16_000)])
    }

    @Test func silenceDoesNotThrow() async throws {
        let transcript = try await transcribe([Float](repeating: 0, count: 16_000))
        #expect(transcript.text.count < 40)
    }
}

struct ParakeetEngineTests {
    @Test func reportsParakeetCapabilities() async {
        let engine = ParakeetEngine(model: parakeet.model)
        #expect(await engine.choice == parakeet)
        let capabilities = await engine.capabilities
        #expect(!capabilities.supportsPrompt)
        #expect(capabilities.forcibleLanguages.isEmpty)
        #expect(capabilities.check(.auto) == nil)
        #expect(capabilities.check(.uk) == .languageNotSupported(.uk))
        #expect(!capabilities.givesSegmentTimes)
    }

    @Test func missingModelThrowsModelMissing() async throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = Paths.resolve(environment: ["DICTATION_HOME": home.path])
        let engine = ParakeetEngine(model: parakeet.model, paths: paths)
        let folder = try #require(ModelCatalog.folder(for: parakeet, paths: paths))
        await #expect(throws: EngineError.modelMissing(folder.path)) { try await engine.load() }
    }

    @Test func factoryMakesParakeetEngine() {
        #expect((try? EngineFactory.make(parakeet)) is ParakeetEngine)
    }
}
