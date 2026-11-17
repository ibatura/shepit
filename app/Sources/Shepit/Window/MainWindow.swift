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

/// The sections with a model of their own, made once by `AppHost` and kept while the window is closed. A new one is
/// added here and in `MainView.section`.
@MainActor
struct WindowSections {
    let meetings: MeetingsModel
    let dictations: DictationsModel
    let statistics: StatisticsModel

    func reload(_ section: WindowSection) {
        switch section {
        case .meetings: meetings.reload()
        case .dictations: dictations.reload()
        case .statistics: statistics.reload()
        case .home, .dictionary, .people, .settings: break
        }
    }

    /// The window came back to the front on `section`: Meetings reads notes edited meanwhile in Obsidian or Finder,
    /// Statistics what was recorded meanwhile (its view is kept while the window is closed, so it doesn't appear again).
    /// Dictations follows its store's events and isn't read again: with thousands of entries loaded that takes a while.
    func returned(to section: WindowSection) {
        if section != .dictations { reload(section) }
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
    let sections: WindowSections
    private let live = WindowModel()
    private let model: SettingsModel
    private let actions: WindowActions
    private let snapshot: () -> AppSnapshot
    private var window: NSWindow?

    /// `snapshot` gives the app's state; it is asked only while the window is open.
    init(model: SettingsModel, actions: WindowActions, sections: WindowSections, snapshot: @escaping () -> AppSnapshot) {
        self.model = model
        self.actions = actions
        self.sections = sections
        self.snapshot = snapshot
        super.init()
        // Past midnight Today and the other periods move on: the open section reads its period again.
        NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.reload(self.navigation.section)
            }
        }
    }

    var isOpen: Bool { window?.isVisible == true }

    /// After a change of state. Nothing is gathered for a closed window.
    func refresh() {
        guard isOpen else { return }
        show(snapshot())
    }

    /// Home and the running transcript from one snapshot.
    private func show(_ snapshot: AppSnapshot) {
        let home = HomeModel.build(snapshot)
        if home != live.home { live.home = home }
        sections.meetings.setLive(snapshot.meeting)
    }

    /// A meeting was added: chosen if its running transcript was, and listed in the open Meetings section.
    func meetingAdded(_ id: Int) {
        sections.meetings.added(id)
        reload(.meetings)
    }

    /// The data of `section` changed (a meeting added, a dictation kept or deleted): the open window reads it again if
    /// it shows that section.
    func reload(_ section: WindowSection) {
        guard isOpen, navigation.section == section else { return }
        sections.reload(section)
    }

    /// `section` nil: the section it had last.
    func show(_ section: WindowSection? = nil) {
        if let section { navigation.section = section }
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        // activate() is only a request since macOS 14 and is refused while another app is active (seen on 26.4).
        // shortcut: Apple marks this call to be deprecated; if a later macOS ignores it, only the Dock icon works.
        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        show(snapshot()) // once visible: the snapshot then carries the live entries
    }

    private func makeWindow() -> NSWindow {
        let controller = NSHostingController(rootView: MainView(model: model, actions: actions, live: live, sections: sections,
                                                                navigation: navigation))
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

    func windowDidBecomeKey(_ notification: Notification) {
        sections.returned(to: navigation.section)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
