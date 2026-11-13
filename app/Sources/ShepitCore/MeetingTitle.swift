import Foundation

/// Meeting name and app from window titles (spec §5.4 "Meeting name"), best effort. Patterns are
/// provisional until checked against a real call (Task 11).
public enum MeetingTitle {
    public struct Window: Sendable {
        public var app: String
        public var title: String
        /// The window has the call's mute button: it is the meeting window, whatever its title.
        public var inCall: Bool
        public init(app: String, title: String, inCall: Bool = false) {
            self.app = app
            self.title = title
            self.inCall = inCall
        }
    }

    /// Teams views that are not a meeting.
    static let teamsViews: Set<String> = ["Chat", "Calendar", "Activity", "Teams", "Calls", "Files", "Apps", "Copilot",
                                          "Microsoft Teams", "Search", "Settings", "Notifications", "Communities", "OneDrive",
                                          "Meeting join"] // the pre-join screen (2026-11-12)
    public static let zoom = "zoom.us"
    /// Zoom window titles that are not a meeting topic.
    static let zoomGeneric: Set<String> = ["Zoom", "Zoom Meeting", "Zoom Workplace", "Zoom Webinar", "Meeting", "zoom.us"]
    public static let browsers = ["Google Chrome", "Safari", "Arc", "Microsoft Edge", "Firefox", "Brave Browser", "Opera", "Vivaldi", "Chromium"]

    /// `windows` front-most first. A Teams meeting window wins over a Meet tab.
    public static func detect(_ windows: [Window]) -> (title: String?, app: String?) {
        // New Teams (2026-11-04): the call window is titled just "Refinement: Phase 3 …", with no
        // " | Microsoft Teams"; the window with the mute button tells it from chats and the calendar.
        for window in windows where window.app.hasPrefix("Microsoft Teams") && window.inCall {
            return (teamsCall(window.title), "Teams")
        }
        for window in windows where window.app.hasPrefix("Microsoft Teams") {
            if let title = teams(window.title) { return (title, "Teams") }
        }
        // Zoom keeps the topic out of most titles: "Zoom Meeting" is a call with no name.
        for window in windows where window.app == zoom && (window.inCall || window.title.hasPrefix("Zoom Meeting")) {
            let title = window.title.trimmingCharacters(in: .whitespaces)
            return (zoomGeneric.contains(title) ? nil : title, "Zoom")
        }
        for window in windows where browsers.contains(window.app) {
            if let found = meet(window.title) { return (found.isEmpty ? nil : found, "Meet") }
        }
        return (nil, nil)
    }

    /// "Weekly sync | Microsoft Teams" → "Weekly sync"; views like "Chat | Olha | Microsoft Teams" → nil.
    static func teams(_ title: String) -> String? {
        let parts = title.components(separatedBy: " | ").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2, parts.last?.hasPrefix("Microsoft Teams") == true, let first = parts.first,
              !first.isEmpty, !teamsViews.contains(first) else { return nil }
        return first
    }

    /// A mute control's label: true = the microphone is muted now ("Unmute mic", "Turn on microphone"),
    /// false = it is on ("Mute mic", Meet's "Turn off microphone (⌘ + d)", Zoom's "Mute audio"), nil = not one.
    public static func micMuted(byLabel label: String) -> Bool? {
        let text = label.lowercased().trimmingCharacters(in: .whitespaces)
        // Host controls for everyone else (Zoom's Meeting menu, Teams' participant list) are not my mic, and
        // neither is Chrome's "Mute tab" / "Mute site" (found before Meet's own button, 2026-11-06).
        let words = Set(text.split { !$0.isLetter }.map(String.init))
        guard words.isDisjoint(with: ["all", "everyone", "participants", "entry", "tab", "site", "notifications"]) else { return nil }
        for prefix in ["unmute", "turn on microphone", "turn on mic", "увімкнути мікрофон", "увімкнути звук"] where text.hasPrefix(prefix) { return true }
        for prefix in ["mute", "turn off microphone", "turn off mic", "вимкнути мікрофон", "вимкнути звук"] where text.hasPrefix(prefix) { return false }
        return nil
    }

    /// The call window's title without " | Microsoft Teams"; nil for a view name or nothing left.
    static func teamsCall(_ title: String) -> String? {
        let parts = title.components(separatedBy: " | ").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("Microsoft Teams") }
        guard let first = parts.first, !teamsViews.contains(first) else { return nil }
        return first
    }

    /// "Meet - Weekly sync - Google Chrome - Work" → "Weekly sync"; a bare code like abc-defg-hij → "" (Meet, no name).
    /// What Chrome adds after a page title: recording, sound and tab-group marks.
    nonisolated(unsafe) static let chromeMarks = /\s[-–—]\s(Camera and microphone recording|Camera recording|Microphone recording|Audio playing|Audio muted|Sharing [a-z ]+|Part of group .*|High memory usage.*|Network connection lost|Pinned)$/

    /// "Meet - Weekly sync - Google Chrome" → "Weekly sync"; a meeting code ("abc-defg-hij") → "" (Meet,
    /// no name); not Meet → nil. Chrome during a call (2026-11-06):
    /// `Meet: "qbu-gkgc-bjh" – Camera and microphone recording - Google Chrome – Ivan (Ivan (private))`.
    static func meet(_ title: String) -> String? {
        var text = title
        for browser in browsers {
            for separator in [" - ", " — ", " – "] {
                if let range = text.range(of: separator + browser) { text = String(text[..<range.lowerBound]) }
            }
        }
        while let mark = text.firstMatch(of: chromeMarks) { text = String(text[..<mark.range.lowerBound]) }
        text = text.trimmingCharacters(in: .whitespaces)
        for prefix in ["Meet - ", "Meet – ", "Meet — ", "Meet: "] where text.hasPrefix(prefix) {
            var rest = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            if rest.count >= 2, rest.first == "\"" || rest.first == "“", rest.last == "\"" || rest.last == "”" {
                rest = String(rest.dropFirst().dropLast())
            }
            return rest.wholeMatch(of: /[a-z]{3}-[a-z]{4}-[a-z]{3}/) != nil ? "" : rest
        }
        if text.wholeMatch(of: /[a-z]{3}-[a-z]{4}-[a-z]{3}/) != nil || text == "Google Meet" { return "" }
        return nil
    }

    /// A clock as Meet shows it next to the meeting name: "16:29", "4:29 PM".
    public static func isClock(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespaces).wholeMatch(of: /\d{1,2}:\d{2}(\s?[AaPp]\.?\s?[Mm]\.?)?/) != nil
    }

    /// The meeting name on a Meet call page: its bottom bar reads "16:29 | Weekly sync" (a meeting from a
    /// calendar) or "16:29 | abc-defg-hij" (a quick meeting: no name). `texts` are the bar's texts in order.
    public static func meetPageName(_ texts: [String]) -> String? {
        let parts = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard let clock = parts.firstIndex(where: isClock) else { return nil }
        guard let name = parts[(clock + 1)...].first(where: { !["|", "•", "·", "-", "–"].contains($0) }) else { return nil }
        if name.wholeMatch(of: /[a-z]{3}-[a-z]{4}-[a-z]{3}/) != nil || isClock(name) || name.count > 120 { return nil }
        return name
    }
}
