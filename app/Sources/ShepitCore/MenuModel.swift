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

/// The menu bar's rhombus (icon and name design §6): the dictation's mark, and a dot while a meeting transcript runs.
public struct MenuIcon: Hashable, Sendable, CaseIterable {
    public enum Mark: CaseIterable, Sendable { case ready, recording, transcribing, problem }
    public var mark: Mark
    public var meeting: Bool

    public init(mark: Mark, meeting: Bool) {
        self.mark = mark
        self.meeting = meeting
    }

    /// Every mark, alone and with the meeting's dot.
    public static let allCases = Mark.allCases.flatMap { mark in [false, true].map { MenuIcon(mark: mark, meeting: $0) } }

    /// No colour: drawn as a template, which macOS tints for any menu bar.
    public var isPlain: Bool { !meeting && (mark == .ready || mark == .transcribing) }
}

/// Menu bar icon and dropdown as data (port of menubar.lua); the app turns it into an NSMenu.
public enum MenuModel {
    static let recentLabelChars = 60

    public static func icon(_ view: AppSnapshot) -> MenuIcon {
        MenuIcon(mark: mark(view), meeting: view.meeting?.state.isActive == true)
    }

    /// The icon's tooltip and VoiceOver label: the status line, then what its dots show. No meeting title: it changes every call.
    public static func iconLabel(_ view: AppSnapshot) -> String {
        let icon = icon(view)
        var parts = ["Shepit: \(view.statusLine)"]
        if icon.mark == .problem, let hotkey = view.hotkeyProblem { parts.append(hotkey) } // a failed load is in the status line
        if icon.meeting { parts.append("Meeting transcript running") }
        return parts.joined(separator: " · ")
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

    private static func mark(_ view: AppSnapshot) -> MenuIcon.Mark {
        switch view.state {
        case .recording: return .recording
        case .transcribing: return .transcribing
        case .idle:
            if case .failed = view.load { return .problem }
            return view.hotkeyProblem == nil ? .ready : .problem
        }
    }

    /// Settings review design §6: ⚠ problems, Meeting, Dictation, Shepit, each group led by its state.
    public static func build(_ view: AppSnapshot) -> [MenuItem] {
        var problems = (view.configErrors + [view.hotkeyProblem].compactMap { $0 }).map { MenuItem(title: StatusText.shorten("⚠ \($0)"), enabled: false) }
        if !view.accessibilityGranted {
            problems.append(MenuItem(title: "⚠ Accessibility not granted — click to allow (needed to paste)", action: .grantAccessibility))
        }
        if view.microphoneDenied {
            problems.append(MenuItem(title: "⚠ Microphone access denied — click to open Settings", action: .grantMicrophone))
        }
        var meeting = view.meeting.flatMap { meetingLine($0.state, title: $0.title) }.map { [MenuItem(title: $0, enabled: false)] } ?? []
        meeting += [meetingItem(view),
                    languages("Meeting language", view.settings.meetingLanguage, enabled: view.meeting?.state.isActive != true, action: AppAction.setMeetingLanguage)]
        var dictation = [MenuItem(title: "Dictation: \(view.statusLine)", enabled: false),
                         MenuItem(title: "Copy last dictation", enabled: !view.history.isEmpty, action: view.history.first.map { .copyText($0.text) })]
        if view.settings.historyMenuItems > 0 {
            let entries = view.history.prefix(view.settings.historyMenuItems).map {
                MenuItem(title: recentLabel($0, now: view.now), tooltip: $0.text, action: .copyText($0.text))
            }
            dictation.append(MenuItem(title: "Recent dictations", submenu: entries.isEmpty ? [MenuItem(title: "No dictations yet", enabled: false)] : entries))
        }
        dictation += [MenuItem(title: "Add word to dictionary…", action: .addToDictionary),
                      languages("Dictation language", view.settings.language, enabled: view.state == .idle, action: AppAction.setLanguage)]
        let shepit = [
            MenuItem(title: "Open Shepit", keyEquivalent: "o", action: .openWindow),
            MenuItem(title: "Settings…", keyEquivalent: ",", action: .openSettings),
            MenuItem(title: "About Shepit", action: .about),
            MenuItem(title: "Quit Shepit", keyEquivalent: "q", action: .quit),
        ]
        return Array([problems, meeting, dictation, shepit].filter { !$0.isEmpty }.joined(separator: [.separator]))
    }

    private static func languages(_ title: String, _ current: String, enabled: Bool, action: (String) -> AppAction) -> MenuItem {
        MenuItem(title: title, enabled: enabled, submenu: Settings.languages.map {
            MenuItem(title: $0.title, checked: $0.value == current, action: action($0.value))
        })
    }

    /// "14:32 · text" on one line, the text cut to `recentLabelChars` with "…".
    private static func recentLabel(_ entry: DictationStore.Entry, now: Date) -> String {
        var text = entry.text.replacingOccurrences(of: #"\s*[\r\n]+\s*"#, with: " ", options: .regularExpression)
        if text.count > recentLabelChars {
            text = String(text.prefix(recentLabelChars - 1)).replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression) + "…"
        }
        return "\(DictationPage.when(entry.time, now: now)) · \(text)"
    }
}
