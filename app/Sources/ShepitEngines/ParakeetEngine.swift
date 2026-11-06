import FluidAudio
import Foundation
import ShepitCore

public actor ParakeetEngine: SpeechEngine {
    public let choice: EngineChoice
    private var manager: AsrManager?
    private let paths: Paths.Resolved

    public init(model: String, paths: Paths.Resolved = Paths.resolve()) {
        choice = EngineChoice(engine: .parakeet, model: model)
        self.paths = paths
    }

    // Token timings exist, but phase 1 returns one whole-input segment; grouping tokens into sentences waits for meetings.
    public var capabilities: EngineCapabilities {
        EngineCapabilities(supportsPrompt: false, forcibleLanguages: [], detectsLanguage: true, givesSegmentTimes: false)
    }

    public var isLoaded: Bool { manager != nil }

    public func load() async throws {
        guard manager == nil else { return }
        guard let folder = ModelCatalog.folder(for: choice, paths: paths),
              FileManager.default.fileExists(atPath: folder.appending(path: ".complete").path) else {
            throw EngineError.modelMissing(ModelCatalog.folder(for: choice, paths: paths)?.path ?? choice.model)
        }
        do {
            // loadLocal never downloads; Encoder_v2 (int8V2) is the one scripts/download-models.sh fetches.
            let models = try AsrModels.loadLocal(from: folder, version: .v3, encoderPrecision: .int8V2)
            manager = AsrManager(models: models)
        } catch {
            throw EngineError.loadFailed("Parakeet could not load \(folder.path): \(error)")
        }
    }

    public func unload() async {
        manager = nil
    }

    public func transcribe(_ request: TranscriptionRequest) async throws -> Transcript {
        try await load()
        guard let manager else { throw EngineError.loadFailed("Parakeet model missing") }
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let result: ASRResult
        do {
            result = try await manager.transcribe(request.samples, decoderState: &state)
        } catch {
            throw EngineError.recognitionFailed("Parakeet transcription failed: \(error)")
        }
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let segments = request.wantSegments ? [Segment(text: text, start: 0, end: Double(request.samples.count) / 16_000)] : []
        return Transcript(text: text, segments: segments, detectedLanguage: nil)
    }
}
