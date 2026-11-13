import AppKit
import ShepitCore

/// The main window (window shell design §4) and the appearance settings.
extension AppHost {
    /// Opens the window (menu, ⌘, or launching the app again); nil: on the section it had last.
    func showWindow(_ section: WindowSection? = nil) {
        gatherLookups()
        mainWindow.show(section)
    }

    /// After a change of state: the menu-bar title, and the open window with its devices and files looked up again
    /// (the 2-s poll comes here too, so a plugged-in microphone or a finished download shows up).
    func refreshStatus() {
        if mainWindow.isOpen { gatherLookups() }
        refreshLive()
    }

    /// Only the live state changed (the meeting clock ticks every second): the lookups are reused.
    func refreshLive() {
        menu?.refreshTitle()
        mainWindow.refresh()
    }

    /// "system" follows macOS. The dictation overlay has its own colours.
    func applyTheme(_ theme: String) {
        NSApp.appearance = ["light": NSAppearance.Name.aqua, "dark": .darkAqua][theme].flatMap(NSAppearance.init(named:))
    }

    /// The accent colour is macOS's per-app preference `AppleAccentColor`, in Shepit's own preferences.
    func applyAccentColor(_ name: String) {
        let key = "AppleAccentColor"
        let code = Settings.accentColorCode(name)
        guard UserDefaults.standard.object(forKey: key) as? Int != code else { return }
        UserDefaults.standard.set(code, forKey: key)
        // macOS reads the preference when an app starts, and again on this notification (the one System Settings
        // sends; other apps re-read their own colour and find it unchanged).
        // shortcut: the notification is undocumented; if it stops working the colour applies at the next start.
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("AppleAquaColorVariantChanged"), object: nil, userInfo: nil, deliverImmediately: true)
    }
}
