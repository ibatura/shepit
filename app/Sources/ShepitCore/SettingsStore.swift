import Foundation

public enum SettingsStoreError: Error, LocalizedError {
    case brokenSettings
    case validation([String])
    case write(String)

    public var errorDescription: String? {
        switch self {
        case .brokenSettings:
            "settings.json errors; fix it first (Edit settings…)"
        case .validation(let errors):
            errors.joined(separator: "\n")
        case .write(let message):
            "could not save settings.json: \(message)"
        }
    }
}

public final class SettingsStore {
    public let file: URL
    public private(set) var settings: Settings = .defaults
    public private(set) var errors: [String] = []

    private var rawSettings: [String: Any] = [:]
    private var settingsAreValid = true

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
            settingsAreValid = false
            errors = ["settings.json: \(error.message)"]
            return false
        }

        let (validated, validationErrors) = validateSettings(raw)
        guard let validated else {
            settingsAreValid = false
            errors = validationErrors
            return false
        }
        settings = validated
        rawSettings = raw
        errors = []
        settingsAreValid = true
        return true
    }

    /// A key exactly as it is in the file (nil when unset), e.g. to change one field of `overlayStyle`.
    public func rawValue(_ key: String) -> Any? {
        rawSettings[key]
    }

    public func update(_ key: String, _ value: Any) throws {
        if FileManager.default.fileExists(atPath: file.path) { load() } // merge into the file as it is now, not as at the last poll
        guard settingsAreValid else { throw SettingsStoreError.brokenSettings }
        var raw = rawSettings
        raw[key] = value
        if key == "engines" {
            raw.removeValue(forKey: "model")
            raw.removeValue(forKey: "previewModel")
        }

        let (validated, validationErrors) = validateSettings(raw)
        guard let validated else { throw SettingsStoreError.validation(validationErrors) }

        do {
            try JSONFile.writeAtomically(raw, to: file)
        } catch {
            throw SettingsStoreError.write(error.localizedDescription)
        }
        settings = validated
        rawSettings = raw
    }
}
