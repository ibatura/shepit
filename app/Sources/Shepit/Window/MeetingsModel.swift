import Foundation
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
    }

    private(set) var meetings: [MeetingStore.Meeting] = []
    private(set) var missing: Set<Int> = []
    private(set) var live: LiveMeeting?
    private(set) var open: Open?
    var selection: Selection? {
        didSet {
            guard selection != oldValue else { return }
            if case .meeting(let id) = selection { defaults.set(id, forKey: "meetingSelection") }
            load()
        }
    }

    @ObservationIgnored let store: MeetingStore
    @ObservationIgnored private let liveSource: () -> LiveMeeting?
    @ObservationIgnored private let defaults: UserDefaults
    /// The note of the transcript that was running, so it is chosen once it is in the list.
    @ObservationIgnored private var finishedNote: String?
    @ObservationIgnored private var reading: Task<Void, Never>?

    init(store: MeetingStore, live: @escaping () -> LiveMeeting?, defaults: UserDefaults = .standard) {
        self.store = store
        liveSource = live
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
                                                                  entries: MeetingNote.parse(text).entries))
        }
    }
}
