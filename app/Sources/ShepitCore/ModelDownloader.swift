import CryptoKit
import Foundation

/// One line of a pinned manifest (`scripts/models/*.sha256`): SHA-256 and a relative path.
public struct ManifestEntry: Equatable, Sendable {
    public let sha256: String
    public let path: String
}

public enum Manifest {
    public struct Invalid: Error, Equatable, CustomStringConvertible {
        public let description: String
    }

    /// Every non-blank line must be `<64 hex>  <relative path>`; duplicates and paths leaving the
    /// folder are rejected — before anything is downloaded (as fetch_dir in download-models.sh).
    public static func parse(_ text: String) throws -> [ManifestEntry] {
        var entries: [ManifestEntry] = []
        var seen = Set<String>()
        for line in text.split(whereSeparator: \.isNewline) where !line.allSatisfy(\.isWhitespace) {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count == 2, fields[0].count == 64, fields[0].allSatisfy(\.isHexDigit) else {
                throw Invalid(description: "invalid manifest entry: \(line)")
            }
            let path = String(fields[1])
            guard !path.hasPrefix("/"), !path.contains("..") else { throw Invalid(description: "invalid manifest entry: \(line)") }
            guard seen.insert(path).inserted else { throw Invalid(description: "duplicate manifest entry: \(path)") }
            entries.append(ManifestEntry(sha256: fields[0].lowercased(), path: path))
        }
        guard !entries.isEmpty else { throw Invalid(description: "empty manifest") }
        return entries
    }
}

/// What to fetch for one folder or file: pinned base URL, verified entries, where it goes.
public struct DownloadJob: Sendable {
    public enum Kind: Sendable {
        /// A model folder: `<destination>.part` → `<destination>` + `.complete`.
        case folder
        /// One file (the manifest's single entry): `<destination>.part` → `<destination>`.
        case file
    }

    public let name: String
    public let baseURL: URL
    public let entries: [ManifestEntry]
    public let destination: URL
    public let kind: Kind

    public init(name: String, baseURL: URL, entries: [ManifestEntry], destination: URL, kind: Kind) {
        self.name = name
        self.baseURL = baseURL
        self.entries = entries
        self.destination = destination
        self.kind = kind
    }

    /// Already on disk and every file matches its checksum (re-verified, as the script does).
    public var isInstalled: Bool {
        switch kind {
        case .file:
            return entries.count == 1 && ModelDownloader.sha256(of: destination) == entries[0].sha256
        case .folder:
            guard FileManager.default.fileExists(atPath: destination.appending(path: ".complete").path) else { return false }
            return entries.allSatisfy { ModelDownloader.sha256(of: destination.appending(path: $0.path)) == $0.sha256 }
        }
    }
}

/// Downloads pinned model files only when the user asks (`02-engines.md` §5): every file is
/// SHA-256-verified, nothing half-done is left behind, and a cancel removes the partial download.
public final class ModelDownloader: Sendable {
    public struct ChecksumMismatch: Error, CustomStringConvertible {
        public let description: String
    }

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Runs the jobs in order, skipping ones already installed. `progress` gets 0…1 over all of them.
    public func install(_ jobs: [DownloadJob], progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        let total = Double(jobs.reduce(0) { $0 + $1.entries.count })
        var done = 0.0
        for job in jobs {
            if job.isInstalled {
                done += Double(job.entries.count)
                progress(done / total)
                continue
            }
            let before = done
            try await run(job) { fraction in progress((before + fraction) / total) }
            done += Double(job.entries.count)
        }
        progress(1)
    }

