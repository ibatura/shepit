import Foundation

public enum MenuAction: Equatable, Sendable {
    case setMode(String)
    case setEngine(EngineChoice)
    case setLanguage(String)
    case setMicrophone(String)
    case addToDictionary
    case editDictionary
    case openSettings
    case openStatistics
    case reloadConfig
    case reloadModels
    case openHistory
    case clearHistory
    case copyText(String)
    case grantAccessibility
    case grantMicrophone
    case startMeeting
    case stopMeeting
    case copyLastMeeting
    case openMeetingsFolder
    case renameSpeakers
    case renameSpeakersInNote
    case quit
}

public struct MenuItem: Equatable, Sendable {
    public var title: String
    public var enabled = true
    public var checked = false
    public var tooltip: String?
    public var keyEquivalent = ""
    public var action: MenuAction?
    public var submenu: [MenuItem]?

    public static let separator = MenuItem(title: "-")

    public init(title: String, enabled: Bool = true, checked: Bool = false, tooltip: String? = nil,
                keyEquivalent: String = "", action: MenuAction? = nil, submenu: [MenuItem]? = nil) {
        self.title = title
        self.enabled = enabled
        self.checked = checked
        self.tooltip = tooltip
        self.keyEquivalent = keyEquivalent
        self.action = action
        self.submenu = submenu
    }
}

/// Everything the menu shows, gathered by the app each time the menu opens.
public struct MenuView: Sendable {
    public var state: ControllerState = .idle
    public var load: LoadState = .loaded
    public var settings: Settings = .defaults
    public var downloaded: [EngineChoice] = []
    public var configErrors: [String] = []
    public var hotkeyProblem: String?
    /// nil hides Recent (`historyMenuItems` = 0).
    public var recent: [History.Entry]? = []
    public var today = ""
    public var microphones: [String] = []
    public var accessibilityGranted = true
    public var microphoneDenied = false
    public var meeting: MeetingState = .idle
    /// nil when a meeting can start; else what to download first.
    public var meetingMissing: String?

    public init() {}
}

/// Menu bar icon and dropdown as data (port of menubar.lua); the app turns it into an NSMenu.
public enum MenuModel {
    static let maxLine = 90
    static let recentLabelChars = 60
    private static let modeTitles = ["toggle": "Toggle", "hold": "Hold to talk"]
    private static let languageTitles = ["uk": "Ukrainian", "en": "English", "auto": "Auto-detect"]

    public static func title(_ view: MenuView) -> String {
        meetingActive(view.meeting) ? "⏺" + dictationTitle(view) : dictationTitle(view)
    }

    static func meetingActive(_ state: MeetingState) -> Bool {
        switch state {
        case .recording, .finishing, .detectingSpeakers: true
        case .idle, .done, .interrupted: false
        }
    }

