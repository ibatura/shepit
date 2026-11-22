import Foundation
import Observation
import ShepitCore
import SwiftUI

/// What the Settings window binds to: reads from SettingsStore, and every control change writes
/// exactly one key through `SettingsStore.update` (`04-settings.md` §1, §3).
@MainActor
@Observable
final class SettingsModel {
    /// The pages of Settings (settings review design §4).
    enum Section: String, CaseIterable, Identifiable {
        case general = "General"
        case hotkeys = "Hotkeys"
        case dictation = "Dictation"
        case meetings = "Meetings"
        case engines = "Engines and models"
        case historyPrivacy = "History and privacy"
        case appearance = "Appearance"

        /// A page name remembered by the window, mapped to where its settings are now: Overlay went into Dictation and
        /// Calls into Meetings (settings review, 2026-11-23).
        init?(stored: String) {
            self.init(rawValue: ["Overlay": Self.dictation.rawValue, "Calls": Self.meetings.rawValue][stored] ?? stored)
        }

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .hotkeys: "keyboard"
            case .dictation: "mic"
            case .meetings: "person.2.wave.2"
            case .engines: "cpu"
            case .historyPrivacy: "lock.shield"
            case .appearance: "paintbrush"
            }
        }

        /// What the page is for, shown at its top.
        var line: String {
            switch self {
            case .general: "Shepit itself: starting at login, sounds, and its files."
            case .hotkeys: "The keys that start dictation and meetings."
            case .dictation: "How you dictate: language, microphone, pasting, and the panel shown while you speak."
            case .meetings: "Meeting transcripts: when they start, where the notes go, how they are transcribed."
            case .engines: "Which engine does each job, and every model on this Mac."
            case .historyPrivacy: "What Shepit keeps on this Mac, for how long, and how to clear it."
            case .appearance: "How Shepit's window looks."
            }
        }

        /// The settings.json keys each section edits.
        var keys: [String] {
            switch self {
            case .general: ["launchAtLogin", "sounds"]
            case .hotkeys: ["mode", "hotkey", "cancelKey", "addWordHotkey", "meetingHotkey"]
            case .dictation: ["language", "microphone", "maxRecordingSeconds", "stylePrompt", "refocusOriginalApp", "restoreClipboard",
                              "overlay", "livePreview", "overlayStyle"]
            case .meetings: ["callOffer", "callOfferSeconds", "callAutoStart", "callAutoStartSeconds", "callAutoStopSeconds", "callApps",
                             "meetingsFolder", "meetingFileName", "meetingAskTitle", "meetingMyName", "meetingLanguage", "meetingBlocksDictation"]
            case .engines: ["engines", "idleUnloadMinutes"]
            case .historyPrivacy: ["saveHistory", "historyDays", "historyMenuItems", "failedAudioHours", "collectStats", "typingSpeedWpm", "databasesFolder"]
            case .appearance: ["theme", "accentColor"]
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
        write { try store.update(key, value) }
    }

    /// A control's binding: reads the current value, writes `key` on change.
    func binding<Value>(_ key: String, _ path: KeyPath<ShepitCore.Settings, Value>) -> Binding<Value> {
        Binding(get: { self.settings[keyPath: path] }, set: { self.set(key, $0) })
    }

    func set(_ key: String, hotkey: Hotkey) {
        set(key, ["mods": hotkey.mods, "key": hotkey.key])
    }

    /// Takes the key out of settings.json, so its default applies (for `meetingHotkey`: no shortcut).
    func remove(_ key: String) {
        guard !isReadOnly else { return }
        write { try store.remove(key) }
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

    /// One change to dictionary.json, made on the file as it is now (`DictionaryStore.change`); a refused one is shown.
    func changeDictionary(_ edit: (inout DictionaryFile) throws -> Void) {
        guard !dictionaryIsReadOnly else { return }
        write { try dictionaryStore.change(edit) }
    }

    /// One write to a file; a refused or failed one is shown at the top of the window. The app then applies it.
    private func write(_ change: () throws -> Void) {
        do {
            try change()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
        onChange()
    }
}
