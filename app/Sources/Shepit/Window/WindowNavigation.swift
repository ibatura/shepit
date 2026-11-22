import Foundation
import Observation
import ShepitCore

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
/// Window state: the section, the Settings page and the collapsed sidebar are kept in the app's preferences, not in
/// settings.json; the history only in memory, while Shepit runs.
@MainActor
@Observable
final class WindowNavigation {
    var section: WindowSection { didSet { defaults.set(section.rawValue, forKey: "windowSection") } }
    var settingsSection: SettingsModel.Section { didSet { defaults.set(settingsSection.rawValue, forKey: "settingsSection") } }
    /// The sidebar shows only the sections' icons (design §10).
    var sidebarCollapsed: Bool { didSet { defaults.set(sidebarCollapsed, forKey: "sidebarCollapsed") } }
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
        sidebarCollapsed = defaults.bool(forKey: "sidebarCollapsed")
        history.visit(place)
        recordChanges()
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

    func back() { show(history.back(alive: exists)) }
    func forward() { show(history.forward(alive: exists)) }
    var canGoBack: Bool { history.peekBack(alive: exists) != nil }
    var canGoForward: Bool { history.peekForward(alive: exists) != nil }
    var backHint: String { hint("Back", history.peekBack(alive: exists)) }
    var forwardHint: String { hint("Forward", history.peekForward(alive: exists)) }

    /// The running transcript ended: listed as meeting `id`, its steps become that meeting's; not listed (nil: no entries,
    /// removed, or listing failed), they go, or the next transcript would bring them back to life.
    func finished(running id: Int?) {
        history.replace(.meetings(.running), with: id.map { .meetings(.meeting($0)) })
    }

    /// Every change of place is a step, wherever it comes from: a list, a link, the menu, the window closed or open. The
    /// place is read on the main actor's next turn, so a change made in one go (Open in Meetings sets the section and the
    /// meeting) is one step; showing a step back or forward gives that step again, which the history ignores.
    private func recordChanges() {
        withObservationTracking { _ = place } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.history.visit(self.place)
                self.recordChanges()
            }
        }
    }

    /// The section and its choice.
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

    /// What a step's hint calls it after its section's name: "" for nothing more; nil when the step is gone. The
    /// sections answer for their own choices.
    private func describe(_ place: WindowPlace) -> String? {
        switch place {
        case .meetings(let choice?): meetings.describe(choice)
        case .people(let id?): people.describe(id)
        case .settings(let page): page.rawValue
        case .section, .meetings(nil), .people(nil): ""
        }
    }

    private func exists(_ place: WindowPlace) -> Bool { describe(place) != nil }

    /// "Back to People: Olena K.", "Forward to Home"; just "Back" with nowhere to go (design §6).
    private func hint(_ word: String, _ place: WindowPlace?) -> String {
        guard let place, let name = describe(place) else { return word }
        return "\(word) to \(place.section.rawValue)" + (name.isEmpty ? "" : ": \(name)")
    }
}
