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

/// A section and what is chosen in it: a step of back and forward (back and forward design §4).
enum WindowPlace: Equatable {
    /// Home, Dictations, Dictionary or Statistics.
    case section(WindowSection)
    case meetings(MeetingsModel.Selection?)
    case people(Int?)
    case settings(SettingsModel.Section)

    var section: WindowSection {
        switch self {
        case .section(let section): section
        case .meetings: .meetings
        case .people: .people
        case .settings: .settings
        }
    }
}

/// Which section the window shows, and the way back and forward through what it showed (back and forward design §5).
/// Window state: the section and the Settings page are kept in the app's preferences, not in settings.json; the history
/// only in memory, while Shepit runs.
@MainActor
@Observable
final class WindowNavigation {
    var section: WindowSection { didSet { defaults.set(section.rawValue, forKey: "windowSection") } }
    var settingsSection: SettingsModel.Section { didSet { defaults.set(settingsSection.rawValue, forKey: "settingsSection") } }
    private var history = BackForward<WindowPlace>()
    @ObservationIgnored private let meetings: MeetingsModel
    @ObservationIgnored private let people: PeopleModel
    @ObservationIgnored private let defaults: UserDefaults

    /// The first step is the place the window starts on: the remembered section and choices.
    init(meetings: MeetingsModel, people: PeopleModel, defaults: UserDefaults = .standard) {
        self.meetings = meetings
        self.people = people
        self.defaults = defaults
        section = defaults.string(forKey: "windowSection").flatMap(WindowSection.init) ?? .home
        settingsSection = defaults.string(forKey: "settingsSection").flatMap(SettingsModel.Section.init) ?? .general
        history.visit(place)
    }

    func openSettings(_ section: SettingsModel.Section) {
        settingsSection = section
        self.section = .settings
    }

    /// What the window shows now: only the choice of the section shown counts.
    var place: WindowPlace {
        switch section {
        case .meetings: .meetings(meetings.selection)
        case .people: .people(people.selection)
        case .settings: .settings(settingsSection)
        case .home, .dictations, .dictionary, .statistics: .section(section)
        }
    }

    /// Every change of place (`MainView` calls it). Showing a step back or forward gives that step, which records nothing.
    func visit(_ place: WindowPlace) {
        history.visit(place)
    }

    func back() { show(history.back(alive: exists)) }
    func forward() { show(history.forward(alive: exists)) }
    var canGoBack: Bool { history.peekBack(alive: exists) != nil }
    var canGoForward: Bool { history.peekForward(alive: exists) != nil }
    var backHint: String { hint("Back", history.peekBack(alive: exists)) }
    var forwardHint: String { hint("Forward", history.peekForward(alive: exists)) }

    /// The running transcript was listed as meeting `id`: its steps become that meeting's.
    func finished(running id: Int) {
        history.replace(.meetings(.running), with: .meetings(.meeting(id)))
    }

    /// The section and its choice, in one go: one change of place.
    private func show(_ place: WindowPlace?) {
        guard let place else { return }
        switch place {
        case .meetings(let choice): meetings.selection = choice
        case .people(let id): people.selection = id
        case .settings(let page): settingsSection = page
        case .section: break
        }
        section = place.section
    }

    /// A removed meeting, or a person People no longer lists (merged, or left with no lines), is gone. Asked of the
    /// store, since the sections read their lists only when they appear and edits in Meetings can leave People's behind.
    private func exists(_ place: WindowPlace) -> Bool {
        do {
            switch place {
            case .meetings(.meeting(let id)?): return try meetings.store.meeting(id) != nil
            case .meetings(.running?): return meetings.live != nil
            case .people(let id?): return try meetings.store.lists(person: id)
            case .section, .meetings(nil), .people(nil), .settings: return true
            }
        } catch {
            return true // a failed read is no gone step: the history keeps it
        }
    }

    /// "Back to People: Olena K.", "Forward to Home"; just "Back" with nowhere to go (design §6).
    private func hint(_ word: String, _ place: WindowPlace?) -> String {
        guard let place else { return word }
        let chosen: String? = switch place {
        case .meetings(.meeting(let id)?): (try? meetings.store.meeting(id)).map { MeetingPage.title($0.title, $0.app) }
        case .meetings(.running?): "the running transcript"
        case .people(let id?): people.people.first { $0.id == id }?.name // nil while People's list is unread
        case .settings(let page): page.rawValue
        case .section, .meetings(nil), .people(nil): nil
        }
        return "\(word) to \(place.section.rawValue)" + (chosen.map { ": \($0)" } ?? "")
    }
}

/// The sections with a model of their own, made once by `AppHost` and kept while the window is closed. A new one is
/// added here and in `MainView.section`.
@MainActor
struct WindowSections {
    let meetings: MeetingsModel
    let dictations: DictationsModel
    let statistics: StatisticsModel
    let people: PeopleModel

    func reload(_ section: WindowSection) {
        switch section {
        case .meetings: meetings.reload()
        case .dictations: dictations.reload()
        case .statistics: statistics.reload()
        case .people: people.reload()
        case .home, .dictionary, .settings: break
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
    let navigation: WindowNavigation
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
        navigation = WindowNavigation(meetings: sections.meetings, people: sections.people)
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
        navigation.finished(running: id) // first: `added` then chooses it, which is no new step
        sections.meetings.added(id)
        reload(.meetings)
        reload(.people)
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
