import AppKit
import ShepitCore

/// The main window (window shell design §4) and the appearance settings.
extension AppHost {
    /// Opens the window (menu, ⌘, or launching the app again); nil: on the section it had last.
    func showWindow(_ section: WindowSection? = nil) {
        gatherLookups()
        mainWindow.show(section)
    }

    /// After a change of state (a dictation, the meeting clock every second, a call, a settings write): the menu-bar
    /// title and the open window, with the lookups they have. No device or disk lookups here.
    func refreshStatus() {
        menu?.refreshTitle()
        mainWindow.refresh()
    }

    /// Devices, downloads and permissions change without an event we can rely on: the 2-s poll looks them up again
    /// for the open window.
    func refreshLookups() {
        guard mainWindow.isOpen else { return }
        gatherLookups()
        mainWindow.refresh()
    }

    /// After history.log was written or cleared: the open window lists it at once.
    func refreshHistory() {
        guard mainWindow.isOpen else { return }
        lookups.history = recentHistory
        mainWindow.refresh()
    }

    /// "system" follows macOS. The dictation overlay has its own colours.
    func applyTheme(_ theme: String) {
        NSApp.appearance = ["light": NSAppearance.Name.aqua, "dark": .darkAqua][theme].flatMap(NSAppearance.init(named:))
    }

    /// The accent colour is macOS's per-app preference `AppleAccentColor`, in Shepit's own preferences.
    func applyAccentColor(_ color: AccentColor) {
        let key = "AppleAccentColor"
        let code = color.code
        // Shepit's own preference only: `object(forKey:)` would also read the system-wide accent.
        let current = Bundle.main.bundleIdentifier.flatMap { UserDefaults.standard.persistentDomain(forName: $0)?[key] } as? Int
        guard current != code else { return }
        UserDefaults.standard.set(code, forKey: key)
        // macOS reads the preference when an app starts, and again on this notification (the one System Settings
        // sends; other apps re-read their own colour and find it unchanged).
        // shortcut: the notification is undocumented; if it stops working the colour applies at the next start.
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("AppleAquaColorVariantChanged"), object: nil, userInfo: nil, deliverImmediately: true)
    }
}
