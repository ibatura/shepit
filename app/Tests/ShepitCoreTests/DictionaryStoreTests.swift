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

    // The window's changes (Dictations and Dictionary design §6).

    @Test func aChangeWorksOnTheFileAsItIsNowAndWritesOnlyWhatChanged() throws {
        let (store, file) = try makeStore(#"{"terms":["A"],"note":1}"#)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        store.load()
        try #"{"terms":["A","B"],"note":1}"#.write(to: file, atomically: true, encoding: .utf8) // by hand, before the next poll
        try store.change { $0.add(term: "C") }
        let raw = try written(file)
        #expect(raw["terms"] as? [String] == ["A", "B", "C"])
        #expect(raw["note"] as? Int == 1 && raw["replace"] == nil && raw["dropPhrases"] == nil)
        #expect(store.dictionary.terms == ["A", "B", "C"])
    }

    @Test func termsAndPhrasesAreAddedOnceAndATermMovesOntoAnother() throws {
        var dictionary = DictionaryFile(terms: ["A", "B", "C"], replace: [:], dropPhrases: ["x"])
        dictionary.add(term: "B")
        dictionary.add(dropPhrase: "x")
        dictionary.add(dropPhrase: "y")
        #expect(dictionary.terms == ["A", "B", "C"] && dictionary.dropPhrases == ["x", "y"])
        dictionary.move(term: "C", to: "A")
        #expect(dictionary.terms == ["C", "A", "B"])
        dictionary.move(term: "C", to: "B")
        #expect(dictionary.terms == ["A", "B", "C"])
        dictionary.move(term: "elsewhere", to: "A")
        #expect(dictionary.terms == ["A", "B", "C"])
    }

    @Test func aRuleNeedsBothSidesAndAHeardPhraseNoOtherRuleHas() throws {
        let (store, file) = try makeStore(#"{"replace":{"кубер":"Kuber","шепіт":"Shepit"}}"#)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        store.load()
        let before = try Data(contentsOf: file)
        #expect(throws: DictionaryStoreError.emptyRule) { try store.change { try $0.setRule(heard: "кубер", written: "  ", replacing: "кубер") } }
        #expect(throws: DictionaryStoreError.ruleExists("Шепіт")) {
            try store.change { try $0.setRule(heard: "Шепіт", written: "Kubernetes", replacing: "кубер") }
        }
        #expect(throws: DictionaryStoreError.ruleExists("шепіт")) { try store.change { try $0.setRule(heard: "шепіт", written: "x") } }
        #expect(try Data(contentsOf: file) == before)
        try store.change { try $0.setRule(heard: " Кубернетіс ", written: "Kubernetes", replacing: "кубер") }
        try store.change { try $0.setRule(heard: "шепіт", written: "Shepit app", replacing: "шепіт") } // its own rule
        #expect(try written(file)["replace"] as? [String: String] == ["кубернетіс": "Kubernetes", "шепіт": "Shepit app"])
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
