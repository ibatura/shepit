import AppKit
import Observation
import ShepitCore

/// The transcript being recorded, as the Meetings section shows it (Meetings design §7). Built from the session's memory.
struct LiveMeeting: Equatable {
    var state: MeetingState
    var title: String?
    var app: CallApp?
    var words: Int
    /// nil while the call app's mute button can't be read.
    var muted: Bool?
    var entries: [MeetingNote.Entry]
    /// The note's path, to choose the meeting once the transcript is ready.
    var note: String
}

/// What the Meetings section shows (Meetings design §5–7). The list comes from the store and is read when the section
/// appears, when the window becomes active and after a meeting is added; the chosen note is read off the main thread.
@MainActor
@Observable
final class MeetingsModel {
    enum Selection: Hashable {
        case running, meeting(Int)
    }

    struct Open: Equatable {
        var meeting: MeetingStore.Meeting
        /// nil while the note is being read.
        var page: MeetingPage.Page?
        /// Every real name Shepit knows, for the name fields.
        var suggestions: [String] = []
    }

    /// What the section asks before it changes or removes something.
    enum Question: Equatable {
        case merge(meeting: Int, person: String, into: String, name: String)
        case reset(meeting: Int)
        case remove(MeetingStore.Meeting)
        case trash(MeetingStore.Meeting)
    }

    private(set) var meetings: [MeetingStore.Meeting] = []
    private(set) var missing: Set<Int> = []
    private(set) var live: LiveMeeting?
    private(set) var open: Open?
    var question: Question?
    /// A change that could not be made, for an alert.
    var problem: String?
    var selection: Selection? {
        didSet {
            guard selection != oldValue else { return }
            if case .meeting(let id) = selection { defaults.set(id, forKey: "meetingSelection") }
            load()
        }
    }

    @ObservationIgnored let store: MeetingStore
    @ObservationIgnored private let liveSource: () -> LiveMeeting?
    @ObservationIgnored private let template: () -> String
    @ObservationIgnored private let defaults: UserDefaults
    /// The note of the transcript that was running, so it is chosen once it is in the list.
    @ObservationIgnored private var finishedNote: String?
    @ObservationIgnored private var reading: Task<Void, Never>?

    /// `template`: `meetingFileName`, for renaming a note.
    init(store: MeetingStore, live: @escaping () -> LiveMeeting?, template: @escaping () -> String, defaults: UserDefaults = .standard) {
        self.store = store
        liveSource = live
        self.template = template
        self.defaults = defaults
        let remembered = defaults.integer(forKey: "meetingSelection")
        selection = remembered == 0 ? nil : .meeting(remembered)
    }

    /// The list again, and the chosen meeting's note.
    func reload() {
        do {
            meetings = try store.meetings()
        } catch {
            NSLog("Shepit meetings list: %@", String(describing: error))
        }
        missing = Set(meetings.filter { !FileManager.default.fileExists(atPath: $0.path) }.map(\.id))
        followFinished()
        load()
    }

    /// Every refresh of the open window: the running transcript from memory.
    func refreshLive() {
        let now = liveSource()
        guard now != live else { return }
        if now == nil, let live { finishedNote = live.note }
        live = now
        followFinished()
    }

    /// Chooses the meeting of this note (Name people on the "Transcript ready" panel).
    func select(note: String) {
        reload()
        if let id = meetings.first(where: { $0.path == note })?.id { selection = .meeting(id) }
    }

    /// The running transcript turned into a finished meeting: it stays chosen.
    private func followFinished() {
        guard selection == .running, live == nil, let note = finishedNote,
              let id = meetings.first(where: { $0.path == note })?.id else { return }
        finishedNote = nil
        selection = .meeting(id)
    }

    private func load() {
        reading?.cancel()
        guard case .meeting(let id) = selection, let meeting = meetings.first(where: { $0.id == id }) else {
            open = nil
            return
        }
        guard !missing.contains(id) else {
            open = Open(meeting: meeting, page: nil)
            return
        }
        if open?.meeting.id != id { open = Open(meeting: meeting, page: nil) } // keeps the old page on a re-read: no flicker
        let people = (try? store.people(id)) ?? [], lines = (try? store.lines(id)) ?? []
        let suggestions = (try? store.knownNames()) ?? []
        let url = URL(fileURLWithPath: meeting.path)
        // A note in iCloud Drive that macOS has offloaded is downloaded on read: not on the main thread.
        reading = Task {
            let text = await Task.detached { try? String(contentsOf: url, encoding: .utf8) }.value
            guard !Task.isCancelled, selection == .meeting(id) else { return }
            guard let text else {
                missing.insert(id)
                open = Open(meeting: meeting, page: nil)
                return
            }
            open = Open(meeting: meeting, page: MeetingPage.page(people: people, lines: lines, you: meeting.you,
                                                                  entries: MeetingNote.parse(text).entries), suggestions: suggestions)
        }
    }

