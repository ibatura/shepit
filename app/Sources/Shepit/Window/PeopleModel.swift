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
            suggestions = [] // another person's
            suggest()
        }
    }
    /// The period of Who talked how much and the person's meetings, remembered.
    var period: StatsPeriod {
        didSet {
            defaults.set(period, section: "people")
            tally()
        }
    }
    /// Who talked how much, for the chosen person in `period`.
    private(set) var talk: [StatisticsPage.Tile] = []
    /// The chosen person's meetings in `period`, newest first.
    private(set) var meetingRows: [PeoplePage.MeetingRow] = []
    /// May also be in, for the chosen person (voices design §6): read off the main thread with the list and when the
    /// choice changes; a reload keeps them until the new read.
    private(set) var suggestions: [PeoplePage.Suggestion] = []
    var question: Question?
    /// A change that could not be made, for an alert.
    var notice: MeetingsModel.Notice?

    var chosen: PeoplePage.Person? { people.first { $0.id == selection } }

    /// What a back or forward step to person `id` is called in its hint (back and forward design §5–6); nil when People
    /// no longer lists them: merged, or left with no lines. Asked of the store, as the list is read only when the section
    /// appears and edits in Meetings can leave it behind; a read that fails names nothing ("") rather than dropping the step.
    func describe(_ id: Int) -> String? {
        do {
            guard let person = try store.listed(person: id) else { return nil }
            return person.you ? settings().myName() : person.name ?? ""
        } catch { return "" }
    }

    @ObservationIgnored private let store: MeetingStore
    @ObservationIgnored private let settings: () -> ShepitCore.Settings
    @ObservationIgnored private let defaults: UserDefaults
    /// Every listed meeting, for the titles of the chosen person's meetings and suggestions.
    @ObservationIgnored private var meetings: [MeetingStore.Meeting] = []
    /// Everyone's voice prints and the store's version they were read at; read with a suggestion that needs them, since
    /// they need every sample kept, and again only once the store has changed.
    @ObservationIgnored private var prints: (version: Int, prints: [Int: Voices.Print])?
    /// The read of `suggestions` under way.
    @ObservationIgnored private(set) var suggesting: Task<Void, Never>?

    /// `settings`: your name, as it is now.
    init(store: MeetingStore, settings: @escaping () -> ShepitCore.Settings, defaults: UserDefaults = .standard) {
        self.store = store
        self.settings = settings
        self.defaults = defaults
        let remembered = defaults.integer(forKey: "peopleSelection")
        selection = remembered == 0 ? nil : remembered
        period = defaults.period(section: "people")
    }

    func reload() {
        do {
            meetings = try store.meetings()
            people = PeoplePage.people(try store.summaries(), you: settings().myName(), now: Date())
        } catch {
            NSLog("Shepit people: %@", String(describing: error))
        }
        tally()
        suggest()
    }

    /// The chosen person's lines are read for `period` only: You is in every meeting.
    private func tally() {
        var presences: [MeetingStore.Presence]?
        if let person = chosen {
            do {
                presences = try store.presences(of: person.id, in: period.range(now: Date()))
            } catch {
                NSLog("Shepit people: %@", String(describing: error))
            }
        }
        talk = presences.map(PeoplePage.talk) ?? []
        meetingRows = presences.map { PeoplePage.meetings($0, meetings: meetings) } ?? []
    }

    /// None for You, or while Remember voices is off: no voice is recognised then. Read off the main thread in one step,
    /// the prints with them when ours are older than the store (query plans design §7.5), one read at a time: a read that
    /// ends after the choice, the store or Remember voices changed is not shown, and reads again.
    private func suggest() {
        guard let person = chosen, !person.isYou, settings().rememberVoices else {
            suggestions = []
            return
        }
        guard suggesting == nil else { return } // it checks the choice when it ends
        let version = store.version, file = store.file
        let known = prints.flatMap { $0.version == version ? $0.prints : nil }
        suggesting = Task {
            var found: [Int: String] = [:]
            do {
                let read = try await MeetingStore.suggestions(in: file, for: person.id, prints: known)
                found = read.found
                if let read = read.prints { prints = (version, read) }
            } catch {
                NSLog("Shepit suggestions: %@", String(describing: error))
            }
            suggesting = nil
            guard chosen?.id == person.id, store.version == version, settings().rememberVoices else { return suggest() }
            suggestions = PeoplePage.suggestions(found, meetings: meetings)
        }
    }

    /// Name them: of the `suggestions` shown, the people in the `checked` meetings become `person`; the rest aren't
    /// suggested again.
    func name(_ person: PeoplePage.Person, suggestions: [PeoplePage.Suggestion], checked: Set<Int>) async {
        let keys = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.id, $0.key) })
        await apply("Can't name \(person.name)", notes: meetings.filter { checked.contains($0.id) }) {
            try store.nameSuggested(person.id, named: keys.filter { checked.contains($0.key) },
                                    declined: keys.filter { !checked.contains($0.key) })
        }
    }

    /// A name typed in a person's title (voices design §6): saved in every meeting and note, or a question when another
    /// person has it, also one People doesn't list (no lines left), or You.
    func rename(_ person: PeoplePage.Person, typed: String) async {
        guard !person.isYou, let name = MeetingPage.name(typed), let key = Names.key(name), name != person.name else { return }
        let taken = (try? store.person(named: name, except: person.id)).flatMap { $0 }
        if let other = people.first(where: { $0.id != person.id && Names.key($0.name) == key })
            ?? taken.map({ found in people.first { $0.id == found.id } ?? PeoplePage.unlisted(found.id, name: found.name) }) {
            question = .taken(person, name: name, by: other)
        } else {
            await save(person, name)
        }
    }

    /// Keep both, the third answer to `.taken`: the name is saved anyway, two people with one name.
    func keepBoth(_ question: Question) async {
        self.question = nil
        if case .taken(let person, let name, _) = question { await save(person, name) }
    }

    private func save(_ person: PeoplePage.Person, _ name: String) async {
        await apply("Can't rename \(person.name)", notes: (try? store.meetings(of: person.id)) ?? []) {
            try store.rename(person: person.id, to: name)
        }
    }

    /// Merge into…: `person`'s meetings go to `other`, who is chosen next.
    func merge(_ person: PeoplePage.Person, into other: PeoplePage.Person) async {
        if await apply("Can't merge \(person.name)", notes: (try? store.meetings(of: person.id)) ?? [], {
            try store.merge(person: person.id, into: other.id, myName: settings().myName())
        }) {
            selection = other.id
        }
    }

    /// The answer to `question`: yes deletes or merges.
    func answer(_ question: Question, yes: Bool) async {
        self.question = nil
        guard yes else { return }
        switch question {
        case .deleteVoice(let person): await apply("Voices not deleted") { try store.deleteVoice(person.id) }
        case .deleteAll: await apply("Voices not deleted") { try store.deleteAllVoices() }
        case .merge(let person, let other), .taken(let person, _, let other): await merge(person, into: other)
        }
    }

    /// Runs a change and reads the list again; false, with a notice, when it failed. The `notes` it rewrites are read off
    /// the main thread first: a note in iCloud Drive is downloaded when read, and the change reads and writes each one
    /// on the main thread, in one transaction.
    @discardableResult private func apply(_ failed: String, notes: [MeetingStore.Meeting] = [], _ change: () throws -> Void) async -> Bool {
        let urls = notes.map { URL(fileURLWithPath: $0.path) }
        await Task.detached { for url in urls { _ = try? Data(contentsOf: url) } }.value
        defer {
            suggestions = [] // the change may have named or deleted them; read again
            reload()
        }
        do {
            try change()
            return true
        } catch {
            notice = .init(title: failed, message: error.localizedDescription)
            return false
        }
    }
}
