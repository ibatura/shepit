import Foundation

public enum MenuAction: Equatable, Sendable {
    case setMode(String)
    case setEngine(EngineChoice)
    case setLanguage(String)
    case addToDictionary
    case openWindow
    case openSettings
    case reloadConfig
    case reloadModels
    case openHistory
    case clearHistory
    case copyText(String)
    case grantAccessibility
    case grantMicrophone
    case startMeeting
    /// Start for a call the app has noticed: with its name, no dialog.
    case startCall(title: String?, app: CallApp)
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
    /// The running transcript's name; nil when it has none.
    public var meetingTitle: String?
    /// The app the running transcript was started for ("Teams"); nil when unknown.
    public var meetingApp: String?
    /// A call that runs now and is not recorded.
    public var call: CallOffer.Current?
    /// The newest history entries, newest first, whatever `historyMenuItems` says.
    public var history: [History.Entry] = []
    /// nil when a meeting can start; else what to download first.
    public var meetingMissing: String?

    public init() {}
}

/// Menu bar icon and dropdown as data (port of menubar.lua); the app turns it into an NSMenu.
public enum MenuModel {
    static let maxLine = 90
    static let recentLabelChars = 60

    public static func title(_ view: MenuView) -> String {
        view.meeting.isActive ? "⏺" + dictationTitle(view) : dictationTitle(view)
    }

    /// The meeting's line under the status line (window shell design §7); nil when no meeting runs.
    public static func meetingLine(_ state: MeetingState, title: String? = nil) -> String? {
        switch state {
        case .recording(let elapsed, let waiting):
            let parts = ["⏺ Recording", title, clock(elapsed), waiting > 0 ? "\(waiting) phrase\(waiting == 1 ? "" : "s") waiting" : nil]
            return parts.compactMap { $0 }.joined(separator: " · ")
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
        let start = switch MeetingControl(view.meeting, missing: view.meetingMissing) {
        case .stop: MenuItem(title: "Stop meeting transcript", action: .stopMeeting)
        case .busy: MenuItem(title: "Start meeting transcript", enabled: false)
        case .blocked(let missing): MenuItem(title: "Start meeting transcript (\(missing))", enabled: false)
        case .start: MenuItem(title: "Start meeting transcript", action: .startMeeting)
        }
        // Off during a session: the note is still being written and relabelled.
        let idle = !view.meeting.isActive
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
        let engine = engineTitle(view.settings.engine(for: .dictation))
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
        if let line = meetingLine(view.meeting, title: view.meetingTitle) { items.append(MenuItem(title: line, enabled: false)) }
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
        items += [.separator, MenuItem(title: "Open Shepit", keyEquivalent: "o", action: .openWindow), .separator]
        items += meetingItems(view) // all but Start and Stop move to the window with its Meetings section
        items += [.separator, MenuItem(title: "Copy last dictation", enabled: !view.history.isEmpty, action: view.history.first.map { .copyText($0.text) })]
        if let recent = view.recent {
            let entries = recent.map {
                MenuItem(title: History.label($0, today: view.today, maxChars: recentLabelChars), tooltip: $0.text, action: .copyText($0.text))
            }
            items.append(MenuItem(title: "Recent", submenu: entries.isEmpty ? [MenuItem(title: "No dictations yet", enabled: false)] : entries))
        }
        items += [
            MenuItem(title: "Add word…", action: .addToDictionary),
            .separator,
            MenuItem(title: "Mode", enabled: !busy, submenu: Settings.modes.map {
                MenuItem(title: $0.title, checked: $0.value == view.settings.mode, action: .setMode($0.value))
            }),
            MenuItem(title: "Language", enabled: !busy, submenu: Settings.languages.map {
                MenuItem(title: $0.title, checked: $0.value == view.settings.language, action: .setLanguage($0.value))
            }),
            MenuItem(title: "Dictation engine", enabled: !busy, submenu: engineChoices(view)),
            .separator,
            MenuItem(title: "Settings…", keyEquivalent: ",", action: .openSettings),
            MenuItem(title: "Quit Shepit", keyEquivalent: "q", action: .quit),
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

    private static func shorten(_ s: String) -> String {
        s.count > maxLine ? String(s.prefix(maxLine - 2)) + "…" : s
    }
}
