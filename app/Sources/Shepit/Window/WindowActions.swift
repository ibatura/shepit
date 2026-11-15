import Foundation
import ShepitCore

/// What the window needs from the app besides the settings themselves.
@MainActor
struct WindowActions {
    var microphones: () -> [String]
    /// Runs an action the menu also has (reload, open history, start and stop a meeting, copy).
    var perform: (AppAction) -> Void
    var hotkeyProblem: () -> String?
    var openSettingsFile: () -> Void
    var openDictionaryFile: () -> Void
    var openDataFolder: () -> Void
    var clearStatistics: () -> Void
    var setLaunchAtLogin: (Bool) -> String?
    /// The shortcut recorder turns the global hotkeys off while it listens, and back on after.
    var suspendHotkeys: () -> Void
    var resumeHotkeys: () -> Void
    /// Shows the panel with sample text in the current style.
    var previewOverlay: () -> Void
    /// Stored dictation attempts in a period (all of them for nil).
    var statistics: (DateInterval?) -> [DictationRow]
    /// Stored meetings that started in a period (all of them for nil).
    var meetingStatistics: (DateInterval?) -> [MeetingRecord]
    /// Why this engine can't do the configured language, or nil when it can.
    var languageNote: (EngineChoice, String) async -> String?
    var downloads: ModelDownloads
}
