import Foundation
import ShepitCore
import Testing
@testable import ShepitEngines

private let whisperKitLargeV3 = EngineChoice(engine: .whisperkit, model: "large-v3")
private let whisperKitTurbo = EngineChoice(engine: .whisperkit, model: "large-v3-turbo")

@Suite(.enabled(if: ModelCatalog.isDownloaded(whisperKitLargeV3)), .serialized)
struct WhisperKitSmokeTests {
    private func fixture() throws -> [Float] {
        let url = try #require(Bundle.module.url(forResource: "hello", withExtension: "wav", subdirectory: "Fixtures"))
        return try AudioFile.load(url)
    }

    private func transcribe(
        _ samples: [Float],
        prompt: String = "",
        language: Language = .en,
        wantSegments: Bool = true
    ) async throws -> Transcript {
        let engine = WhisperKitEngine(model: "large-v3")
        try await engine.load()
        let transcript = try await engine.transcribe(
            TranscriptionRequest(samples: samples, language: language, prompt: prompt, wantSegments: wantSegments))
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
        #expect(transcript.detectedLanguage == "en")
    }

    @Test func silenceDoesNotThrow() async throws {
        let transcript = try await transcribe([Float](repeating: 0, count: 16_000))
        #expect(transcript.text.count < 40)
    }

    @Test func autoLanguageDetectsEnglish() async throws {
        let transcript = try await transcribe(try fixture(), language: .auto)
        #expect(transcript.detectedLanguage == "en")
    }

    @Test func omitsSegmentsWhenTheyAreNotRequested() async throws {
        let transcript = try await transcribe(try fixture(), wantSegments: false)
        #expect(transcript.segments.isEmpty)
    }

    @Test func promptAccepted() async throws {
        _ = try await transcribe(try fixture(), prompt: "Kubernetes, GitHub")
    }
}

@Suite(.enabled(if: ModelCatalog.isDownloaded(whisperKitTurbo)), .serialized)
struct WhisperKitTurboSmokeTests {
    @Test func transcribesFixture() async throws {
        let url = try #require(Bundle.module.url(forResource: "hello", withExtension: "wav", subdirectory: "Fixtures"))
        let engine = WhisperKitEngine(model: "large-v3-turbo")
        try await engine.load()
        let transcript = try await engine.transcribe(
            TranscriptionRequest(samples: try AudioFile.load(url), language: .en, prompt: "", wantSegments: true))
        await engine.unload()
        #expect(transcript.text.lowercased().contains("test"))
        #expect(transcript.detectedLanguage == "en")
    }
}

struct WhisperKitEngineTests {
    @Test func reportsWhisperKitCapabilities() async {
        let engine = WhisperKitEngine(model: "large-v3")
        #expect(await engine.choice == EngineChoice(engine: .whisperkit, model: "large-v3"))
        let capabilities = await engine.capabilities
        #expect(capabilities.supportsPrompt)
        #expect(capabilities.forcibleLanguages == [.uk, .en])
        #expect(capabilities.detectsLanguage)
        #expect(capabilities.givesSegmentTimes)
        #expect(await !engine.isLoaded)
    }

    @Test func missingModelThrowsModelMissing() async throws {
        let choice = EngineChoice(engine: .whisperkit, model: "missing-model")
        let engine = WhisperKitEngine(model: choice.model)
        let path = try #require(ModelCatalog.folder(for: choice)).path
        await #expect(throws: EngineError.modelMissing(path)) { try await engine.load() }
    }

    @Test func corruptTokenizerThrowsBeforeEngineConstruction() async throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = Paths.resolve(environment: ["DICTATION_HOME": home.path])
        let sourceTokenizer = try #require(ModelCatalog.tokenizerFolder())
        let tokenizerFolder = try #require(ModelCatalog.tokenizerFolder(paths: paths))
        try FileManager.default.createDirectory(at: tokenizerFolder, withIntermediateDirectories: true)
        for file in ["config.json", "tokenizer_config.json", "tokenizer.json"] {
            try FileManager.default.copyItem(at: sourceTokenizer.appending(path: file), to: tokenizerFolder.appending(path: file))
        }
        try Data("{not json".utf8).write(to: tokenizerFolder.appending(path: "tokenizer.json"))
        try Data().write(to: tokenizerFolder.appending(path: ".complete"))
        let sourceModel = try #require(ModelCatalog.folder(for: whisperKitLargeV3))
        let modelFolder = try #require(ModelCatalog.folder(for: whisperKitLargeV3, paths: paths))
        try FileManager.default.copyItem(at: sourceModel, to: modelFolder)
        let engine = WhisperKitEngine(model: whisperKitLargeV3.model, tokenizerFolder: tokenizerFolder, paths: paths)

        await #expect(throws: EngineError.loadFailed("WhisperKit tokenizer is invalid at \(tokenizerFolder.path)")) {
            try await engine.load()
        }
        #expect(FileManager.default.fileExists(atPath: tokenizerFolder.path))
    }

    @Test func missingTokenizerThrowsModelMissingBeforeEngineConstruction() async throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = Paths.resolve(environment: ["DICTATION_HOME": home.path])
        let choice = EngineChoice(engine: .whisperkit, model: "large-v3")
        let modelFolder = try #require(ModelCatalog.folder(for: choice, paths: paths))
        try FileManager.default.createDirectory(at: modelFolder, withIntermediateDirectories: true)
        try Data().write(to: modelFolder.appending(path: ".complete"))
        let tokenizerFolder = try #require(ModelCatalog.tokenizerFolder(paths: paths))
        let engine = WhisperKitEngine(model: choice.model, tokenizerFolder: tokenizerFolder, paths: paths)

        await #expect(throws: EngineError.modelMissing(tokenizerFolder.path)) { try await engine.load() }
        #expect(!FileManager.default.fileExists(atPath: tokenizerFolder.path))
        #expect(!FileManager.default.fileExists(atPath: home.appending(path: "Documents/huggingface").path))
    }

    @Test func factoryMakesWhisperKitEngine() {
        let choice = EngineChoice(engine: .whisperkit, model: "large-v3")
        let engine = try? EngineFactory.make(choice)
        #expect(engine is WhisperKitEngine)
    }
}
