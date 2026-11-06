import AppKit
import ShepitCore

/// Meeting apps seen through Accessibility (which Shepit already has for pasting): window and tab titles of
/// Teams, Zoom and browsers, and the call's mute button (spec §5.4 "Meeting name"; Task 11).
///
/// Teams, Chrome and other Chromium/Electron apps build their accessibility tree only once an assistive app
/// asks, and a moment later: a lookup right at Start saw an empty call window (2026-11-04). So Shepit asks them
/// to keep it built (AXManualAccessibility) at launch, when one of them starts, and at Start.
enum MeetingApps {
    static let callApps = ["Microsoft Teams", MeetingTitle.zoom]

    /// What one look found. AXUIElement is a CF reference, usable from any thread.
    struct Scan: @unchecked Sendable {
        var windows: [MeetingTitle.Window] = []
        var mute: MuteButton?
        var visited = 0
        /// The name on a Meet call page ("16:29 | Weekly sync"); nil for a quick meeting.
        var meetName: String?

        /// The meeting app and name: window titles first, then the Meet page.
        var detected: (title: String?, app: String?) {
            let found = MeetingTitle.detect(windows)
            return found.app == "Meet" && found.title == nil ? (meetName, "Meet") : found
        }
    }

    /// Apps whose shown name differs from the one `MeetingTitle` uses: Zoom's bundle is "zoom.us" but
    /// macOS names the running app "Zoom", so Zoom was never looked at (2026-11-06).
    static let byBundle = ["us.zoom.xos": MeetingTitle.zoom]

    private static func apps() -> [(NSRunningApplication, String)] {
        let names = MeetingTitle.browsers + callApps
        return NSWorkspace.shared.runningApplications.compactMap { app in
            // Regular apps only: helper processes ("Google Chrome Helper (Renderer)", dozens of them) have no
            // windows and each one could hold the lookup for the whole AX timeout — that made Start take 6–8 s.
            guard app.activationPolicy == .regular,
                  let name = app.bundleIdentifier.flatMap({ byBundle[$0] }) ?? app.localizedName,
                  names.contains(where: { name.hasPrefix($0) }) else { return nil }
            return (app, name)
        }
    }

