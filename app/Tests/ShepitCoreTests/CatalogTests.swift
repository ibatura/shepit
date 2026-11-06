import Foundation
import Testing
@testable import ShepitCore

struct CatalogTests {
    @Test func catalogPathsResolveModelAndVADAssetsFromDictationHome() {
        let paths = Paths.resolve(environment: ["DICTATION_HOME": "/tmp/h"])
        let choice = EngineChoice(engine: .whisperkit, model: "large-v3")

        #expect(ModelCatalog.folder(for: choice, paths: paths)?.path == "/tmp/h/.local/share/dictation/models/whisperkit/large-v3")
        #expect(ModelCatalog.tokenizerFolder(paths: paths)?.path == "/tmp/h/.local/share/dictation/models/whisperkit/tokenizer")
        #expect(ModelCatalog.folder(for: EngineChoice(engine: .apple, model: ""), paths: paths) == nil)
        #expect(ModelCatalog.vadModel.path == Paths.modelsDir.appending(path: "ggml-silero-v6.2.0.bin").path)
    }

    @Test func whisperCppNeedsTheVADModelToCountAsDownloaded() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = Paths.resolve(environment: ["DICTATION_HOME": home.path])
        let ggml = EngineChoice(engine: .whispercpp, model: "large-v3")
        try FileManager.default.createDirectory(at: paths.modelsDir, withIntermediateDirectories: true)
        try Data().write(to: try #require(ModelCatalog.folder(for: ggml, paths: paths)))
        #expect(!ModelCatalog.isDownloaded(ggml, paths: paths))
        try Data().write(to: paths.modelsDir.appending(path: "ggml-silero-v6.2.0.bin"))
        #expect(ModelCatalog.isDownloaded(ggml, paths: paths))
    }

    @Test func sizeOnDiskForFilesAndFolders() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = Paths.resolve(environment: ["DICTATION_HOME": home.path])
        let ggml = EngineChoice(engine: .whispercpp, model: "large-v3-turbo")
        let kit = EngineChoice(engine: .whisperkit, model: "large-v3")
        #expect(ModelCatalog.sizeOnDisk(ggml, paths: paths) == nil)
        try FileManager.default.createDirectory(at: paths.modelsDir, withIntermediateDirectories: true)
        try Data(count: 1000).write(to: try #require(ModelCatalog.folder(for: ggml, paths: paths)))
        #expect(ModelCatalog.sizeOnDisk(ggml, paths: paths) == 1000)
        let folder = try #require(ModelCatalog.folder(for: kit, paths: paths))
        try FileManager.default.createDirectory(at: folder.appending(path: "Model.mlmodelc"), withIntermediateDirectories: true)
        try Data(count: 300).write(to: folder.appending(path: "Model.mlmodelc/weights.bin"))
        try Data(count: 20).write(to: folder.appending(path: "config.json"))
        #expect(ModelCatalog.sizeOnDisk(kit, paths: paths) == 320)
        #expect(ModelCatalog.sizeOnDisk(EngineChoice(engine: .apple, model: ""), paths: paths) == nil)
    }

    @Test func partialModelFolderIsNotDownloadedUntilCompleteMarkerExists() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = Paths.resolve(environment: ["DICTATION_HOME": home.path])
        let choice = EngineChoice(engine: .whisperkit, model: "large-v3")
        let modelFolder = try #require(ModelCatalog.folder(for: choice, paths: paths))
        try FileManager.default.createDirectory(at: modelFolder, withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: modelFolder.appending(path: "weights.bin"))

        #expect(!ModelCatalog.isDownloaded(choice, paths: paths))
        try Data().write(to: modelFolder.appending(path: ".complete"))
        let tokenizerFolder = try #require(ModelCatalog.tokenizerFolder(paths: paths))
        try FileManager.default.createDirectory(at: tokenizerFolder, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: tokenizerFolder.appending(path: "config.json"))
        try Data("{}".utf8).write(to: tokenizerFolder.appending(path: "tokenizer.json"))
        try Data("{}".utf8).write(to: tokenizerFolder.appending(path: "tokenizer_config.json"))
        try Data().write(to: tokenizerFolder.appending(path: ".complete"))
        #expect(ModelCatalog.isDownloaded(choice, paths: paths))
    }
}
