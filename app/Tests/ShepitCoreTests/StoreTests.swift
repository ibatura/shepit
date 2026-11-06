import Foundation
import Testing
@testable import ShepitCore

struct StoreTests {
    @Test func missingSettingsFileLoadsDefaults() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SettingsStore(file: directory.appending(path: "settings.json"))

        #expect(store.load())
        #expect(store.errors.isEmpty)
        #expect(store.settings.mode == "toggle")
    }

    @Test func validSettingsLoadAndUnknownKeysArePreservedOnUpdate() throws {
        let (directory, file) = try makeSettingsFile(#"{"mode":"hold","unknown":{"keep":true}}"#)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SettingsStore(file: file)

        #expect(store.load())
        #expect(store.settings.mode == "hold")
        try store.update("sounds", false)

        let written = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        #expect(written["mode"] as? String == "hold")
        #expect((written["unknown"] as? [String: Any])?["keep"] as? Bool == true)
        #expect(written["sounds"] as? Bool == false)
        #expect(!FileManager.default.fileExists(atPath: file.path + ".tmp"))
    }

    @Test func anUpdateKeepsAHandEditMadeSinceTheLastLoad() throws {
        let (directory, file) = try makeSettingsFile(#"{"mode":"hold"}"#)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SettingsStore(file: file)
        #expect(store.load())
        try #"{"mode":"hold","language":"en","url":"https://x/y"}"#.write(to: file, atomically: true, encoding: .utf8)
        try store.update("sounds", false)
        let text = try String(contentsOf: file, encoding: .utf8)
        let written = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(written["language"] as? String == "en")
        #expect(text.contains("https://x/y")) // slashes stay readable
    }

    @Test func invalidJSONKeepsLastGoodSettingsAndRefusesUpdate() throws {
        let (directory, file) = try makeSettingsFile(#"{"mode":"hold"}"#)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SettingsStore(file: file)
        #expect(store.load())

        try Data("{".utf8).write(to: file)
        #expect(!store.load())
        #expect(store.settings.mode == "hold")
        #expect(store.errors == ["settings.json: parse error at line 1"])
        #expect(throws: SettingsStoreError.self) {
            try store.update("mode", "toggle")
        }
        #expect(String(data: try Data(contentsOf: file), encoding: .utf8) == "{")
    }

    @Test func nonObjectJSONKeepsLastGoodSettingsAndRefusesUpdate() throws {
        let (directory, file) = try makeSettingsFile(#"{"mode":"hold"}"#)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SettingsStore(file: file)
        #expect(store.load())

        try #"["a", "b"]"#.write(to: file, atomically: true, encoding: .utf8)
        #expect(!store.load())
        #expect(store.settings.mode == "hold")
        #expect(store.errors == ["settings.json: file must contain JSON object"])
    }

    @Test func invalidValuesKeepLastGoodSettingsAndRefuseUpdate() throws {
        let (directory, file) = try makeSettingsFile(#"{"mode":"hold"}"#)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SettingsStore(file: file)
        #expect(store.load())

        try #"{"mode":"invalid"}"#.write(to: file, atomically: true, encoding: .utf8)
        #expect(!store.load())
        #expect(store.settings.mode == "hold")
        #expect(store.errors == [#"settings.json: "mode" must be one of: toggle, hold"#])
        #expect(throws: SettingsStoreError.self) {
            try store.update("mode", "toggle")
        }
    }

    @Test func updateCreatesSettingsFileAndRejectsInvalidValueWithoutWriting() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "settings.json")
        let store = SettingsStore(file: file)
        #expect(store.load())

        #expect(throws: SettingsStoreError.self) {
            try store.update("mode", "push")
        }
        #expect(!FileManager.default.fileExists(atPath: file.path))

        try store.update("mode", "hold")
        #expect(store.settings.mode == "hold")
        let written = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        #expect(written.count == 1)
        #expect(written["mode"] as? String == "hold")
    }

    @Test func updateRemovesLegacyKeysWhenWritingEngines() throws {
        let (directory, file) = try makeSettingsFile(#"{"model":"large-v3-turbo","previewModel":"large-v3"}"#)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SettingsStore(file: file)
        #expect(store.load())

        let engines: [String: Any] = [
            "dictation": ["engine": "whisperkit", "model": "large-v3"],
            "preview": ["engine": "whispercpp", "model": "large-v3"],
            "meetings": ["engine": "whispercpp", "model": "large-v3"]
        ]
        try store.update("engines", engines)

        let written = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        #expect(written["engines"] != nil)
        #expect(written["model"] == nil)
        #expect(written["previewModel"] == nil)
    }

    @Test func updateFailureDoesNotChangeInMemorySettingsOrOriginalFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "settings.json")
        try #"{"mode":"hold"}"#.write(to: file, atomically: true, encoding: .utf8)
        let store = SettingsStore(file: file)
        #expect(store.load())

        let movedDirectory = directory.deletingLastPathComponent().appending(path: "moved-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.moveItem(at: directory, to: movedDirectory)
        defer { try? FileManager.default.removeItem(at: movedDirectory) }

        #expect(throws: SettingsStoreError.self) {
            try store.update("mode", "toggle")
        }
        #expect(store.settings.mode == "hold")
        let preservedFile = movedDirectory.appending(path: "settings.json")
        #expect(String(data: try Data(contentsOf: preservedFile), encoding: .utf8) == #"{"mode":"hold"}"#)
        let remainingFiles = try FileManager.default.contentsOfDirectory(atPath: movedDirectory.path)
        #expect(!remainingFiles.contains { $0.hasSuffix(".tmp") })
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeSettingsFile(_ contents: String) throws -> (URL, URL) {
        let directory = try makeTemporaryDirectory()
        let file = directory.appending(path: "settings.json")
        try contents.write(to: file, atomically: true, encoding: .utf8)
        return (directory, file)
    }
}
