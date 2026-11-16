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
    let meetings: MeetingsModel
    let dictations: DictationsModel
    private let live = WindowModel()
    private let model: SettingsModel
    private let actions: WindowActions
    private let snapshot: () -> AppSnapshot
    private var window: NSWindow?

    /// `snapshot` gives the app's state; it is asked only while the window is open.
    init(model: SettingsModel, actions: WindowActions, meetings: MeetingsModel, dictations: DictationsModel,
         snapshot: @escaping () -> AppSnapshot) {
        self.model = model
        self.actions = actions
        self.meetings = meetings
        self.dictations = dictations
        self.snapshot = snapshot
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
        meetings.setLive(snapshot.meeting)
    }

    /// A meeting was added: chosen if its running transcript was, and listed in the open Meetings section.
    func meetingAdded(_ id: Int) {
        meetings.added(id)
        meetingsChanged()
    }

    /// A meeting was added or changed: the open Meetings section lists it.
    func meetingsChanged() {
        guard isOpen, navigation.section == .meetings else { return }
        meetings.reload()
    }

    /// A dictation was kept or deleted, or the history cleared: the open Dictations section reads it again.
    func dictationsChanged() {
        guard isOpen, navigation.section == .dictations else { return }
        dictations.reload()
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
        let controller = NSHostingController(rootView: MainView(model: model, actions: actions, live: live, meetings: meetings,
                                                                dictations: dictations, navigation: navigation))
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

    /// Back from Obsidian or Finder: notes may have been edited, moved or deleted.
    func windowDidBecomeKey(_ notification: Notification) {
        meetingsChanged()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
