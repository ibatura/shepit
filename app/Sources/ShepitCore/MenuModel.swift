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
        view.meeting?.state.isActive == true ? "⏺" + dictationTitle(view) : dictationTitle(view)
    }

    /// The meeting's line under the status line (window shell design §7); nil when no meeting runs.
    public static func meetingLine(_ state: MeetingState, title: String? = nil) -> String? {
        switch state {
        case .recording(let elapsed, let waiting):
            // A long calendar subject must not widen the whole menu; the clock stays visible.
            let parts = ["⏺ Recording", title.map { StatusText.shorten($0, to: 40) }, StatusText.clock(elapsed), StatusText.phrasesWaiting(waiting)]
            return parts.compactMap { $0 }.joined(separator: " · ")
        case .finishing(let left): return "Meeting: finishing (\(left) left)"
        case .detectingSpeakers: return "Meeting: detecting speakers…"
        case .idle, .done, .interrupted: return nil
        }
    }

    /// Start or Stop; the rest of the meeting items live in the window's Meetings section (Meetings design §9).
    private static func meetingItem(_ view: AppSnapshot) -> MenuItem {
        switch MeetingControl(view.meeting?.state ?? .idle, missing: view.meetingMissing) {
        case .stop: MenuItem(title: "Stop meeting transcript", action: .stopMeeting)
        case .busy: MenuItem(title: "Start meeting transcript", enabled: false)
        case .blocked(let missing): MenuItem(title: "Start meeting transcript (\(missing))", enabled: false)
        case .start: MenuItem(title: "Start meeting transcript", action: .startMeeting)
        }
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
        if let meeting = view.meeting, let line = meetingLine(meeting.state, title: meeting.title) { items.append(MenuItem(title: line, enabled: false)) }
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
        items.append(meetingItem(view))
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
