import Foundation
import ShepitCore
import WhisperKit

public actor WhisperKitEngine: SpeechEngine {
    public let choice: EngineChoice
    private var whisperKit: WhisperKit?
    private let tokenizerFolder: URL
    private let paths: Paths.Resolved

    public init(
        model: String,
        tokenizerFolder: URL? = nil,
        paths: Paths.Resolved = Paths.resolve()
    ) {
        choice = EngineChoice(engine: .whisperkit, model: model)
        self.paths = paths
        self.tokenizerFolder = tokenizerFolder ?? ModelCatalog.tokenizerFolder(paths: paths)!
    }

    public var capabilities: EngineCapabilities {
        EngineCapabilities(supportsPrompt: true, forcibleLanguages: [.uk, .en], detectsLanguage: true, givesSegmentTimes: true)
    }

    public var isLoaded: Bool { whisperKit != nil }

    public func load() async throws {
        guard whisperKit == nil else { return }
        guard let folder = ModelCatalog.folder(for: choice, paths: paths) else {
            throw EngineError.modelMissing(choice.model)
        }
        guard FileManager.default.fileExists(atPath: folder.appending(path: ".complete").path) else {
            throw EngineError.modelMissing(folder.path)
        }
        guard FileManager.default.fileExists(atPath: tokenizerFolder.appending(path: ".complete").path),
              FileManager.default.fileExists(atPath: tokenizerFolder.appending(path: "config.json").path),
              FileManager.default.fileExists(atPath: tokenizerFolder.appending(path: "tokenizer.json").path),
              FileManager.default.fileExists(atPath: tokenizerFolder.appending(path: "tokenizer_config.json").path) else {
            throw EngineError.modelMissing(tokenizerFolder.path)
        }
        do {
            _ = try await AutoTokenizerWrapper.from(
                modelFolder: tokenizerFolder,
                hubApi: HubApiWrapper(downloadBase: tokenizerFolder, endpoint: "file:///nonexistent")
            )
        } catch {
            throw EngineError.loadFailed("WhisperKit tokenizer is invalid at \(tokenizerFolder.path)")
        }
        let model: WhisperKit
        do {
            model = try await WhisperKit(WhisperKitConfig(
                downloadBase: tokenizerFolder,
                modelEndpoint: "file:///nonexistent",
                modelFolder: folder.path,
                tokenizerFolder: tokenizerFolder,
                verbose: false,
                load: true,
                download: false
            ))
        } catch {
            throw EngineError.loadFailed("WhisperKit could not load \(folder.path): \(error)")
        }
        whisperKit = model
    }

    public func unload() async {
        await whisperKit?.unloadModels()
        whisperKit = nil
    }

    public func transcribe(_ request: TranscriptionRequest) async throws -> Transcript {
        try await load()
        guard let whisperKit, let tokenizer = whisperKit.tokenizer else {
            throw EngineError.loadFailed("WhisperKit model or tokenizer missing")
        }
        let prompt = request.prompt.isEmpty ? "" : " \(request.prompt)"
        let promptTokens = prompt.isEmpty ? nil : tokenizer.encode(text: prompt).filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        let options = DecodingOptions(
            task: .transcribe,
            language: request.language == .auto ? nil : request.language.rawValue,
            temperature: 0,
            temperatureFallbackCount: 0,
            usePrefillPrompt: true,
            detectLanguage: request.language == .auto,
            withoutTimestamps: !request.wantSegments,
            promptTokens: promptTokens
        )
        do {
            let results: [TranscriptionResult] = try await whisperKit.transcribe(
                audioArray: request.samples,
                decodeOptions: options
            )
            guard !results.isEmpty else { throw EngineError.recognitionFailed("WhisperKit returned no results") }
            let segments = request.wantSegments ? results.flatMap { result in
                result.segments.map { Segment(text: $0.text, start: Double($0.start), end: Double($0.end)) }
            } : []
            let text = results.map { $0.text }.joined().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            return Transcript(text: text, segments: segments, detectedLanguage: results.first?.language)
        } catch let error as EngineError {
            throw error
        } catch {
            throw EngineError.recognitionFailed("WhisperKit transcription failed: \(error)")
        }
    }
}
