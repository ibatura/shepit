@preconcurrency import CoreML
@preconcurrency import FluidAudio
import Foundation
import ShepitCore

/// Models are loaded straight from our folders with `MLModel`, never through FluidAudio's `ModelHub`,
/// so nothing here can reach the network (spec anti-goal: no audio or text leaves the Mac).
private func loadModel(_ url: URL, units: MLComputeUnits) throws -> MLModel {
    guard FileManager.default.fileExists(atPath: url.path) else { throw EngineError.modelMissing(url.path) }
    let configuration = MLModelConfiguration()
    configuration.computeUnits = units
    do {
        return try MLModel(contentsOf: url, configuration: configuration)
    } catch {
        throw EngineError.loadFailed("could not load \(url.lastPathComponent): \(error)")
    }
}

private func requireComplete(_ model: MeetingModel, paths: Paths.Resolved) throws -> URL {
    let folder = model.folder(paths: paths)
    guard model.isDownloaded(paths: paths) else { throw EngineError.modelMissing(folder.path) }
    return folder
}

/// Silero voice activity, one probability per 4096-sample frame (256 ms at 16 kHz), with the model's
/// recurrent state carried across frames of one stream. One instance per stream.
public actor SileroVAD {
    public static let frameSamples = VadManager.chunkSize

    private let manager: VadManager
    private var state = VadStreamState.initial()

    public init(paths: Paths.Resolved = Paths.resolve()) throws {
        let folder = try requireComplete(.vad, paths: paths)
        let model = try loadModel(folder.appending(path: ModelNames.VAD.sileroVadFile), units: .cpuAndNeuralEngine)
        manager = VadManager(config: .default, vadModel: model)
    }

    /// Speech probability of one frame of exactly `frameSamples` samples.
    public func probability(_ frame: [Float]) async throws -> Float {
        let result = try await manager.processStreamingChunk(frame, state: state)
        state = result.state
        return result.probability
    }
}

/// FluidAudio's offline diarization (pyannote segmentation + WeSpeaker embeddings + VBx) over a whole call.
public enum Diarizer {
    public static func turns(_ samples: [Float], paths: Paths.Resolved = Paths.resolve()) async throws -> [SpeakerTurn] {
        let folder = try requireComplete(.diarization, paths: paths)
        let started = Date()
        let models = OfflineDiarizerModels(
            segmentationModel: try loadModel(folder.appending(path: ModelNames.OfflineDiarizer.segmentationFile), units: .all),
            fbankModel: try loadModel(folder.appending(path: ModelNames.OfflineDiarizer.fbankFile), units: .cpuOnly),
            embeddingModel: try loadModel(folder.appending(path: ModelNames.OfflineDiarizer.embeddingFile), units: .all),
            pldaRhoModel: try loadModel(folder.appending(path: ModelNames.OfflineDiarizer.pldaRhoFile), units: .all),
            pldaPsi: try pldaPsi(folder.appending(path: ModelNames.OfflineDiarizer.pldaParameters)),
            compilationDuration: Date().timeIntervalSince(started))
        let manager = OfflineDiarizerManager(config: .default)
        manager.initialize(models: models)
        do {
            let result = try await manager.process(audio: samples)
            return result.segments.map { SpeakerTurn(speaker: $0.speakerId, start: Double($0.startTimeSeconds), end: Double($0.endTimeSeconds)) }
        } catch {
            throw EngineError.recognitionFailed("speaker detection failed: \(error)")
        }
    }

    /// The `psi` tensor from `plda-parameters.json` (base64 Float32), as FluidAudio's own loader reads it.
    static func pldaPsi(_ url: URL) throws -> [Double] {
        guard let data = try? Data(contentsOf: url) else { throw EngineError.modelMissing(url.path) }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tensors = root["tensors"] as? [String: Any],
              let psi = tensors["psi"] as? [String: Any],
              let base64 = psi["data_base64"] as? String,
              let decoded = Data(base64Encoded: base64, options: .ignoreUnknownCharacters),
              decoded.count >= MemoryLayout<Float>.size else {
            throw EngineError.loadFailed("could not read \(url.lastPathComponent)")
        }
        var floats = [Float](repeating: 0, count: decoded.count / MemoryLayout<Float>.size)
        _ = floats.withUnsafeMutableBytes { decoded.copyBytes(to: $0) }
        return floats.map(Double.init)
    }
}
