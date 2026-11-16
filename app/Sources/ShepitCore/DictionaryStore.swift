import Foundation

public enum DictionaryStoreError: Error, Equatable, LocalizedError {
    case brokenDictionary
    case emptyRight
    case emptyRule
    case ruleExists(String)
    case validation([String])
    case write(String)

    public var errorDescription: String? {
        switch self {
        case .brokenDictionary:
            "dictionary.json has errors; fix it first (Open Shepit → Open dictionary file)"
        case .emptyRight:
            "the correct spelling is empty"
        case .emptyRule:
            "A replace rule needs both what was heard and the correct spelling"
        case .ruleExists(let heard):
            "Another rule already replaces “\(heard)”"
        case .validation(let errors):
            errors.joined(separator: "\n")
        case .write(let message):
            "could not save dictionary.json: \(message)"
        }
    }
}

/// dictionary.json with last-good behaviour, like SettingsStore (port of config.lua Store dictionary parts).
public final class DictionaryStore {
    public let file: URL
    public private(set) var dictionary: DictionaryFile = .empty
    public private(set) var errors: [String] = []

    private var rawDictionary: [String: Any] = [:]
    private var dictionaryIsValid = true

    public init(file: URL) {
        self.file = file
    }

    @discardableResult
    public func load() -> Bool {
        let raw: [String: Any]
        switch JSONFile.readObject(file) {
        case .success(let object):
            raw = object
        case .failure(let error):
            dictionaryIsValid = false
            errors = ["dictionary.json: \(error.message)"]
            return false
        }
        let (validated, validationErrors) = validateDictionary(raw)
        guard let validated else {
            dictionaryIsValid = false
            errors = validationErrors
            return false
        }
        dictionary = validated
        rawDictionary = raw
        errors = []
        dictionaryIsValid = true
        return true
    }

    /// Current replacement for a misspelling (matched case-insensitively), or nil.
    public func ruleFor(_ wrong: String) -> String? {
        let key = wrong.trimmed.lowercased()
        return dictionary.replace.first { $0.key.lowercased() == key }?.value
    }

    /// Changes the dictionary as the file is now, not as at the last poll, so a hand edit made since stays. Only the keys
    /// that changed are written; the rest of the file is kept. An edit that throws writes nothing.
    public func change(_ edit: (inout DictionaryFile) throws -> Void) throws {
        if FileManager.default.fileExists(atPath: file.path) { load() }
        guard dictionaryIsValid else { throw DictionaryStoreError.brokenDictionary }
        var changed = dictionary
        try edit(&changed)
        var raw = rawDictionary
        if changed.terms != dictionary.terms { raw["terms"] = changed.terms }
        if changed.replace != dictionary.replace { raw["replace"] = changed.replace }
        if changed.dropPhrases != dictionary.dropPhrases { raw["dropPhrases"] = changed.dropPhrases }
        try write(raw)
    }

    /// Add word (⌃⌥D): `wrong → right` in replace, over any rule for `wrong` in any case, and `right` in terms. Empty
    /// `wrong` adds only the term.
    public func addRule(wrong: String, right: String) throws {
        let right = right.trimmed
        guard !right.isEmpty else { throw DictionaryStoreError.emptyRight }
        try change { dictionary in
            if !wrong.trimmed.isEmpty {
                dictionary.replace = dictionary.replace.filter { $0.key.lowercased() != wrong.trimmed.lowercased() }
                try dictionary.setRule(heard: wrong, written: right)
            }
            dictionary.add(term: right)
        }
    }

    private func write(_ raw: [String: Any]) throws {
        let (validated, validationErrors) = validateDictionary(raw)
        guard let validated else { throw DictionaryStoreError.validation(validationErrors) }
        do {
            try JSONFile.writeAtomically(raw, to: file)
        } catch {
            throw DictionaryStoreError.write(error.localizedDescription)
        }
        dictionary = validated
        rawDictionary = raw
    }
}
