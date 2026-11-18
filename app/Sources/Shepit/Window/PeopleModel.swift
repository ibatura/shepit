import Foundation
import Observation
import ShepitCore

/// What the People section shows (voices design §6). The list is read from the meetings store when the section appears,
/// when the window becomes active and after a meeting is added or recognised; never while drawing.
@MainActor
@Observable
final class PeopleModel {
    /// What the section asks before it deletes voices.
    enum Question: Equatable {
        case deleteVoice(PeoplePage.Person)
        case deleteAll
    }

    private(set) var people: [PeoplePage.Person] = []
    var selection: Int? { didSet { defaults.set(selection ?? 0, forKey: "peopleSelection") } }
    var question: Question?
    /// A deletion that failed: its error, for an alert.
    var failure: String?

    var chosen: PeoplePage.Person? { people.first { $0.id == selection } }

    @ObservationIgnored private let store: MeetingStore
    @ObservationIgnored private let settings: () -> ShepitCore.Settings
    @ObservationIgnored private let defaults: UserDefaults

    /// `settings`: your name, as it is now.
    init(store: MeetingStore, settings: @escaping () -> ShepitCore.Settings, defaults: UserDefaults = .standard) {
        self.store = store
        self.settings = settings
        self.defaults = defaults
        let remembered = defaults.integer(forKey: "peopleSelection")
        selection = remembered == 0 ? nil : remembered
    }

    func reload() {
        do {
            people = PeoplePage.people(try store.presences(), meetings: try store.meetings(), you: settings().myName(), now: Date())
        } catch {
            NSLog("Shepit people: %@", String(describing: error))
        }
    }

    /// The answer to `question`.
    func answer(_ question: Question, yes: Bool) {
        self.question = nil
        guard yes else { return }
        do {
            switch question {
            case .deleteVoice(let person): try store.deleteVoice(person.id)
            case .deleteAll: try store.deleteAllVoices()
            }
        } catch {
            failure = error.localizedDescription
        }
        reload()
    }
}