    /// The meeting's line under the status line (spec §5.6); nil when no meeting runs.
    public static func meetingLine(_ state: MeetingState) -> String? {
        switch state {
        case .recording(let elapsed, let waiting):
            let time = clock(elapsed)
            return waiting > 0 ? "Meeting: recording \(time) · \(waiting) phrase\(waiting == 1 ? "" : "s") waiting" : "Meeting: recording \(time)"
        case .finishing(let left): return "Meeting: finishing (\(left) left)"
        case .detectingSpeakers: return "Meeting: detecting speakers…"
        case .idle, .done, .interrupted: return nil
        }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let (h, m, s) = (total / 3600, total / 60 % 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    private static func meetingItems(_ view: MenuView) -> [MenuItem] {
        let start: MenuItem
        switch view.meeting {
        case .recording: start = MenuItem(title: "Stop meeting transcript", action: .stopMeeting)
        case .finishing, .detectingSpeakers: start = MenuItem(title: "Start meeting transcript", enabled: false)
        case .idle, .done, .interrupted:
            start = view.meetingMissing.map { MenuItem(title: "Start meeting transcript (\($0))", enabled: false) }
                ?? MenuItem(title: "Start meeting transcript", action: .startMeeting)
        }
        // Off during a session: the note is still being written and relabelled.
        let idle = !meetingActive(view.meeting)
        return [
            start,
            MenuItem(title: "Copy last meeting transcript", action: .copyLastMeeting),
            MenuItem(title: "Rename speakers…", enabled: idle, action: .renameSpeakers),
            MenuItem(title: "Rename speakers in another note…", enabled: idle, action: .renameSpeakersInNote),
            MenuItem(title: "Open meetings folder", action: .openMeetingsFolder),
        ]
    }

    private static func dictationTitle(_ view: MenuView) -> String {
        switch view.state {
        case .recording: return "🔴"
        case .transcribing: return "⏳"
        case .idle:
            if case .failed = view.load { return "🎙⚠" }
            return view.hotkeyProblem == nil ? "🎙" : "🎙⚠"
        }
    }

    public static func statusLine(_ view: MenuView) -> String {
        switch view.state {
        case .recording: return "Recording… (Esc to cancel)"
        case .transcribing: return "Transcribing…"
        case .idle: break
        }
        let engine = engineTitle(view.settings.engines[.dictation] ?? Settings.defaults.engines[.dictation]!)
        switch view.load {
        case .loading: return "Loading \(engine)…"
        case .failed(let detail): return shorten("Error: \(detail)")
        case .unloaded: return "Model unloaded — loads on next use"
        case .loaded: return "Ready — \(engine)"
        }
    }

    public static func engineTitle(_ choice: EngineChoice) -> String {
        switch choice.engine {
        case .whispercpp: "whisper.cpp \(choice.model)"
        case .whisperkit: "WhisperKit \(choice.model)"
        case .parakeet: "Parakeet"
        case .apple: "Apple Speech"
        }
    }

    public static func build(_ view: MenuView) -> [MenuItem] {
        let busy = view.state != .idle
        var items = [MenuItem(title: statusLine(view), enabled: false)]
        if let line = meetingLine(view.meeting) { items.append(MenuItem(title: line, enabled: false)) }
        for error in view.configErrors {
            items.append(MenuItem(title: shorten("⚠ \(error)"), enabled: false))
        }
        if let problem = view.hotkeyProblem {
            items.append(MenuItem(title: shorten("⚠ \(problem)"), enabled: false))
        }
        if !view.accessibilityGranted {
            items.append(MenuItem(title: "⚠ Accessibility not granted — click to allow (needed to paste)", action: .grantAccessibility))
        }
        if view.microphoneDenied {
            items.append(MenuItem(title: "⚠ Microphone access denied — click to open Settings", action: .grantMicrophone))
        }
        items += [
            .separator,
            MenuItem(title: "Mode", enabled: !busy, submenu: ["toggle", "hold"].map {
                MenuItem(title: modeTitles[$0]!, checked: $0 == view.settings.mode, action: .setMode($0))
            }),
            MenuItem(title: "Engine", enabled: !busy, submenu: engineChoices(view)),
            MenuItem(title: "Language", enabled: !busy, submenu: ["uk", "en", "auto"].map {
                MenuItem(title: languageTitles[$0]!, checked: $0 == view.settings.language, action: .setLanguage($0))
            }),
            MenuItem(title: "Microphone", enabled: !busy && !meetingActive(view.meeting), submenu: microphoneChoices(view)),
            .separator,
        ]
        items += meetingItems(view)
        items += [
            .separator,
            MenuItem(title: "Add to dictionary…", action: .addToDictionary),
            MenuItem(title: "Edit dictionary…", action: .editDictionary),
            MenuItem(title: "Settings…", keyEquivalent: ",", action: .openSettings),
            MenuItem(title: "Statistics", action: .openStatistics),
            MenuItem(title: "Reload config", action: .reloadConfig),
            MenuItem(title: "Reload models", enabled: !busy, action: .reloadModels),
        ]
        if let recent = view.recent {
            let entries = recent.map {
                MenuItem(title: History.label($0, today: view.today, maxChars: recentLabelChars), tooltip: $0.text, action: .copyText($0.text))
            }
            items.append(MenuItem(title: "Recent", submenu: entries.isEmpty ? [MenuItem(title: "No dictations yet", enabled: false)] : entries))
        }
        items += [
            MenuItem(title: "Open history", action: .openHistory),
            MenuItem(title: "Clear history…", action: .clearHistory),
            .separator,
            MenuItem(title: "Quit", keyEquivalent: "q", action: .quit),
        ]
        return items
    }

    /// Downloaded engine+model pairs for dictation; the configured one is shown even when missing.
    private static func engineChoices(_ view: MenuView) -> [MenuItem] {
        let current = view.settings.engines[.dictation]
        var items = view.downloaded.map { MenuItem(title: engineTitle($0), checked: $0 == current, action: .setEngine($0)) }
        if let current, !view.downloaded.contains(current) {
            items.append(MenuItem(title: "\(engineTitle(current)) (not downloaded)", enabled: false))
        }
        return items
    }

    private static func microphoneChoices(_ view: MenuView) -> [MenuItem] {
        let current = view.settings.microphone
        var items = [MenuItem(title: "System default", checked: current.isEmpty, action: .setMicrophone(""))]
        items += view.microphones.map { MenuItem(title: $0, checked: $0 == current, action: .setMicrophone($0)) }
        if !current.isEmpty, !view.microphones.contains(current) {
            items.append(MenuItem(title: "\(current) (not connected)", enabled: false))
        }
        return items
    }

    private static func shorten(_ s: String) -> String {
        s.count > maxLine ? String(s.prefix(maxLine - 2)) + "…" : s
    }
}
