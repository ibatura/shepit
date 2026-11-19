import AppKit
import Observation
import ShepitCore

/// What the Meetings section shows (Meetings design §5–8). The list comes from the store and is read when the section
/// appears, when the window becomes active and after a meeting is added; the chosen note is read off the main thread.
/// Changes go through `MeetingStore`, which keeps the store and the note together.
@MainActor
@Observable
final class MeetingsModel {
    enum Selection: Hashable {
        case running, meeting(Int)
    }

    struct Open: Equatable {
        enum Content: Equatable {
            case reading, missing, page(MeetingPage.Page)
        }

        var meeting: MeetingStore.Meeting
        var content: Content
        /// Every real name Shepit knows, for the name fields.
        var suggestions: [String] = []
    }

    /// What the section asks before it changes or removes something.
    enum Question: Equatable {
        case merge(meeting: Int, person: String, into: String, name: String)
        case reset(meeting: Int)
        /// Delete all their lines…: the lines shown as theirs, by `name`.
        case deleteLines(meeting: Int, name: String, lines: Set<MeetingNote.Place>)
        case remove(MeetingStore.Meeting)
        case trash(MeetingStore.Meeting)
    }

    /// A message for an alert: a change that could not be made, or what Add notes… did.
    struct Notice: Equatable {
        var title: String
        var message: String
    }

    private(set) var meetings: [MeetingStore.Meeting] = []
    private(set) var missing: Set<Int> = []
    private(set) var live: LiveMeeting?
    private(set) var open: Open?
    var question: Question?
    var notice: Notice?
    /// Counts Cancels of a merge question: a name field that is still being edited then drops what was typed.
    private(set) var cancels = 0
    var selection: Selection? {
        didSet {
            guard selection != oldValue else { return }
            if case .meeting(let id) = selection { defaults.set(id, forKey: "meetingSelection") }
            load()
        }
    }

    @ObservationIgnored let store: MeetingStore
    @ObservationIgnored private let settings: () -> ShepitCore.Settings
    @ObservationIgnored private let defaults: UserDefaults
    /// The meeting added last: Name people on the "Transcript ready" panel opens it.
    @ObservationIgnored private var lastAdded: Int?
    @ObservationIgnored private var reading: Task<Void, Never>?

    /// `settings`: the meetings folder, `meetingFileName` and your name, as they are now.
    init(store: MeetingStore, settings: @escaping () -> ShepitCore.Settings, defaults: UserDefaults = .standard) {
        self.store = store
        self.settings = settings
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
        load()
    }

    /// Every refresh of the open window: the running transcript from the snapshot.
    func setLive(_ meeting: LiveMeeting?) {
        if meeting != live { live = meeting }
    }

    /// A meeting was added (nil: one could not be). When it is the running transcript that finished (chosen as `.running`),
    /// it stays chosen.
    func added(_ id: Int?) {
        lastAdded = id
        if let id, selection == .running { selection = .meeting(id) }
    }

    /// Name people on the "Transcript ready" panel: the meeting just added.
    func chooseLastAdded() {
        if let lastAdded { selection = .meeting(lastAdded) }
    }

    private func load() {
        reading?.cancel()
        guard case .meeting(let id) = selection, let meeting = meetings.first(where: { $0.id == id }) else {
            open = nil
            return
        }
        guard !missing.contains(id) else {
            open = Open(meeting: meeting, content: .missing)
            return
        }
        if open?.meeting.id != id { open = Open(meeting: meeting, content: .reading) } // a re-read keeps the old page: no flicker
        let people = (try? store.people(id)) ?? [], lines = (try? store.lines(id)) ?? []
        let suggestions = (try? store.knownNames()) ?? []
        let url = URL(fileURLWithPath: meeting.path)
        // A note in iCloud Drive that macOS has offloaded is downloaded on read: not on the main thread.
        reading = Task {
            let text = await Task.detached { try? String(contentsOf: url, encoding: .utf8) }.value
            guard !Task.isCancelled, selection == .meeting(id) else { return }
            guard let text else {
                missing.insert(id)
                open = Open(meeting: meeting, content: .missing)
                return
            }
            let page = MeetingPage.page(people: people, lines: lines, you: meeting.you, entries: MeetingNote.parse(text).entries)
            open = Open(meeting: meeting, content: .page(page), suggestions: suggestions)
        }
    }

    // MARK: Changes (Meetings design §8)

    // Each change names its meeting: a field saved when it loses focus can be saved after another meeting was chosen.

    /// A name typed for a person: saved, or a merge question when another person of the meeting has it.
    func name(_ meeting: Int, person: String, typed: String) async {
        let people = (try? store.people(meeting)) ?? []
        let name = MeetingPage.name(typed)
        // Unchanged when it shows the same: a person without a name shows its label.
        guard (name ?? person) != (people.first { $0.key == person }?.name ?? person) else { return }
        if let name, let other = MeetingPage.clash(people: people, lines: (try? store.lines(meeting)) ?? [], person: person, name: name) {
            question = .merge(meeting: meeting, person: person, into: other, name: name)
            return
        }
        await change(meeting) { try store.setName(meeting, person: person, to: name) }
    }

    func merge(_ meeting: Int, person: String, into: String) async {
        await change(meeting) { try store.merge(meeting, person: person, into: into) }
    }

    func give(_ meeting: Int, line: MeetingNote.Place, to person: String) async {
        await change(meeting) { try store.give(meeting, line: line, to: person) }
    }

