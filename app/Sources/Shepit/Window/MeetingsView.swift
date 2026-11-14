import AppKit
import SwiftUI
import ShepitCore

/// The window's Meetings section (Meetings design §5–7, mockups 2 and 3): the list, and the chosen meeting.
struct MeetingsView: View {
    let model: MeetingsModel
    let actions: WindowActions

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                list
                Divider()
                HStack {
                    Button("Add notes…", action: actions.addMeetingNotes)
                    Spacer()
                    Button("Open meetings folder") { actions.perform(.openMeetingsFolder) }
                }
                .padding(8)
            }
            .frame(width: 270)
            Divider()
            detail.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { model.reload() }
    }

    @ViewBuilder private var list: some View {
        let running = model.live.map { MeetingPage.Running(state: $0.state, title: $0.title, app: $0.app?.rawValue) }
        let groups = MeetingPage.list(model.meetings, missing: model.missing, running: running, now: Date())
        if groups.isEmpty {
            ContentUnavailableView("No meetings yet", systemImage: "person.2.wave.2",
                                   description: Text("Every transcript is added here. For notes made before this version, use Add notes…"))
        } else {
            List(selection: Binding(get: { model.selection }, set: { model.selection = $0 })) {
                ForEach(groups, id: \.title) { group in
                    if group.title.isEmpty {
                        rows(group)
                    } else {
                        Section(group.title) { rows(group) }
                    }
                }
            }
        }
    }

    private func rows(_ group: MeetingPage.ListGroup) -> some View {
        ForEach(group.rows, id: \.id) { row in
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if row.id == nil { Circle().fill(.red).frame(width: 8, height: 8) }
                    Text(row.title).fontWeight(row.id == nil ? .semibold : .regular).lineLimit(1)
                }
                Text(row.detail).font(.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
            }
            .padding(.vertical, 2)
            .tag(row.id.map(MeetingsModel.Selection.meeting) ?? .running)
            .contextMenu {
                if let meeting = model.meetings.first(where: { $0.id == row.id }) {
                    Button("Open note") { NSWorkspace.shared.open(URL(fileURLWithPath: meeting.path)) }
                        .disabled(model.missing.contains(meeting.id))
                }
            }
        }
    }

    @ViewBuilder private var detail: some View {
        switch model.selection {
        case .running?:
            if let live = model.live {
                RunningMeeting(live: live) { actions.perform(.stopMeeting) }
            } else {
                choose
            }
        case .meeting(let id)?:
            if let open = model.open, open.meeting.id == id {
                FinishedMeeting(open: open, missing: model.missing.contains(id), actions: actions)
            } else {
                choose
            }
        case nil:
            choose
        }
    }

    private var choose: some View {
        ContentUnavailableView("Choose a meeting", systemImage: "person.2.wave.2")
    }
}

/// A small caption over a block, as in the mockups ("People", "Transcript (read only)").
private struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary).padding(.top, 6)
    }
}

/// One entry: "Name · 10:00:19" over its text; a ⚠ line of its own in grey.
private struct EntryRow: View {
    let name: String?
    let time: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let name {
                Text("\(name) · \(time)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Text(text)
            } else {
                Text(text).foregroundStyle(.secondary).italic()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A finished meeting (§6): the top, People and the transcript. Read only in this version.
private struct FinishedMeeting: View {
    let open: MeetingsModel.Open
    let missing: Bool
    let actions: WindowActions

    private static let colors: [Color] = [.green, .purple, .orange, .cyan, .pink, .blue, .yellow, .indigo, .mint, .brown]
    private var meeting: MeetingStore.Meeting { open.meeting }
    private var note: URL { URL(fileURLWithPath: meeting.path) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(MeetingPage.title(meeting.title, meeting.app)).font(.title2).fontWeight(.semibold)
                HStack(spacing: 6) {
                    ForEach(MeetingPage.facts(meeting), id: \.self) { fact in
                        Text(fact).font(.caption).padding(.horizontal, 8).padding(.vertical, 3).background(.quaternary, in: Capsule())
                    }
                    Spacer()
                    Button("Copy", action: copy).disabled(missing)
                    Button("Open note") { NSWorkspace.shared.open(note) }.disabled(missing)
                }
                if missing {
                    Text("The note was moved, renamed or deleted:").padding(.top, 12)
                    Text(meeting.path).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                } else if let page = open.page {
                    Caption("People")
                    VStack(spacing: 0) {
                        ForEach(Array(page.people.enumerated()), id: \.element.key) { index, person in
                            if index > 0 { Divider().padding(.leading, 44) }
                            personRow(person, color: Self.colors[index % Self.colors.count])
                        }
                    }
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
                    Caption("Transcript (read only)")
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(page.rows.enumerated()), id: \.offset) { _, row in
                            EntryRow(name: row.name, time: row.time, text: row.text)
                        }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .padding(20)
        }
    }

    private func personRow(_ person: MeetingPage.PersonRow, color: Color) -> some View {
        HStack(spacing: 10) {
            Text(person.initials).font(.caption2).fontWeight(.bold).foregroundStyle(.white)
                .frame(width: 26, height: 26).background(color, in: Circle())
            Text(person.name).foregroundStyle(person.named ? .primary : .secondary)
            Spacer()
            let share = "\(Int((person.share * 100).rounded()))%"
            Text(person.isYou ? "you · \(share)" : share).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private func copy() {
        guard let text = try? String(contentsOf: note, encoding: .utf8) else { return }
        actions.perform(.copyText(MeetingNote.stripFrontMatter(text)))
    }
}

/// The transcript being recorded (§7, mockup 3).
private struct RunningMeeting: View {
    let live: LiveMeeting
    let stop: () -> Void
    /// The end of the live transcript is on screen: new entries scroll into view; scrolled up, they don't.
    @State private var atEnd = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(.red).frame(width: 10, height: 10)
                Text(MeetingPage.title(live.title, live.app?.rawValue)).font(.title2).fontWeight(.semibold)
                Spacer()
                switch live.state {
                case .recording: Button("Stop", action: stop).buttonStyle(.borderedProminent).tint(.red)
                case .finishing(let left): Text("Finishing (\(left) left)").foregroundStyle(.secondary)
                case .detectingSpeakers: Text("Detecting speakers…").foregroundStyle(.secondary)
                case .idle, .done, .interrupted: EmptyView()
                }
            }
            HStack(spacing: 10) {
                tile("Time", value: { if case .recording(let elapsed, _) = live.state { StatusText.clock(elapsed) } else { "–" } }())
                tile("Words", value: live.words.formatted())
                tile("Phrases waiting", value: { switch live.state {
                case .recording(_, let waiting): "\(waiting)"
                case .finishing(let left): "\(left)"
                default: "–"
                } }())
                tile("Your microphone", value: live.muted.map { $0 ? "Muted" : "On" } ?? "–")
            }
            Caption("Live transcript")
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(live.entries, id: \.line) { entry in
                            EntryRow(name: entry.label, time: String(entry.timestamp.suffix(8)), text: entry.text)
                        }
                        Color.clear.frame(height: 1).id("end")
                            .onAppear { atEnd = true }
                            .onDisappear { atEnd = false }
                    }
                }
                .onAppear { proxy.scrollTo("end", anchor: .bottom) }
                .onChange(of: live.entries.count) { if atEnd { proxy.scrollTo("end", anchor: .bottom) } }
            }
        }
        .padding(20)
    }

    private func tile(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3).fontWeight(.semibold).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
    }
}
