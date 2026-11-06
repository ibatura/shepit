import Foundation
import ShepitCore
import Speech
import Testing
@testable import ShepitEngines

@available(macOS 26, *)
private func assetsInstalled(_ language: Language) async -> Bool {
    guard let module = await AppleSpeechEngine.module(for: language) else { return false }
    return await AppleSpeechEngine.assetStatus(for: language, module: module) == .installed
}

@Suite(.serialized)
struct AppleSpeechSmokeTests {
    @available(macOS 26, *)
    private func transcribe(_ samples: [Float], language: Language = .en, prompt: String = "") async throws -> Transcript {
        let engine = AppleSpeechEngine()
        try await engine.load()
        return try await engine.transcribe(
            TranscriptionRequest(samples: samples, language: language, prompt: prompt, wantSegments: true))
    }

    @available(macOS 26, *)
    @Test(.enabled { await assetsInstalled(.en) })
    func transcribesFixtureEnglish() async throws {
        let url = try #require(Bundle.module.url(forResource: "hello", withExtension: "wav", subdirectory: "Fixtures"))
        let transcript = try await transcribe(try AudioFile.load(url), prompt: "Kubernetes, GitHub")
        #expect(transcript.text.lowercased().contains("test"))
        #expect(transcript.segments.count >= 1)
        #expect(try #require(transcript.segments.first).start >= 0)
    }

    @available(macOS 26, *)
    @Test(.enabled { await assetsInstalled(.en) })
    func silenceDoesNotThrow() async throws {
        let transcript = try await transcribe([Float](repeating: 0, count: 16_000))
        #expect(transcript.text.count < 40)
    }

    @available(macOS 26, *)
    @Test(.enabled { await assetsInstalled(.en) })
    func emptyAudioGivesEmptyText() async throws {
        #expect(try await transcribe([]).text == "")
    }

    @available(macOS 26, *)
    @Test func autoRejected() async {
        #expect(await AppleSpeechEngine().capabilities.check(.auto) == .languageNotSupported(.auto))
    }

    @available(macOS 26, *)
    @Test func ukSupportMatchesSystem() async {
        let systemHasUk = await (SpeechTranscriber.supportedLocales + DictationTranscriber.supportedLocales)
            .contains { $0.identifier(.bcp47).hasPrefix("uk") }
        #expect(await AppleSpeechEngine().capabilities.forcibleLanguages.contains(.uk) == systemHasUk)
    }

    @available(macOS 26, *)
    @Test(.enabled { await !assetsInstalled(.uk) })
    func missingAssetsThrowModelMissing() async {
        let message = "Apple speech assets for uk are not installed — run: Shepit apple-assets uk --install"
        await #expect(throws: EngineError.modelMissing(message)) {
            try await AppleSpeechEngine().transcribe(TranscriptionRequest(samples: [0], language: .uk, prompt: "", wantSegments: false))
        }
    }

    @available(macOS 26, *)
    @Test func factoryMakesAppleEngine() {
        #expect((try? EngineFactory.make(EngineChoice(engine: .apple, model: ""))) is AppleSpeechEngine)
    }
}