    func giveToNewPerson(_ meeting: Int, line: MeetingNote.Place) async {
        await change(meeting) { try store.give(meeting, line: line, to: try store.newPerson(meeting)) }
    }

    /// Delete line, and the answer to Delete all their lines… (the author, 2026-11-19).
    func delete(_ meeting: Int, lines: Set<MeetingNote.Place>) async {
        await edit(meeting) { try store.delete($0, lines: lines) }
    }

    /// The meeting's name (§8): the store, the note's title and file name, `meeting-names.json`. False when it failed.
    @discardableResult func rename(_ meeting: MeetingStore.Meeting, typed: String) -> Bool {
        let title = MeetingPage.name(typed)
        guard title != meeting.title else { return true }
        do {
            try store.rename(meeting, to: title, template: settings().meetingFileName,
                             namesFile: Paths.dataDir.appending(path: MeetingNames.fileName))
        } catch {
            failed("Can't rename", meeting.path, error)
            return false
        }
        reload()
        return true
    }

    /// Add notes… (§4): notes made before the meetings list, or kept elsewhere.
    func addNotes() {
        let settings = settings()
        guard let notes = choose(message: "Choose meeting notes to add to the list", prompt: "Add", several: true,
                                 in: settings.meetingsFolderURL(home: Paths.home)) else { return }
        // The note being recorded is listed when it is finished. Already listed (nil), not a transcript or unreadable (throws): skipped.
        let added = notes.filter { $0.path != live?.note && (try? store.add(note: $0, you: settings.myName())) != nil }.count
        let skipped = notes.count - added
        notice = Notice(title: added == 1 ? "1 note added" : "\(added) notes added",
                        message: skipped == 0 ? "" : "\(skipped) skipped: already in the list, being recorded, not a transcript, or can't be read.")
        reload()
    }

    /// Locate note…: another file becomes this meeting's note; its entries are paired again.
    func locate() {
        guard let meeting = open?.meeting,
              let url = choose(message: "Where is the note of “\(MeetingPage.title(meeting.title, meeting.app))”?", prompt: "Use this note",
                               several: false, in: URL(fileURLWithPath: meeting.path).deletingLastPathComponent())?.first else { return }
        if url.path == live?.note {
            notice = Notice(title: "Can't use this note", message: "It is the transcript being recorded now.")
            return
        }
        if let other = meetings.first(where: { $0.path == url.path && $0.id != meeting.id }) {
            notice = Notice(title: "Can't use this note", message: "It is already in the list as “\(MeetingPage.title(other.title, other.app))”.")
            return
        }
        do {
            try store.relink(meeting.id, path: url.path)
        } catch {
            failed("Can't use", url.path, error)
        }
        reload()
    }

    /// The answer to `question`.
    func answer(_ question: Question, yes: Bool) async {
        self.question = nil
        guard yes else {
            if case .merge = question { cancels += 1 }
            return
        }
        switch question {
        case .merge(let meeting, let person, let into, _): await merge(meeting, person: person, into: into)
        case .reset(let meeting): await change(meeting) { try store.reset(meeting) }
        case .deleteLines(let meeting, _, let lines): await delete(meeting, lines: lines)
        case .remove(let meeting): remove(meeting, trash: false)
        case .trash(let meeting): remove(meeting, trash: true)
        }
    }

    private func remove(_ meeting: MeetingStore.Meeting, trash: Bool) {
        do {
            try store.remove(meeting, trash: trash)
        } catch {
            failed("Can't remove", meeting.path, error)
        }
        if selection == .meeting(meeting.id) { selection = nil }
        reload()
    }

    private func change(_ id: Int, _ body: () throws -> Void) async {
        await edit(id) { try store.change([$0], body) }
    }

    /// The note is read off the main thread first, as People does: a note in iCloud Drive that macOS has offloaded is
    /// downloaded on read, and the change reads and writes it on the main thread.
    private func edit(_ id: Int, _ body: (MeetingStore.Meeting) throws -> Void) async {
        guard let meeting = meetings.first(where: { $0.id == id }), !missing.contains(id) else { return }
        let url = URL(fileURLWithPath: meeting.path)
        await Task.detached { _ = try? Data(contentsOf: url) }.value
        // Moved or deleted since it was opened: nothing changes (the store's change would skip the note and change only
        // the database), and the meeting shows "note not found".
        guard FileManager.default.fileExists(atPath: meeting.path) else {
            missing.insert(id)
            failed("Can't change", meeting.path, CocoaError(.fileNoSuchFile))
            load()
            return
        }
        do {
            try body(meeting)
        } catch {
            failed("Can't change", meeting.path, error)
        }
        load()
    }

    private func failed(_ what: String, _ path: String, _ error: Error) {
        notice = Notice(title: "\(what) \(URL(fileURLWithPath: path).lastPathComponent)", message: error.localizedDescription)
    }

    /// A file chooser for `.md` notes, opening in `folder` when it exists; nil when cancelled.
    private func choose(message: String, prompt: String, several: Bool, in folder: URL) -> [URL]? {
        NSApp.activate()
        let chooser = NSOpenPanel()
        chooser.message = message
        chooser.prompt = prompt
        chooser.allowedContentTypes = [.init(filenameExtension: "md")!]
        chooser.allowsMultipleSelection = several
        if FileManager.default.fileExists(atPath: folder.path) { chooser.directoryURL = folder }
        return chooser.runModal() == .OK ? chooser.urls : nil
    }
}
