import Foundation

public enum DictionaryStoreError: Error, Equatable, LocalizedError {
    case brokenDictionary
    case emptyRight
    case validation([String])
    case write(String)

    public var errorDescription: String? {
        switch self {
        case .brokenDictionary:
            "dictionary.json has errors; fix it first (Edit dictionary…)"
        case .emptyRight:
            "the correct spelling is empty"
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

    /// Replaces one key (`terms`, `replace`, `dropPhrases`), keeping the rest of the file; validated first.
    public func update(_ key: String, _ value: Any) throws {
        if FileManager.default.fileExists(atPath: file.path) { load() } // merge into the file as it is now, not as at the last poll
        guard dictionaryIsValid else { throw DictionaryStoreError.brokenDictionary }
        var raw = rawDictionary
        raw[key] = value
        try write(raw)
    }

    /// Adds `wrong → right` to replace and `right` to terms. Empty `wrong` adds only the term.
    public func addRule(wrong: String, right: String) throws {
        if FileManager.default.fileExists(atPath: file.path) { load() }
        guard dictionaryIsValid else { throw DictionaryStoreError.brokenDictionary }
        let wrong = wrong.trimmed
        let right = right.trimmed
        guard !right.isEmpty else { throw DictionaryStoreError.emptyRight }
        var raw = rawDictionary
        if !wrong.isEmpty {
            let key = wrong.lowercased()
            var replace = (raw["replace"] as? [String: String] ?? [:]).filter { $0.key.lowercased() != key }
            replace[key] = right
            raw["replace"] = replace
        }
        var terms = raw["terms"] as? [String] ?? []
        if !terms.contains(right) { terms.append(right) }
        raw["terms"] = terms
        try write(raw)
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
