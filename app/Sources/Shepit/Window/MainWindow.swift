import AppKit
import Observation
import ShepitCore
import SwiftUI

/// The sidebar's items (window shell design §4.1).
enum WindowSection: String, CaseIterable, Identifiable {
    case home = "Home"
    case meetings = "Meetings"
    case dictations = "Dictations"
    case dictionary = "Dictionary"
    case people = "People"
    case statistics = "Statistics"
    case settings = "Settings"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: "house"
        case .meetings: "person.2.wave.2"
        case .dictations: "text.bubble"
        case .dictionary: "character.book.closed"
        case .people: "person.crop.circle"
        case .statistics: "chart.bar"
        case .settings: "gearshape"
        }
    }
}

/// Which section the window shows. Window state, so it is kept in the app's preferences, not in settings.json.
@MainActor
@Observable
final class WindowNavigation {
    var section: WindowSection { didSet { defaults.set(section.rawValue, forKey: "windowSection") } }
    var settingsSection: SettingsModel.Section { didSet { defaults.set(settingsSection.rawValue, forKey: "settingsSection") } }
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        section = defaults.string(forKey: "windowSection").flatMap(WindowSection.init) ?? .home
        settingsSection = defaults.string(forKey: "settingsSection").flatMap(SettingsModel.Section.init) ?? .general
    }

    func openSettings(_ section: SettingsModel.Section) {
        settingsSection = section
        self.section = .settings
    }
}

/// What the window shows of the app's live state, kept current by `MainWindow.refresh`.
@MainActor
@Observable
final class WindowModel {
    var home = HomeModel.build(AppSnapshot())
}

/// The one window (window shell design §4). Shepit is a regular app with a Dock icon only while it is open.
@MainActor
final class MainWindow: NSObject, NSWindowDelegate {
    let navigation = WindowNavigation()
    private let live = WindowModel()
    private let model: SettingsModel
    private let actions: WindowActions
    private let home: () -> Home
    private var window: NSWindow?

    /// `home` builds Home from the app's state; it is asked only while the window is open.
    init(model: SettingsModel, actions: WindowActions, home: @escaping () -> Home) {
        self.model = model
        self.actions = actions
        self.home = home
    }

    var isOpen: Bool { window?.isVisible == true }

    /// After a change of state. Nothing is gathered for a closed window.
    func refresh() {
        guard isOpen else { return }
        let home = home()
        if home != live.home { live.home = home }
    }

    /// `section` nil: the section it had last.
    func show(_ section: WindowSection? = nil) {
        if let section { navigation.section = section }
        live.home = home()
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let controller = NSHostingController(rootView: MainView(model: model, actions: actions, live: live, navigation: navigation))
        controller.sizingOptions = [] // the window keeps its own size; SwiftUI's ideal size would shrink it
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.setContentSize(NSSize(width: 980, height: 640))
        window.contentMinSize = NSSize(width: 760, height: 480)
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("ShepitMain") // after center(): a remembered frame wins
        window.delegate = self
        return window
    }

    func windowWillClose(_ notification: Notification) {
        actions.resumeHotkeys() // a shortcut being recorded when the window closes would leave them off
        NSApp.setActivationPolicy(.accessory)
    }
}
