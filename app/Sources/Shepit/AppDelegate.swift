import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let host = AppHost()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = Self.editMenu()
        host.start()
    }

    /// A menu-bar app has no menu bar of its own, so without this ⌘C/⌘V/⌘X/⌘A/⌘Z do nothing in Settings
    /// and the dialogs: key equivalents are found through the main menu, even when it is never shown.
    static func editMenu() -> NSMenu {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        let main = NSMenu()
        main.addItem(NSMenuItem(title: "Shepit", action: nil, keyEquivalent: "")) // the app menu slot
        main.addItem(editItem)
        return main
    }

    /// Quit asks first during a meeting; engines are unloaded before exit (whisper.cpp's Metal teardown
    /// aborts if a context is still alive). Logout and shutdown don't ask.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if !loggingOut, !host.confirmQuitDuringMeeting() { return .terminateCancel }
        Task {
            await host.prepareToQuit()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private var loggingOut: Bool {
        // A logout or shutdown sends a quit Apple Event with a reason.
        guard let reason = NSAppleEventManager.shared().currentAppleEvent?.attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason))?.typeCodeValue
        else { return false }
        return [kAELogOut, kAEReallyLogOut, kAEShowShutdownDialog, kAEShutDown, kAERestart, kAEShowRestartDialog].map { OSType($0) }.contains(reason)
    }

    /// Launching the app again opens Settings (`04-settings.md` §3).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        host.showSettings()
        return false
    }
}
