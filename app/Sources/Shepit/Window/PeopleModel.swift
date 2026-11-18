import Foundation
import Observation
import ShepitCore

/// What the People section shows (voices design §6). The list is read from the meetings store when the section appears,
/// when the window becomes active and after a meeting is added or recognised; never while drawing.
@MainActor
@Observable
final class PeopleModel {
    /// What the section asks before it changes people or deletes voices.
    enum Question: Equatable {
        case deleteVoice(PeoplePage.Person)
        case deleteAll
        /// Merge into…
        case merge(PeoplePage.Person, into: PeoplePage.Person)
        /// A name typed for a person that another person has: merge into them, or keep both.
        case taken(PeoplePage.Person, name: String, by: PeoplePage.Person)
    }

    private(set) var people: [PeoplePage.Person] = []
    var selection: Int? {
        didSet {
            defaults.set(selection ?? 0, forKey: "peopleSelection")
            tally()
            suggest()
        }
    }
    /// Who talked how much counts this period (Dictations' periods), remembered.
    var period: Period {
        didSet {
            defaults.set(period.rawValue, forKey: "peoplePeriod")
            tally()
        }
    }
    /// Who talked how much, for the chosen person.
    private(set) var talk: [StatisticsPage.Tile] = []
    /// May also be in, for the chosen person (voices design §6): read with the list and when the choice changes.
    private(set) var suggestions: [PeoplePage.Suggestion] = []
    var question: Question?
    /// A change that could not be made, for an alert.
    var notice: MeetingsModel.Notice?

    var chosen: PeoplePage.Person? { people.first { $0.id == selection } }

    @ObservationIgnored private let store: MeetingStore
    @ObservationIgnored private let settings: () -> ShepitCore.Settings
    @ObservationIgnored private let defaults: UserDefaults
    /// What the list was built from, for the talk of another person or period without reading the store again.
    @ObservationIgnored private var presences: [MeetingStore.Presence] = []
    @ObservationIgnored private var meetings: [MeetingStore.Meeting] = []
    @ObservationIgnored private var wordsFilled = false

    /// `settings`: your name, as it is now.
    init(store: MeetingStore, settings: @escaping () -> ShepitCore.Settings, defaults: UserDefaults = .standard) {
        self.store = store
        self.settings = settings
        self.defaults = defaults
        let remembered = defaults.integer(forKey: "peopleSelection")
        selection = remembered == 0 ? nil : remembered
        period = defaults.string(forKey: "peoplePeriod").flatMap(Period.init) ?? .month
    }

    func reload() {
        do {
            presences = try store.presences()
            meetings = try store.meetings()
            people = PeoplePage.people(presences, meetings: meetings, you: settings().myName(), now: Date())
        } catch {
            NSLog("Shepit people: %@", String(describing: error))
        }
        tally()
        suggest()
    }

    /// The words of meetings listed before they were kept (voices design §7), once per run when the section first
    /// appears: each note is read off the main thread (a note in iCloud Drive may be downloaded), then the list again.
    func fillWords() async {
        guard !wordsFilled else { return }
        wordsFilled = true
        let older = (try? store.meetingsWithoutWords()) ?? []
        guard !older.isEmpty else { return }
        for meeting in older {
            let note = URL(fileURLWithPath: meeting.path)
            guard let text = await Task.detached(operation: { try? String(contentsOf: note, encoding: .utf8) }).value else { continue }
            do {
                try store.fillWords(meeting.id, entries: MeetingNote.parse(text).entries)
            } catch {
                NSLog("Shepit meeting words: %@", String(describing: error))
            }
        }
        reload()
    }

    private func tally() {
        talk = chosen.map { PeoplePage.talk($0.id, presences, meetings: meetings, period: period, now: Date()) } ?? []
    }

    /// None for You, or while Remember voices is off: no voice is recognised then.
    private func suggest() {
        guard let person = chosen, !person.isYou, settings().rememberVoices else {
            suggestions = []
            return
        }
        do {
            let found = Voices.suggestions(person.id, unnamed: try store.suggestedVoices(for: person.id),
                                           prints: Voices.prints(try store.voiceRows()))
            suggestions = PeoplePage.suggestions(found, meetings: meetings)
        } catch {
            NSLog("Shepit suggestions: %@", String(describing: error))
            suggestions = []
        }
    }

    /// Name them: of the `suggestions` shown, the people in the `checked` meetings become `person`; the rest aren't
    /// suggested again.
    func name(_ person: PeoplePage.Person, suggestions: [PeoplePage.Suggestion], checked: Set<Int>) {
        let keys = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.id, $0.key) })
        apply("Can't name \(person.name)") {
            try store.nameSuggested(person.id, named: keys.filter { checked.contains($0.key) },
                                    declined: keys.filter { !checked.contains($0.key) })
        }
    }

    /// A name typed in a person's title (voices design §6): saved in every meeting and note, or a question when another
    /// person has it. With `keepBoth`, saved anyway: two people with one name.
    func rename(_ person: PeoplePage.Person, typed: String, keepBoth: Bool = false) {
        guard !person.isYou, let name = MeetingPage.name(typed), let key = Names.key(name), name != person.name else { return }
        if !keepBoth, let other = people.first(where: { $0.id != person.id && Names.key($0.name) == key }) {
            question = .taken(person, name: name, by: other)
            return
        }
        apply("Can't rename \(person.name)") { try store.rename(person: person.id, to: name) }
    }

    /// Merge into…: `person`'s meetings go to `other`, who is chosen next.
    func merge(_ person: PeoplePage.Person, into other: PeoplePage.Person) {
        if apply("Can't merge \(person.name)", { try store.merge(person: person.id, into: other.id, myName: settings().myName()) }) {
            selection = other.id
        }
    }

    /// The answer to `question`: yes deletes or merges.
    func answer(_ question: Question, yes: Bool) {
        self.question = nil
        guard yes else { return }
        switch question {
        case .deleteVoice(let person): apply("Voices not deleted") { try store.deleteVoice(person.id) }
        case .deleteAll: apply("Voices not deleted") { try store.deleteAllVoices() }
        case .merge(let person, let other), .taken(let person, _, let other): merge(person, into: other)
        }
    }

    /// Runs a change and reads the list again; false, with a notice, when it failed.
    @discardableResult private func apply(_ failed: String, _ change: () throws -> Void) -> Bool {
        defer { reload() }
        do {
            try change()
            return true
        } catch {
            notice = .init(title: failed, message: error.localizedDescription)
            return false
        }
    }
}
