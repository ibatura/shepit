import Foundation
import Observation
import ShepitCore
import ShepitEngines
import Speech

/// What Settings downloads: a recognition model, or a meeting model (voice or speaker detection).
enum DownloadItem: Hashable {
    case engine(EngineChoice)
    case meeting(MeetingModel)
}

/// Download / delete of models from Settings. Nothing touches the network unless the user clicks Download.
@MainActor
@Observable
final class ModelDownloads {
    /// 0…1, or −1 while the amount isn't known (Apple's system assets).
    private(set) var progress: [DownloadItem: Double] = [:]
    /// One download at a time: models share files (the WhisperKit tokenizer, the VAD model).
    private(set) var running: DownloadItem?
    private(set) var errors: [DownloadItem: String] = [:]
    /// Bumped after a download or delete so rows re-read what's on disk.
    private(set) var revision = 0

    @ObservationIgnored private var tasks: [DownloadItem: Task<Void, Never>] = [:]
    @ObservationIgnored private let downloader = ModelDownloader()
    /// The pinned manifests bundled into Shepit.app (nil when running unbundled, e.g. `swift run`).
    @ObservationIgnored private let manifests = Bundle.main.resourceURL?.appending(path: "models")
    @ObservationIgnored var onChange: () -> Void = {}

    var canDownload: Bool {
        manifests.map { FileManager.default.fileExists(atPath: $0.appending(path: "ggml.sha256").path) } ?? false
    }

    func download(_ item: DownloadItem, language: String = "") {
        guard running == nil else { return }
        let apple = if case .engine(let choice) = item { choice.engine == .apple } else { false }
        running = item
        errors[item] = nil
        progress[item] = apple ? -1 : 0
        tasks[item] = Task {
            do {
                if apple {
                    try await installAppleAssets(language: language)
                } else {
                    guard let manifests else { throw RecorderError("model manifests aren't bundled in this build") }
                    let jobs = try Self.jobs(for: item, manifests: manifests)
                    try await downloader.install(jobs) { value in
                        Task { @MainActor in if self.running == item { self.progress[item] = max(self.progress[item] ?? 0, value) } }
                    }
                }
            } catch is CancellationError {
            } catch let error as URLError where error.code == .cancelled {
            } catch {
                errors[item] = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            }
            tasks[item] = nil
            progress[item] = nil
            running = nil
            revision += 1
            onChange()
        }
    }

    func cancel(_ item: DownloadItem) {
        tasks[item]?.cancel()
    }

    /// Removes the model's own file or folder (the shared VAD model and WhisperKit tokenizer stay).
    /// `inUse` is asked at the moment of deleting, since settings may have changed while the dialog was open.
    func delete(_ item: DownloadItem, inUse: Bool) {
        guard !inUse else {
            errors[item] = "In use — choose another engine for those tasks first"
            return
        }
        guard running != item, let manifests, let job = try? Self.jobs(for: item, manifests: manifests).first else { return }
        do {
            try FileManager.default.removeItem(at: job.destination)
        } catch CocoaError.fileNoSuchFile {
        } catch {
            errors[item] = error.localizedDescription
        }
        revision += 1
        onChange()
    }

    private static func jobs(for item: DownloadItem, manifests: URL) throws -> [DownloadJob] {
        switch item {
        case .engine(let choice): try ModelSources.jobs(for: choice, manifests: manifests)
        case .meeting(let model): [try ModelSources.job(for: model, manifests: manifests)]
        }
    }

    /// Apple's speech assets come from macOS, for the dictation language (both when it's auto).
    private func installAppleAssets(language: String) async throws {
        guard #available(macOS 26, *) else { throw RecorderError("Apple Speech needs macOS 26") }
        let languages: [Language] = Language(rawValue: language).map { $0 == .auto ? [.uk, .en] : [$0] } ?? [.uk]
        for language in languages {
            guard let module = await AppleSpeechEngine.module(for: language),
                  let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) else { continue }
            try await request.downloadAndInstall()
        }
    }
}