    // MARK: Changes (Meetings design §8)

    // Each change names its meeting: a field saved when it loses focus can be saved after another meeting was chosen.

    /// A name typed for a person: saved, or a merge question when another person of the meeting has it.
    func name(_ meeting: Int, person: String, typed: String) {
        let people = (try? store.people(meeting)) ?? []
        let stored = people.first { $0.key == person }?.name
        let name = MeetingPage.name(typed)
        guard name != stored, !(stored == nil && name == person) else { return } // unchanged: the label shows when there's no name
        if let name, let other = MeetingPage.clash(people: people, lines: (try? store.lines(meeting)) ?? [], person: person, name: name) {
            question = .merge(meeting: meeting, person: person, into: other, name: name)
            return
        }
        change(meeting) { try $0.setName($1, person: person, to: name) }
    }

    func merge(_ meeting: Int, person: String, into: String) {
        change(meeting) { try $0.merge($1, person: person, into: into) }
    }

    func give(_ meeting: Int, line: MeetingStore.Place, to person: String) {
        change(meeting) { try $0.give($1, line: line, to: person) }
    }

    func giveToNewPerson(_ meeting: Int, line: MeetingStore.Place) {
        change(meeting) { store, id in try store.give(id, line: line, to: try store.newPerson(id)) }
    }

    /// The meeting's name (§8): the store, the note's title and file name, `meeting-names.json`. False when it failed.
    @discardableResult func rename(_ meeting: MeetingStore.Meeting, typed: String) -> Bool {
        let title = MeetingPage.name(typed)
        guard title != meeting.title else { return true }
        do {
            try store.rename(meeting, to: title, template: template(), namesFile: Paths.dataDir.appending(path: MeetingNames.fileName))
        } catch {
            problem = "Can't rename \(URL(fileURLWithPath: meeting.path).lastPathComponent): \(error.localizedDescription)"
            return false
        }
        reload()
        return true
    }

    /// Locate note…: another file becomes this meeting's note; its entries are paired again.
    func locate() {
        guard let meeting = open?.meeting else { return }
        NSApp.activate()
        let chooser = NSOpenPanel()
        chooser.message = "Where is the note of “\(MeetingPage.title(meeting.title, meeting.app))”?"
        chooser.prompt = "Use this note"
        chooser.allowedContentTypes = [.init(filenameExtension: "md")!]
        let folder = URL(fileURLWithPath: meeting.path).deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: folder.path) { chooser.directoryURL = folder }
        guard chooser.runModal() == .OK, let url = chooser.url else { return }
        if let other = meetings.first(where: { $0.path == url.path && $0.id != meeting.id }) {
            problem = "This note is already in the list as “\(MeetingPage.title(other.title, other.app))”."
            return
        }
        do {
            try store.relink(meeting.id, path: url.path)
        } catch {
            problem = "Can't use \(url.lastPathComponent): \(error.localizedDescription)"
        }
        reload()
    }

    /// The answer to `question`; nil = Cancel.
    func answer(_ question: Question, yes: Bool) {
        self.question = nil
        guard yes else {
            load() // a name field that asked to merge shows the old name again
            return
        }
        switch question {
        case .merge(let meeting, let person, let into, _): merge(meeting, person: person, into: into)
        case .reset(let meeting): change(meeting) { try $0.reset($1) }
        case .remove(let meeting): remove(meeting, trash: false)
        case .trash(let meeting): remove(meeting, trash: true)
        }
    }

    private func remove(_ meeting: MeetingStore.Meeting, trash: Bool) {
        do {
            try store.transaction { // the note goes to the Trash only with its row, and the row only with the note
                try store.remove(meeting.id)
                if trash { try FileManager.default.trashItem(at: URL(fileURLWithPath: meeting.path), resultingItemURL: nil) }
            }
        } catch {
            problem = "Can't remove \(URL(fileURLWithPath: meeting.path).lastPathComponent): \(error.localizedDescription)"
        }
        if selection == .meeting(meeting.id) { selection = nil }
        reload()
    }

    /// A change to people or lines: the store and the note's headers together, or neither (§8). The note is read
    /// again right before writing, so edits made in Obsidian meanwhile stay.
    private func change(_ id: Int, _ body: (MeetingStore, Int) throws -> Void) {
        guard let meeting = meetings.first(where: { $0.id == id }), !missing.contains(id) else { return }
        let note = URL(fileURLWithPath: meeting.path)
        do {
            try store.transaction {
                let before = (people: try store.people(id), lines: try store.lines(id))
                try body(store, id)
                let after = (people: try store.people(id), lines: try store.lines(id))
                let text = try String(contentsOf: note, encoding: .utf8)
                let changed = MeetingPage.relabelled(text, before: before, after: after)
                if changed != text { try Data(changed.utf8).write(to: note, options: .atomic) }
            }
        } catch {
            problem = "Can't change \(note.lastPathComponent): \(error.localizedDescription)"
        }
        load()
    }
}
