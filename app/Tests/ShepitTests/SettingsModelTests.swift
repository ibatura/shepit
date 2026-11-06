import Foundation
import SwiftUI
import Testing
@testable import Shepit
import ShepitCore

@MainActor
struct SettingsModelTests {
    private func makeFile(_ contents: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appending(path: "settings.json")
        try contents.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    private func json(_ file: URL) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    }

    @Test func aControlChangeWritesExactlyThatKey() throws {
        let file = try makeFile(#"{"mode":"hold","serverPort":8178,"unknown":{"keep":1}}"#)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = SettingsStore(file: file)
        store.load()
        let model = SettingsModel(store: store, dictionaryStore: DictionaryStore(file: file.deletingLastPathComponent().appending(path: "dictionary.json")))
        var applied = 0
        model.onChange = { applied += 1 }
        model.set("sounds", false)
        let raw = try json(file)
        #expect(Set(raw.keys) == ["mode", "serverPort", "unknown", "sounds"])
        #expect(raw["sounds"] as? Bool == false && raw["mode"] as? String == "hold")
        #expect(model.settings.sounds == false)
        #expect(applied == 1)
    }

    @Test func hotkeysAreWrittenInTheFileFormat() throws {
        let file = try makeFile("{}")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = SettingsStore(file: file)
        store.load()
        let model = SettingsModel(store: store, dictionaryStore: DictionaryStore(file: file.deletingLastPathComponent().appending(path: "dictionary.json")))
        model.set("hotkey", hotkey: Hotkey(mods: ["cmd", "shift"], key: "d"))
        #expect(try json(file)["hotkey"] as? [String: AnyHashable] == ["mods": ["cmd", "shift"], "key": "d"])
        #expect(model.settings.hotkey == Hotkey(mods: ["cmd", "shift"], key: "d"))
    }

    @Test func aBrokenFileMakesEverythingReadOnly() throws {
        let file = try makeFile(#"{"mode":"hold"}"#)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = SettingsStore(file: file)
        store.load()
        let model = SettingsModel(store: store, dictionaryStore: DictionaryStore(file: file.deletingLastPathComponent().appending(path: "dictionary.json")))
        try Data("{".utf8).write(to: file)
        store.load()
        model.refresh()
        #expect(model.isReadOnly)
        #expect(model.errors == ["settings.json: parse error at line 1"])
        model.set("mode", "toggle")
        #expect(String(data: try Data(contentsOf: file), encoding: .utf8) == "{")
    }

    @Test func anInvalidValueIsRefusedAndShown() throws {
        let file = try makeFile("{}")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = SettingsStore(file: file)
        store.load()
        let model = SettingsModel(store: store, dictionaryStore: DictionaryStore(file: file.deletingLastPathComponent().appending(path: "dictionary.json")))
        model.set("typingSpeedWpm", 500)
        #expect(model.lastError?.contains("typingSpeedWpm") == true)
        #expect(try json(file).isEmpty)
    }

    @Test func handEditsReachAnOpenWindow() throws {
        let file = try makeFile(#"{"mode":"toggle"}"#)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = SettingsStore(file: file)
        store.load()
        let model = SettingsModel(store: store, dictionaryStore: DictionaryStore(file: file.deletingLastPathComponent().appending(path: "dictionary.json")))
        try #"{"mode":"hold"}"#.write(to: file, atomically: true, encoding: .utf8)
        store.load()
        model.refresh()
        #expect(model.settings.mode == "hold")
    }

    @Test func theUsersRealFileRoundTripsWithoutLosingKeys() throws {
        guard let original = try? Data(contentsOf: Paths.settingsFile) else { return } // no real file on this machine
        let file = try makeFile(String(decoding: original, as: UTF8.self))
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = SettingsStore(file: file)
        #expect(store.load())
        let before = try json(file)
        SettingsModel(store: store, dictionaryStore: DictionaryStore(file: file.deletingLastPathComponent().appending(path: "dictionary.json"))).set("sounds", !(before["sounds"] as? Bool ?? true))
        let after = try json(file)
        #expect(Set(after.keys) == Set(before.keys).union(["sounds"]))
        for key in before.keys where key != "sounds" {
            #expect((after[key] as? NSObject)?.isEqual(before[key]) == true, "\(key) changed")
        }
    }

    @Test func aStyleChangeKeepsTheOtherStyleFields() throws {
        let file = try makeFile(#"{"overlayStyle":{"width":700,"custom":1}}"#)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = SettingsStore(file: file)
        store.load()
        let model = SettingsModel(store: store, dictionaryStore: DictionaryStore(file: file.deletingLastPathComponent().appending(path: "dictionary.json")))
        model.setStyle("bars", 12)
        #expect(try json(file)["overlayStyle"] as? [String: Int] == ["width": 700, "custom": 1, "bars": 12])
        #expect(model.settings.overlayStyle.bars == 12 && model.settings.overlayStyle.width == 700)
    }

    private func dictionaryModel(_ contents: String) throws -> (SettingsModel, URL) {
        let file = try makeFile("{}")
        let dictionary = file.deletingLastPathComponent().appending(path: "dictionary.json")
        try contents.write(to: dictionary, atomically: true, encoding: .utf8)
        let store = SettingsStore(file: file)
        store.load()
        let dictionaryStore = DictionaryStore(file: dictionary)
        dictionaryStore.load()
        return (SettingsModel(store: store, dictionaryStore: dictionaryStore), dictionary)
    }

    @Test func reorderingTermsWritesTheNewOrderAndKeepsTheRest() throws {
        let (model, file) = try dictionaryModel(#"{"terms":["A","B","C"],"replace":{"x":"y"},"note":1}"#)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        var terms = model.dictionary.terms
        terms.move(fromOffsets: [2], toOffset: 0)
        model.setTerms(terms)
        let raw = try json(file)
        #expect(raw["terms"] as? [String] == ["C", "A", "B"])
        #expect(raw["replace"] as? [String: String] == ["x": "y"] && raw["note"] as? Int == 1)
    }

    @Test func anEmptyRuleIsRefusedAndTheFileIsUnchanged() throws {
        let (model, file) = try dictionaryModel(#"{"replace":{"x":"y"}}"#)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let before = try Data(contentsOf: file)
        model.setRule(wrong: "кубер", right: "  ")
        #expect(model.lastError != nil)
        #expect(try Data(contentsOf: file) == before)
    }

    @Test func editingARuleReplacesItsOldSpelling() throws {
        let (model, file) = try dictionaryModel(#"{"replace":{"кубер":"Kuber"}}"#)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        model.setRule(wrong: "Кубернетіс", right: "Kubernetes", replacing: "кубер")
        #expect(try json(file)["replace"] as? [String: String] == ["кубернетіс": "Kubernetes"])
        model.removeRule("кубернетіс")
        #expect(try json(file)["replace"] as? [String: String] == [:])
    }

    @Test func aBrokenDictionaryIsReadOnly() throws {
        let (model, file) = try dictionaryModel(#"{"terms":"oops"}"#)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        #expect(model.dictionaryIsReadOnly)
        model.setTerms(["A"])
        #expect(String(data: try Data(contentsOf: file), encoding: .utf8) == #"{"terms":"oops"}"#)
    }

    @Test func colorsRoundTripThroughHex() {
        #expect(Color(hex: "#FF4D4D").hex(alpha: false) == "#FF4D4D")
        #expect(Color(hex: "#141414").hex(alpha: false) == "#141414")
        #expect(Color(hex: "#FF4D4D80").hex(alpha: true) == "#FF4D4D80")
    }

    @Test func choosingAnEngineWritesAllTasksAndDropsLegacyKeys() throws {
        let file = try makeFile(#"{"model":"large-v3","previewModel":"large-v3-turbo","sounds":false}"#)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = SettingsStore(file: file)
        store.load()
        let model = SettingsModel(store: store, dictionaryStore: DictionaryStore(file: file.deletingLastPathComponent().appending(path: "dictionary.json")))
        model.setEngine(.meetings, EngineChoice(engine: .parakeet, model: "parakeet-tdt-0.6b-v3"))
        let raw = try json(file)
        #expect(raw["model"] == nil && raw["previewModel"] == nil && raw["sounds"] as? Bool == false)
        #expect(raw["engines"] as? [String: [String: String]] == [
            "dictation": ["engine": "whispercpp", "model": "large-v3"],
            "preview": ["engine": "whispercpp", "model": "large-v3-turbo"],
            "meetings": ["engine": "parakeet", "model": "parakeet-tdt-0.6b-v3"],
        ])
    }

    @Test func meetingKeysAreInTheMeetingsSection() {
        #expect(SettingsModel.Section.meetings.keys == ["meetingsFolder", "meetingFileName", "meetingAskTitle", "meetingMyName", "meetingLanguage", "meetingBlocksDictation"])
    }

    @Test func serverPortIsShownNowhere() {
        #expect(!SettingsModel.Section.allCases.flatMap(\.keys).contains("serverPort"))
    }
}
