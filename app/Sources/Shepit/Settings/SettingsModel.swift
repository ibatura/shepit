import Foundation
import Observation
import ShepitCore
import SwiftUI

/// What the Settings window binds to: reads from SettingsStore, and every control change writes
/// exactly one key through `SettingsStore.update` (`04-settings.md` §1, §3).
@MainActor
@Observable
final class SettingsModel {
    enum Section: String, CaseIterable, Identifiable {
        case general = "General"
        case hotkeys = "Hotkeys"
        case dictation = "Dictation"
        case meetings = "Meetings"
        case engines = "Engines & Models"
        case overlay = "Overlay"
        case dictionary = "Dictionary"
        case historyPrivacy = "History & Privacy"
        case statistics = "Statistics"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .hotkeys: "keyboard"
            case .dictation: "mic"
            case .meetings: "person.2.wave.2"
            case .engines: "cpu"
            case .overlay: "rectangle.bottomhalf.inset.filled"
            case .dictionary: "character.book.closed"
            case .historyPrivacy: "lock.shield"
            case .statistics: "chart.bar"
            }
        }

        /// The settings.json keys each section edits (`serverPort` is accepted in the file but shown nowhere).
        var keys: [String] {
            switch self {
            case .general: ["launchAtLogin", "sounds", "language"]
            case .hotkeys: ["mode", "hotkey", "cancelKey", "addWordHotkey"]
            case .dictation: ["microphone", "stylePrompt", "refocusOriginalApp", "restoreClipboard", "maxRecordingSeconds"]
            case .meetings: ["meetingsFolder", "meetingFileName", "meetingAskTitle", "meetingMyName", "meetingLanguage", "meetingBlocksDictation"]
            case .engines: ["engines", "idleUnloadMinutes"]
            case .overlay: ["overlay", "livePreview", "overlayStyle"]
            case .dictionary: [] // dictionary.json: terms, replace, dropPhrases
            case .historyPrivacy: ["saveHistory", "historyDays", "historyMenuItems", "failedAudioHours", "collectStats", "typingSpeedWpm"]
            case .statistics: [] // reads stats.sqlite
            }
        }
    }

    private(set) var settings: ShepitCore.Settings
    private(set) var errors: [String]
    private(set) var dictionary: DictionaryFile
    private(set) var dictionaryErrors: [String]
    /// The last write that was refused or failed, shown at the top of the window.
    private(set) var lastError: String?

    /// Controls can't change anything while settings.json has errors (the menu refuses too).
    var isReadOnly: Bool { !errors.isEmpty }

    @ObservationIgnored private let store: SettingsStore
    @ObservationIgnored private let dictionaryStore: DictionaryStore
    /// Called after a successful write, so the app applies the change at once.
    @ObservationIgnored var onChange: () -> Void = {}

    init(store: SettingsStore, dictionaryStore: DictionaryStore) {
        self.store = store
        self.dictionaryStore = dictionaryStore
        settings = store.settings
        errors = store.errors
        dictionary = dictionaryStore.dictionary
        dictionaryErrors = dictionaryStore.errors
    }

    /// Picks up edits made in the files by hand (the app re-reads them every 2 s).
    func refresh() {
        if settings != store.settings { settings = store.settings }
        if errors != store.errors { errors = store.errors }
        if dictionary != dictionaryStore.dictionary { dictionary = dictionaryStore.dictionary }
        if dictionaryErrors != dictionaryStore.errors { dictionaryErrors = dictionaryStore.errors }
    }

    func set(_ key: String, _ value: Any) {
        guard !isReadOnly else { return }
        do {
            try store.update(key, value)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
        onChange()
    }

    /// A control's binding: reads the current value, writes `key` on change.
    func binding<Value>(_ key: String, _ path: KeyPath<ShepitCore.Settings, Value>) -> Binding<Value> {
        Binding(get: { self.settings[keyPath: path] }, set: { self.set(key, $0) })
    }

    func set(_ key: String, hotkey: Hotkey) {
        set(key, ["mods": hotkey.mods, "key": hotkey.key])
    }

    /// One task's engine; writes the whole `engines` object (the store then drops the legacy model keys).
    func setEngine(_ task: EngineTask, _ choice: EngineChoice) {
        var engines = settings.engines
        engines[task] = choice
        set("engines", Dictionary(uniqueKeysWithValues: engines.map {
            ($0.key.rawValue, ["engine": $0.value.engine.rawValue, "model": $0.value.model])
        }))
    }

    /// One field of `overlayStyle`; the other fields in the file (set or not) stay as they are.
    func setStyle(_ key: String, _ value: Any) {
        var style = store.rawValue("overlayStyle") as? [String: Any] ?? [:]
        style[key] = value
        set("overlayStyle", style)
    }

    func styleBinding<Value>(_ key: String, _ path: KeyPath<OverlayStyle, Value>) -> Binding<Value> {
        Binding(get: { self.settings.overlayStyle[keyPath: path] }, set: { self.setStyle(key, $0) })
    }

    // MARK: dictionary.json

    var dictionaryIsReadOnly: Bool { !dictionaryErrors.isEmpty }

    func setTerms(_ terms: [String]) {
        setDictionary("terms", terms)
    }

    func setDropPhrases(_ phrases: [String]) {
        setDictionary("dropPhrases", phrases)
    }

    /// Adds or edits a replace rule (`previous` is the rule's old spelling when editing).
    func setRule(wrong: String, right: String, replacing previous: String? = nil) {
        let wrong = wrong.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = right.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wrong.isEmpty, !right.isEmpty else {
            lastError = "A replace rule needs both what was heard and the correct spelling"
            return
        }
        var replace = dictionary.replace
        if let previous { replace[previous] = nil }
        replace[wrong.lowercased()] = right
        setDictionary("replace", replace)
    }

    func removeRule(_ wrong: String) {
        var replace = dictionary.replace
        replace[wrong] = nil
        setDictionary("replace", replace)
    }

    private func setDictionary(_ key: String, _ value: Any) {
        guard !dictionaryIsReadOnly else { return }
        do {
            try dictionaryStore.update(key, value)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
        onChange()
    }
}