    private func run(_ job: DownloadJob, progress: @escaping @Sendable (Double) -> Void) async throws {
        let fm = FileManager.default
        let part = job.destination.appendingPathExtension("part")
        try? fm.removeItem(at: part) // a previous attempt that was interrupted
        if job.kind == .folder { try fm.createDirectory(at: part, withIntermediateDirectories: true) }
        do {
            for (index, entry) in job.entries.enumerated() {
                try Task.checkCancellation()
                let target = job.kind == .folder ? part.appending(path: entry.path) : part
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                let (downloaded, response) = try await session.download(from: job.baseURL.appending(path: entry.path))
                guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else {
                    try? fm.removeItem(at: downloaded)
                    throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "\(entry.path): HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"])
                }
                try? fm.removeItem(at: target)
                try fm.moveItem(at: downloaded, to: target)
                guard Self.sha256(of: target) == entry.sha256 else {
                    throw ChecksumMismatch(description: "checksum mismatch for \(entry.path)")
                }
                progress(Double(index + 1) / Double(job.entries.count))
            }
            try Task.checkCancellation()
            if fm.fileExists(atPath: job.destination.path) {
                // An older or incomplete copy: swapped atomically, so a failure here keeps it.
                _ = try fm.replaceItemAt(job.destination, withItemAt: part)
            } else {
                try fm.moveItem(at: part, to: job.destination)
            }
            if job.kind == .folder { try Data().write(to: job.destination.appending(path: ".complete")) }
        } catch {
            try? fm.removeItem(at: part)
            throw error
        }
    }

    /// Streaming SHA-256 (models are gigabytes); nil when the file is missing.
    public static func sha256(of file: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        // The pool keeps multi-GB models from piling up 4 MB chunks until the loop ends.
        while let chunk = autoreleasepool(invoking: { try? handle.read(upToCount: 4 << 20) }), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Where each engine+model comes from: the same pinned repos and revisions as download-models.sh.
public enum ModelSources {
    private static let hf = URL(string: "https://huggingface.co")!

    /// The job that installs a meeting model.
    public static func job(for model: MeetingModel, manifests: URL, paths: Paths.Resolved = Paths.resolve()) throws -> DownloadJob {
        DownloadJob(name: model.title, baseURL: hf.appending(path: model.source),
                    entries: try Manifest.parse(String(contentsOf: manifests.appending(path: model.manifest), encoding: .utf8)),
                    destination: model.folder(paths: paths), kind: .folder)
    }

    /// The jobs that install `choice` (WhisperKit also needs its tokenizer, whisper.cpp the VAD model).
    /// `manifests` is the folder with the `*.sha256` files (bundled in the app). Empty for Apple.
    public static func jobs(for choice: EngineChoice, manifests: URL, paths: Paths.Resolved = Paths.resolve()) throws -> [DownloadJob] {
        let models = paths.modelsDir
        func manifest(_ name: String) throws -> [ManifestEntry] {
            try Manifest.parse(String(contentsOf: manifests.appending(path: name), encoding: .utf8))
        }
        func ggml(_ file: String, _ repo: String) throws -> DownloadJob {
            guard let entry = try manifest("ggml.sha256").first(where: { $0.path == file }) else {
                throw Manifest.Invalid(description: "no checksum for \(file)")
            }
            return DownloadJob(name: file, baseURL: hf.appending(path: "\(repo)/resolve/main"), entries: [entry],
                               destination: models.appending(path: file), kind: .file)
        }
        switch choice.engine {
        case .whispercpp:
            return [try ggml("ggml-\(choice.model).bin", "ggerganov/whisper.cpp"), try ggml("ggml-silero-v6.2.0.bin", "ggml-org/whisper-vad")]
        case .whisperkit:
            let remote = choice.model == "large-v3-turbo" ? "openai_whisper-large-v3-v20240930" : "openai_whisper-\(choice.model)"
            let needed = ["tokenizer.json", "tokenizer_config.json", "config.json"]
            let tokenizer = try manifest("whisperkit-tokenizer.sha256").filter { needed.contains($0.path) }
            guard tokenizer.count == needed.count else { throw Manifest.Invalid(description: "tokenizer manifest lacks \(needed)") }
            return [
                DownloadJob(name: "WhisperKit \(choice.model)",
                            baseURL: hf.appending(path: "argmaxinc/whisperkit-coreml/resolve/0f63a7800b00dd0226abd051b906c246e1907482/\(remote)"),
                            entries: try manifest("whisperkit-\(choice.model).sha256"),
                            destination: models.appending(path: "whisperkit/\(choice.model)", directoryHint: .isDirectory), kind: .folder),
                DownloadJob(name: "WhisperKit tokenizer",
                            baseURL: hf.appending(path: "openai/whisper-large-v3/resolve/06f233fe06e710322aca913c1bc4249a0d71fce1"),
                            entries: tokenizer, destination: models.appending(path: "whisperkit/tokenizer", directoryHint: .isDirectory), kind: .folder),
            ]
        case .parakeet:
            return [DownloadJob(name: "Parakeet",
                                baseURL: hf.appending(path: "FluidInference/parakeet-tdt-0.6b-v3-coreml/resolve/7dd20fe6b1797d35f5e3307e8b1732d9a178edfe"),
                                entries: try manifest("\(choice.model).sha256"),
                                destination: models.appending(path: "parakeet/\(choice.model)", directoryHint: .isDirectory), kind: .folder)]
        case .apple:
            return []
        }
    }
}
