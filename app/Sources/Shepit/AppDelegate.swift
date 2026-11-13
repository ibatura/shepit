import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let host = AppHost()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = mainMenu()
        host.start()
    }

    /// Shown while the window is open (window shell design §4). It is also needed while Shepit is a menu-bar
    /// app: key equivalents (⌘C/⌘V/⌘X/⌘A/⌘Z in the dialogs) are found through the main menu, even when it is not shown.
    private func mainMenu() -> NSMenu {
        let app = NSMenu(title: "Shepit")
        app.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        app.addItem(.separator())
        app.addItem(withTitle: "Quit Shepit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let main = NSMenu()
        for menu in [app, edit, window] {
            let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
            item.submenu = menu
            main.addItem(item)
        }
        return main
    }

    @objc private func openSettings() {
        host.showWindow(.settings)
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

    /// Launching the app again opens the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        host.showWindow()
        return false
    }
}
