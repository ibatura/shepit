import CryptoKit
import Foundation
import Testing
@testable import ShepitCore

/// Serves files from memory instead of the network and records what was asked for.
private final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var files: [String: Data] = [:]
    nonisolated(unsafe) static var requests: [String] = []
    nonisolated(unsafe) static var delaySeconds = 0.0
    nonisolated(unsafe) static var slowPath = ""
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url!.path
        let data = Self.lock.withLock {
            Self.requests.append(path)
            return Self.files[path]
        }
        let respond = { [self] in
            let response = HTTPURLResponse(url: request.url!, statusCode: data == nil ? 404 : 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data ?? Data())
            client?.urlProtocolDidFinishLoading(self)
        }
        let delay = Self.lock.withLock { Self.slowPath.isEmpty || path.hasSuffix(Self.slowPath) ? Self.delaySeconds : 0 }
        if delay == 0 { respond() } else { DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: respond) }
    }

    override func stopLoading() {}
}

private final class Reported: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []
    func add(_ value: Double) { lock.withLock { values.append(value) } }
    var last: Double? { lock.withLock { values.last } }
}

private func sha(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

@Suite(.serialized)
struct ModelDownloaderTests {
    private let base = URL(string: "https://huggingface.co/repo/resolve/rev/dir")!
    private let downloader: ModelDownloader = {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return ModelDownloader(session: URLSession(configuration: config))
    }()

    private func reset(_ files: [String: Data]) -> URL {
        StubProtocol.lock.withLock {
            StubProtocol.files = Dictionary(uniqueKeysWithValues: files.map { ("/repo/resolve/rev/dir/\($0.key)", $0.value) })
            StubProtocol.requests = []
            StubProtocol.delaySeconds = 0
            StubProtocol.slowPath = ""
        }
        return FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }

    private var requestCount: Int { StubProtocol.lock.withLock { StubProtocol.requests.count } }

    private func folderJob(_ dir: URL, _ entries: [ManifestEntry]) -> DownloadJob {
        DownloadJob(name: "m", baseURL: base, entries: entries, destination: dir.appending(path: "model", directoryHint: .isDirectory), kind: .folder)
    }

    @Test func malformedOrDuplicateManifestRowsFailBeforeAnyDownload() throws {
        let good = String(repeating: "a", count: 64)
        #expect(throws: Manifest.Invalid.self) { try Manifest.parse("\(good)  a.bin\nzz  b.bin") }
        #expect(throws: Manifest.Invalid(description: "duplicate manifest entry: a.bin")) { try Manifest.parse("\(good)  a.bin\n\(good)  a.bin") }
        #expect(throws: Manifest.Invalid.self) { try Manifest.parse("\(good)  ../escape") }
        #expect(throws: Manifest.Invalid.self) { try Manifest.parse("\n  \n") }
        #expect(try Manifest.parse("\(good)  a.bin\n\n\(good)\tsub/b.bin\n").map(\.path) == ["a.bin", "sub/b.bin"])
    }

    @Test func aFolderIsDownloadedVerifiedRenamedAndMarkedComplete() async throws {
        let a = Data("weights".utf8), b = Data("config".utf8)
        let dir = reset(["a.bin": a, "sub/b.json": b])
        defer { try? FileManager.default.removeItem(at: dir) }
        let job = folderJob(dir, [ManifestEntry(sha256: sha(a), path: "a.bin"), ManifestEntry(sha256: sha(b), path: "sub/b.json")])
        try await downloader.install([job])
        #expect(try Data(contentsOf: job.destination.appending(path: "sub/b.json")) == b)
        #expect(FileManager.default.fileExists(atPath: job.destination.appending(path: ".complete").path))
        #expect(!FileManager.default.fileExists(atPath: job.destination.path + ".part"))
        #expect(job.isInstalled)
    }

    @Test func aChecksumMismatchLeavesNothingBehind() async throws {
        let dir = reset(["a.bin": Data("tampered".utf8)])
        defer { try? FileManager.default.removeItem(at: dir) }
        let job = folderJob(dir, [ManifestEntry(sha256: sha(Data("expected".utf8)), path: "a.bin")])
        await #expect(throws: ModelDownloader.ChecksumMismatch.self) { try await downloader.install([job]) }
        #expect(!FileManager.default.fileExists(atPath: job.destination.path))
        #expect(!FileManager.default.fileExists(atPath: job.destination.path + ".part"))
    }

    @Test func aMissingFileOnTheServerFails() async throws {
        let dir = reset([:])
        defer { try? FileManager.default.removeItem(at: dir) }
        let job = folderJob(dir, [ManifestEntry(sha256: sha(Data()), path: "a.bin")])
        await #expect(throws: URLError.self) { try await downloader.install([job]) }
        #expect(!FileManager.default.fileExists(atPath: job.destination.path + ".part"))
    }

    @Test func anInstalledFolderIsReverifiedAndOnlyRedownloadedWhenBroken() async throws {
        let a = Data("weights".utf8)
        let dir = reset(["a.bin": a])
        defer { try? FileManager.default.removeItem(at: dir) }
        let job = folderJob(dir, [ManifestEntry(sha256: sha(a), path: "a.bin")])
        try await downloader.install([job])
        try await downloader.install([job])
        #expect(requestCount == 1)
        try Data("corrupt".utf8).write(to: job.destination.appending(path: "a.bin"))
        #expect(!job.isInstalled)
        try await downloader.install([job])
        #expect(requestCount == 2)
        #expect(try Data(contentsOf: job.destination.appending(path: "a.bin")) == a)
    }

    @Test func aSingleFileJob() async throws {
        let model = Data("ggml".utf8)
        let dir = reset(["ggml-x.bin": model])
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let job = DownloadJob(name: "x", baseURL: base, entries: [ManifestEntry(sha256: sha(model), path: "ggml-x.bin")],
                              destination: dir.appending(path: "ggml-x.bin"), kind: .file)
        let reported = Reported()
        try await downloader.install([job]) { reported.add($0) }
        #expect(try Data(contentsOf: job.destination) == model)
        #expect(reported.last == 1)
    }

    @Test func cancellingLeavesNoFolder() async throws {
        let a = Data("weights".utf8)
        let dir = reset(["a.bin": a, "b.bin": a])
        StubProtocol.lock.withLock {
            StubProtocol.delaySeconds = 2
            StubProtocol.slowPath = "b.bin"
        }
        defer { try? FileManager.default.removeItem(at: dir) }
        let job = folderJob(dir, [ManifestEntry(sha256: sha(a), path: "a.bin"), ManifestEntry(sha256: sha(a), path: "b.bin")])
        let task = Task { try await downloader.install([job]) }
        let firstFile = job.destination.appendingPathExtension("part").appending(path: "a.bin")
        for _ in 0..<200 where !FileManager.default.fileExists(atPath: firstFile.path) {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(FileManager.default.fileExists(atPath: firstFile.path)) // cancelled mid-download, not before it
        task.cancel()
        _ = await task.result
        #expect(!FileManager.default.fileExists(atPath: job.destination.path))
        #expect(!FileManager.default.fileExists(atPath: job.destination.path + ".part"))
    }

    @Test func sourcesUseThePinnedManifests() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let manifests = repoRoot.appending(path: "scripts/models")
        let paths = Paths.resolve(environment: ["DICTATION_HOME": "/tmp/h"])
        // Every repo/revision the app uses is the one download-models.sh pins.
        let script = try String(contentsOf: repoRoot.appending(path: "scripts/download-models.sh"), encoding: .utf8)
        for choice in [EngineChoice(engine: .whispercpp, model: "large-v3"), EngineChoice(engine: .whisperkit, model: "large-v3"),
                       EngineChoice(engine: .parakeet, model: "parakeet-tdt-0.6b-v3")] {
            for job in try ModelSources.jobs(for: choice, manifests: manifests, paths: paths) {
                let parts = job.baseURL.path.split(separator: "/").map(String.init) // repo owner, name, "resolve", revision, [dir]
                #expect(script.contains("\(parts[0])/\(parts[1])"), "\(job.name): repo not in the script")
                #expect(parts[3] == "main" || script.contains(parts[3]), "\(job.name): revision not in the script")
                if parts.count > 4 { #expect(script.contains(parts[4]), "\(job.name): remote dir not in the script") }
            }
        }
        let cpp = try ModelSources.jobs(for: EngineChoice(engine: .whispercpp, model: "large-v3-turbo"), manifests: manifests, paths: paths)
        #expect(cpp.map(\.destination.lastPathComponent) == ["ggml-large-v3-turbo.bin", "ggml-silero-v6.2.0.bin"])
        #expect(cpp[0].entries.first?.sha256 == "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69")
        let kit = try ModelSources.jobs(for: EngineChoice(engine: .whisperkit, model: "large-v3-turbo"), manifests: manifests, paths: paths)
        #expect(kit[0].baseURL.path.hasSuffix("openai_whisper-large-v3-v20240930"))
        #expect(kit[1].entries.map(\.path).sorted() == ["config.json", "tokenizer.json", "tokenizer_config.json"])
        let parakeet = try ModelSources.jobs(for: EngineChoice(engine: .parakeet, model: "parakeet-tdt-0.6b-v3"), manifests: manifests, paths: paths)
        #expect(parakeet[0].entries.count == 20)
        #expect(try ModelSources.jobs(for: EngineChoice(engine: .apple, model: ""), manifests: manifests).isEmpty)
    }

    @Test func meetingModelsUseThePinnedManifests() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let manifests = repoRoot.appending(path: "scripts/models")
        let paths = Paths.resolve(environment: ["DICTATION_HOME": "/tmp/h"])
        let script = try String(contentsOf: repoRoot.appending(path: "scripts/download-models.sh"), encoding: .utf8)
        for model in MeetingModel.allCases {
            let job = try ModelSources.job(for: model, manifests: manifests, paths: paths)
            let parts = job.baseURL.path.split(separator: "/").map(String.init)
            #expect(script.contains("\(parts[0])/\(parts[1]) \(parts[3])"), "\(job.name): repo and revision not in the script")
            #expect(script.contains("\"$DIR/\(model.rawValue)\""), "\(job.name): folder differs from the script")
            #expect(job.destination == model.folder(paths: paths))
            #expect(job.kind == .folder)
        }
        let vad = try ModelSources.job(for: .vad, manifests: manifests, paths: paths)
        #expect(vad.entries.contains { $0.path == "silero-vad-unified-256ms-v6.2.1.mlmodelc/weights/weight.bin" })
        let diarization = try ModelSources.job(for: .diarization, manifests: manifests, paths: paths)
        for model in ["Segmentation", "FBank", "Embedding", "PldaRho"] {
            #expect(diarization.entries.contains { $0.path == "\(model).mlmodelc/coremldata.bin" }, "\(model)")
        }
        #expect(diarization.entries.contains { $0.path == "plda-parameters.json" })
    }

    @Test func meetingModelIsDownloadedOnlyWithItsCompleteMarker() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = Paths.resolve(environment: ["DICTATION_HOME": home.path])
        try FileManager.default.createDirectory(at: MeetingModel.vad.folder(paths: paths), withIntermediateDirectories: true)
        #expect(!MeetingModel.vad.isDownloaded(paths: paths))
        try Data().write(to: MeetingModel.vad.folder(paths: paths).appending(path: ".complete"))
        #expect(MeetingModel.vad.isDownloaded(paths: paths))
        #expect(!MeetingModel.diarization.isDownloaded(paths: paths))
    }
}
