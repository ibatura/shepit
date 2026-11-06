import AppKit
import ApplicationServices
import ShepitCore

/// Puts text into the target app: refocus, clipboard, ⌘V, restore the clipboard (port of paster.lua),
/// and reads the selection with a temporary ⌘C (port of selection.lua).
@MainActor
enum Paster {
    static let refocusDelay = 0.2
    static let restoreDelay = 1.0 // Electron apps (Slack, VS Code) read the clipboard late
    static let copyWait = 0.25
    static let keyV: CGKeyCode = 9 // physical V; works in the Ukrainian layout too (where it types «м»)
    static let keyC: CGKeyCode = 8

    static func paste(_ text: String, into app: AppRef?, refocus: Bool, restoreClipboard: Bool) async -> PasteOutcome {
        let pasteboard = NSPasteboard.general
        guard AXIsProcessTrusted() else {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return .copied
        }
        var delay = 0.0
        if refocus, let bundleID = app?.bundleID,
           let target = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           NSWorkspace.shared.frontmostApplication?.processIdentifier != target.processIdentifier {
            target.activate()
            delay = refocusDelay
        }
        let saved = restoreClipboard ? snapshot(pasteboard) : nil
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ours = pasteboard.changeCount
        if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
        press(keyV)
        if let saved {
            Task {
                try? await Task.sleep(for: .seconds(restoreDelay))
                guard pasteboard.changeCount == ours else { return } // the user copied something since
                restore(saved, to: pasteboard)
            }
        }
        return .pasted
    }

    /// The selected text in the frontmost app ("" when nothing is selected); the clipboard is restored.
    static func readSelection() async -> String {
        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)
        let before = pasteboard.changeCount
        press(keyC)
        try? await Task.sleep(for: .seconds(copyWait))
        guard pasteboard.changeCount != before else { return "" }
        let text = pasteboard.string(forType: .string) ?? ""
        restore(saved, to: pasteboard)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func press(_ key: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }

    /// Every item with every type, so images and rich text survive, not just plain text.
    private static func snapshot(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
    }

    private static func restore(_ saved: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let items = saved.map { types in
            let item = NSPasteboardItem()
            for (type, data) in types { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }
}