    /// Asks Chromium and Electron apps to build their accessibility tree.
    static func keepAccessibilityBuilt() {
        for (app, _) in apps() {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.3)
            AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }
    }

    /// Titles of windows and browser tabs, and the mute button of a call (Teams, Zoom, or a Meet tab), within `limit`.
    /// `name: false` (the mute watch) stops at the mute button instead of walking a Meet page on for its name.
    static func scan(limit: TimeInterval, name: Bool = true) -> Scan {
        let deadline = Date().addingTimeInterval(limit)
        var scan = Scan()
        var callRoots: [(element: AXUIElement, window: Int)] = []
        for (app, name) in apps() {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.3)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
                  let list = value as? [AXUIElement] else {
                continue
            }
            let browser = MeetingTitle.browsers.contains(name)
            for window in list {
                let title = string(window, kAXTitleAttribute)
                guard !title.isEmpty else { continue }
                scan.windows.append(MeetingTitle.Window(app: name, title: title))
                let index = scan.windows.count - 1
                if browser {
                    let tabs = tabTitles(window, until: deadline)
                    scan.windows += tabs.filter { $0 != title }.map { MeetingTitle.Window(app: name, title: $0) }
                    // Only a window showing Meet has the call controls in its tree (background tabs don't).
                    if MeetingTitle.detect([MeetingTitle.Window(app: name, title: title)]).app == "Meet" { callRoots.append((window, index)) }
                } else {
                    callRoots.append((window, index))
                }
            }
            // Zoom hides its toolbar while the pointer is away, but its Meeting menu always has
            // "Mute Audio" / "Unmute Audio" (2026-11-06: no mute button among 1421 elements).
            if name == MeetingTitle.zoom, let index = scan.windows.lastIndex(where: { $0.app == name }) {
                var bar: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXMenuBarAttribute as CFString, &bar) == .success, let bar {
                    callRoots.append((bar as! AXUIElement, index))
                }
            }
        }
        // One breadth-first walk over all call windows together: a chat window walked first must not use up the time.
        // A Meet page is walked on past its mute button, for the meeting name in its bottom bar.
        var queue = callRoots
        let meetWindows = name ? Set(callRoots.map(\.window).filter { MeetingTitle.browsers.contains(scan.windows[$0].app) }) : []
        while !queue.isEmpty, scan.visited < 20_000, Date() < deadline {
            let (element, window) = queue.removeFirst()
            AXUIElementSetMessagingTimeout(element, 0.3)
            scan.visited += 1
            let role = string(element, kAXRoleAttribute)
            if meetWindows.contains(window), scan.meetName == nil, role == kAXStaticTextRole {
                let text = [string(element, kAXValueAttribute), string(element, kAXTitleAttribute)].first { !$0.isEmpty } ?? ""
                if MeetingTitle.isClock(text) {
                    scan.meetName = barTexts(around: element).flatMap(MeetingTitle.meetPageName)
                }
            }
            if scan.mute == nil, role == kAXButtonRole || role == kAXCheckBoxRole || role == kAXMenuItemRole, MuteButton.label(element) != nil {
                scan.mute = MuteButton(element: element)
                scan.windows[window].inCall = true
            }
            if scan.mute != nil, meetWindows.isEmpty || scan.meetName != nil { break }
            queue += children(element).map { ($0, window) }
        }
        return scan
    }

    /// Texts in order around a Meet clock: its parent's subtree, or the grandparent's when the parent holds
    /// only the clock.
    private static func barTexts(around clock: AXUIElement) -> [String]? {
        var node = clock
        for _ in 0..<3 {
            guard let up = parent(node) else { return nil }
            node = up
            let texts = textsInOrder(node, depth: 4)
            if texts.count >= 2 { return texts }
        }
        return nil
    }

    private static func textsInOrder(_ element: AXUIElement, depth: Int) -> [String] {
        var texts: [String] = []
        if string(element, kAXRoleAttribute) == kAXStaticTextRole {
            let text = [string(element, kAXValueAttribute), string(element, kAXTitleAttribute)].first { !$0.isEmpty } ?? ""
            if !text.isEmpty { texts.append(text) }
        }
        if depth > 0 { for child in children(element) { texts += textsInOrder(child, depth: depth - 1) } }
        return texts
    }

    private static func parent(_ element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    /// Tab titles of a browser window: the radio buttons of its tab strip, near the top of the tree.
    private static func tabTitles(_ window: AXUIElement, until deadline: Date) -> [String] {
        var queue: [(AXUIElement, Int)] = [(window, 0)]
        var titles: [String] = []
        var visited = 0
        while !queue.isEmpty, visited < 600, Date() < deadline {
            let (element, depth) = queue.removeFirst()
            visited += 1
            if string(element, kAXRoleAttribute) == kAXTabGroupRole {
                titles += children(element).map { string($0, kAXTitleAttribute) }.filter { !$0.isEmpty }
                continue
            }
            if depth < 6 { queue += children(element).map { ($0, depth + 1) } }
        }
        return titles
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    static func string(_ element: AXUIElement, _ name: String) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return "" }
        return value as? String ?? ""
    }
}

/// A call's mute control (Teams, Zoom, Meet).
final class MuteButton: @unchecked Sendable {
    let element: AXUIElement
    init(element: AXUIElement) { self.element = element }

    /// The label that reads as a mute control, from its title or description.
    static func label(_ element: AXUIElement) -> String? {
        for name in [kAXTitleAttribute, kAXDescriptionAttribute] {
            let text = MeetingApps.string(element, name)
            if MeetingTitle.micMuted(byLabel: text) != nil { return text }
        }
        return nil
    }

    /// true = muted now; nil when it no longer reads as a mute control.
    var muted: Bool? { Self.label(element).flatMap { MeetingTitle.micMuted(byLabel: $0) } }
}

/// Twice a second, off the main queue, reports mute changes on the main queue. Without a button it looks for
/// one every 3 s for a minute, then every 30 s (a look walks the windows for up to 2 s). When the button stops
/// reading (call ended) it reports "not muted" and looks again.
final class MuteWatch: @unchecked Sendable {
    private let timer: DispatchSourceTimer

    init(_ found: MuteButton?, onChange: @escaping @MainActor (Bool) -> Void) {
        timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "dev.shepit.mutewatch"))
        var button = found
        var last: Bool?
        var misses = 0
        var tick = 0
        var looks = 0
        timer.schedule(deadline: .now(), repeating: 0.5)
        timer.setEventHandler {
            tick += 1
            if button == nil {
                guard tick % (looks < 20 ? 6 : 60) == 0 else { return }
                looks += 1
                button = MeetingApps.scan(limit: 2, name: false).mute
                return
            }
            let state = button?.muted
            if state == nil { misses += 1 } else { misses = 0 }
            if misses >= 6 {
                button = nil
                misses = 0
            }
            let now = state ?? (button == nil ? false : last ?? false)
            if now != last {
                last = now
                DispatchQueue.main.async { MainActor.assumeIsolated { onChange(now) } }
            }
        }
        timer.resume()
    }

    func cancel() { timer.cancel() }
}
