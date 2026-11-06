import Foundation

public enum ModelCatalog {
    public static let vadModel = Paths.modelsDir.appending(path: "ggml-silero-v6.2.0.bin")

    public static func models(for engine: EngineID) -> [String] {
        switch engine {
        case .whisperkit, .whispercpp:
            ["large-v3", "large-v3-turbo"]
        case .parakeet:
            ["parakeet-tdt-0.6b-v3"]
        case .apple:
            [""]
        }
    }

    /// Bytes on disk of a model's file or folder (nil when absent; Apple's assets are the system's).
    public static func sizeOnDisk(_ choice: EngineChoice, paths: Paths.Resolved = Paths.resolve()) -> Int64? {
        guard let url = folder(for: choice, paths: paths),
              let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]) else { return nil }
        guard values.isDirectory == true else { return values.fileSize.map(Int64.init) }
        let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
        return (files?.allObjects as? [URL] ?? []).reduce(0) { total, file in
            total + Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    /// Every engine+model pair that can run now (Apple only on macOS 26).
    public static func downloadedChoices(paths: Paths.Resolved = Paths.resolve()) -> [EngineChoice] {
        EngineID.allCases.flatMap { engine in models(for: engine).map { EngineChoice(engine: engine, model: $0) } }
            .filter { choice in
                if choice.engine == .apple, #unavailable(macOS 26) { return false }
                return isDownloaded(choice, paths: paths)
            }
    }

    public static func tokenizerFolder(paths: Paths.Resolved = Paths.resolve()) -> URL? {
        paths.modelsDir.appending(path: "whisperkit/tokenizer", directoryHint: .isDirectory)
    }

    public static func folder(for choice: EngineChoice, paths: Paths.Resolved = Paths.resolve()) -> URL? {
        switch choice.engine {
        case .whispercpp:
            paths.modelsDir.appending(path: "ggml-\(choice.model).bin")
        case .whisperkit:
            paths.modelsDir.appending(path: "whisperkit/\(choice.model)", directoryHint: .isDirectory)
        case .parakeet:
            paths.modelsDir.appending(path: "parakeet/\(choice.model)", directoryHint: .isDirectory)
        case .apple:
            nil
        }
    }

    public static func isDownloaded(_ choice: EngineChoice, paths: Paths.Resolved = Paths.resolve()) -> Bool {
        guard let folder = folder(for: choice, paths: paths) else { return true }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory) else { return false }

        switch choice.engine {
        case .whispercpp:
            // whisper.cpp refuses to run without the VAD model, so it's part of the download.
            return !isDirectory.boolValue && FileManager.default.fileExists(atPath: paths.modelsDir.appending(path: "ggml-silero-v6.2.0.bin").path)
        case .whisperkit:
            guard let tokenizerFolder = tokenizerFolder(paths: paths) else { return false }
            return isDirectory.boolValue
                && FileManager.default.fileExists(atPath: folder.appending(path: ".complete").path)
                && FileManager.default.fileExists(atPath: tokenizerFolder.appending(path: ".complete").path)
                && FileManager.default.fileExists(atPath: tokenizerFolder.appending(path: "config.json").path)
                && FileManager.default.fileExists(atPath: tokenizerFolder.appending(path: "tokenizer.json").path)
                && FileManager.default.fileExists(atPath: tokenizerFolder.appending(path: "tokenizer_config.json").path)
        case .parakeet:
            return isDirectory.boolValue && FileManager.default.fileExists(atPath: folder.appending(path: ".complete").path)
        case .apple:
            return true
        }
    }
}

/// Models a meeting needs besides its transcription engine (spec §4.3, §5.2): Silero voice detection
/// and FluidAudio's offline speaker diarization. Each is a folder with a `.complete` marker.
public enum MeetingModel: String, CaseIterable, Sendable {
    case vad = "silero-vad"
    case diarization

    public var title: String {
        switch self {
        case .vad: "Voice detection (Silero)"
        case .diarization: "Speaker detection (pyannote + WeSpeaker)"
        }
    }

    var manifest: String { "\(rawValue).sha256" }

    var source: String {
        switch self {
        case .vad: "FluidInference/silero-vad-coreml/resolve/b419383c55c110e2c9271fa6ee0ea83d03c70d96"
        case .diarization: "FluidInference/speaker-diarization-coreml/resolve/df2625ac79a7ac6b65ad868fee6d80f320da4232"
        }
    }

    public func folder(paths: Paths.Resolved = Paths.resolve()) -> URL {
        paths.modelsDir.appending(path: rawValue, directoryHint: .isDirectory)
    }

    public func isDownloaded(paths: Paths.Resolved = Paths.resolve()) -> Bool {
        FileManager.default.fileExists(atPath: folder(paths: paths).appending(path: ".complete").path)
    }
}
