import Foundation
import Testing
@testable import ShepitCore

// Dictionary-store cases ported from tests/test_config.lua.
struct DictionaryStoreTests {
    private func makeStore(_ contents: String?) throws -> (DictionaryStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "dictionary.json")
        if let contents { try contents.write(to: file, atomically: true, encoding: .utf8) }
        return (DictionaryStore(file: file), file)
    }

    private func written(_ file: URL) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    }

    @Test func loadUsesDefaultsWhenFileIsMissing() throws {
        let (store, file) = try makeStore(nil)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        #expect(store.load())
        #expect(store.errors.isEmpty)
        #expect(store.dictionary == .empty)
    }

    @Test func keepsLastGoodDictionaryWhenFileBecomesInvalid() throws {
        let (store, file) = try makeStore(#"{"terms":["A"]}"#)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        #expect(store.load())
        try #"{"terms":"oops"}"#.write(to: file, atomically: true, encoding: .utf8)
        #expect(!store.load())
        #expect(store.dictionary.terms == ["A"])
        #expect(store.errors == [#"dictionary.json: "terms" must be a list of strings"#])

        try Data("{".utf8).write(to: file)
        #expect(!store.load())
        #expect(store.errors == ["dictionary.json: parse error at line 1"])
        #expect(store.dictionary.terms == ["A"])
    }

    @Test func addRuleWritesReplaceAndTermAndKeepsTheRest() throws {
        let (store, file) = try makeStore(#"{"terms":["A"],"replace":{"x":"y"},"dropPhrases":["z"],"unknown":1}"#)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        store.load()
        try store.addRule(wrong: "кубернетіс", right: "Kubernetes")
        let raw = try written(file)
        #expect(raw["terms"] as? [String] == ["A", "Kubernetes"])
        #expect(raw["replace"] as? [String: String] == ["x": "y", "кубернетіс": "Kubernetes"])
        #expect(raw["dropPhrases"] as? [String] == ["z"])
        #expect(raw["unknown"] as? Int == 1)
        #expect(store.dictionary.replace["кубернетіс"] == "Kubernetes")
    }

    @Test func addRuleTrimsLowercasesTheKeyAndDoesNotDuplicateTerms() throws {
        let (store, file) = try makeStore(#"{"terms":["Kubernetes"]}"#)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        store.load()
        try store.addRule(wrong: "  Кубернетіс ", right: " Kubernetes ")
        let raw = try written(file)
        #expect(raw["terms"] as? [String] == ["Kubernetes"])
        #expect(raw["replace"] as? [String: String] == ["кубернетіс": "Kubernetes"])
    }

    @Test func addRuleReplacesAnExistingRuleForTheSameWord() throws {
        let (store, file) = try makeStore(#"{"replace":{"кубер":"Old"}}"#)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        store.load()
        try store.addRule(wrong: "КУБЕР", right: "Kuber")
        #expect(try written(file)["replace"] as? [String: String] == ["кубер": "Kuber"])
    }

    @Test func addRuleWithNoWrongSpellingOnlyAddsATerm() throws {
        let (store, file) = try makeStore(nil)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        store.load()
        try store.addRule(wrong: "", right: "Jira")
        let raw = try written(file)
        #expect(raw["terms"] as? [String] == ["Jira"])
        #expect(raw["replace"] == nil)
    }

    @Test func addRuleRejectsEmptyInputAndABrokenFile() throws {
        let (store, file) = try makeStore(#"{"terms":[]}"#)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        store.load()
        #expect(throws: DictionaryStoreError.emptyRight) { try store.addRule(wrong: "x", right: "  ") }
        try Data("Unexpected token".utf8).write(to: file)
        store.load()
        #expect(throws: DictionaryStoreError.brokenDictionary) { try store.addRule(wrong: "x", right: "y") }
        #expect(String(data: try Data(contentsOf: file), encoding: .utf8) == "Unexpected token")
    }

    @Test func ruleForFindsAnExistingRuleCaseInsensitively() throws {
        let (store, file) = try makeStore(#"{"replace":{"кубернетіс":"Kubernetes"}}"#)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        store.load()
        #expect(store.ruleFor("Кубернетіс") == "Kubernetes")
        #expect(store.ruleFor("інше") == nil)
    }

    @Test func realDictionaryFilesLoad() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for file in [repoRoot.appending(path: "examples/dictionary.json"), Paths.dictionaryFile]
        where FileManager.default.fileExists(atPath: file.path) {
            let store = DictionaryStore(file: file)
            #expect(store.load(), "\(file.path): \(store.errors)")
        }
    }
}
