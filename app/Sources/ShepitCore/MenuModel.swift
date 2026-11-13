import Foundation

public struct MenuItem: Equatable, Sendable {
    public var title: String
    public var enabled = true
    public var checked = false
    public var tooltip: String?
    public var keyEquivalent = ""
    public var action: AppAction?
    public var submenu: [MenuItem]?

    public static let separator = MenuItem(title: "-")

    public init(title: String, enabled: Bool = true, checked: Bool = false, tooltip: String? = nil,
                keyEquivalent: String = "", action: AppAction? = nil, submenu: [MenuItem]? = nil) {
        self.title = title
        self.enabled = enabled
        self.checked = checked
        self.tooltip = tooltip
        self.keyEquivalent = keyEquivalent
        self.action = action
        self.submenu = submenu
    }
}

/// Menu bar icon and dropdown as data (port of menubar.lua); the app turns it into an NSMenu.
public enum MenuModel {
    static let recentLabelChars = 60

    public static func title(_ view: AppSnapshot) -> String {
        view.meeting.isActive ? "⏺" + dictationTitle(view) : dictationTitle(view)
    }

    /// The meeting's line under the status line (window shell design §7); nil when no meeting runs.
    public static func meetingLine(_ state: MeetingState, title: String? = nil) -> String? {
        switch state {
        case .recording(let elapsed, let waiting):
            let parts = ["⏺ Recording", title, StatusText.clock(elapsed), StatusText.phrasesWaiting(waiting)]
            return parts.compactMap { $0 }.joined(separator: " · ")
        case .finishing(let left): return "Meeting: finishing (\(left) left)"
        case .detectingSpeakers: return "Meeting: detecting speakers…"
        case .idle, .done, .interrupted: return nil
        }
    }

    private static func meetingItems(_ view: AppSnapshot) -> [MenuItem] {
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

    private static func dictationTitle(_ view: AppSnapshot) -> String {
        switch view.state {
        case .recording: return "🔴"
        case .transcribing: return "⏳"
        case .idle:
            if case .failed = view.load { return "🎙⚠" }
            return view.hotkeyProblem == nil ? "🎙" : "🎙⚠"
        }
    }

    public static func build(_ view: AppSnapshot) -> [MenuItem] {
        let busy = view.state != .idle
        var items = [MenuItem(title: view.statusLine, enabled: false)]
        if let line = meetingLine(view.meeting, title: view.meetingTitle) { items.append(MenuItem(title: line, enabled: false)) }
        for error in view.configErrors {
            items.append(MenuItem(title: StatusText.shorten("⚠ \(error)"), enabled: false))
        }
        if let problem = view.hotkeyProblem {
            items.append(MenuItem(title: StatusText.shorten("⚠ \(problem)"), enabled: false))
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
        if view.settings.historyMenuItems > 0 {
            let entries = view.history.prefix(view.settings.historyMenuItems).map {
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
    private static func engineChoices(_ view: AppSnapshot) -> [MenuItem] {
        let current = view.settings.engines[.dictation]
        var items = view.downloaded.map { MenuItem(title: $0.title, checked: $0 == current, action: .setEngine($0)) }
        if let current, !view.downloaded.contains(current) {
            items.append(MenuItem(title: "\(current.title) (not downloaded)", enabled: false))
        }
        return items
    }
}
