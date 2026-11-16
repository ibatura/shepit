import AppKit
import SwiftUI
import ShepitCore

/// The window's Meetings section (Meetings design §5–8, mockups 2 and 3): the list, and the chosen meeting.
struct MeetingsView: View {
    @Bindable var model: MeetingsModel
    let actions: WindowActions

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                list
                Divider()
                HStack {
                    Button("Add notes…", action: model.addNotes)
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
        .alert(model.question.map { text($0).title } ?? "",
               isPresented: Binding(get: { model.question != nil }, set: { if !$0, let q = model.question { model.answer(q, yes: false) } }),
               presenting: model.question) { question in
            Button(text(question).button, role: text(question).destructive ? .destructive : nil) { model.answer(question, yes: true) }
            Button("Cancel", role: .cancel) { model.answer(question, yes: false) }
        } message: { question in
            Text(text(question).message)
        }
        .alert(model.notice?.title ?? "", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK") { model.notice = nil }
        } message: {
            Text(model.notice?.message ?? "")
        }
    }

    @ViewBuilder private var list: some View {
        let groups = MeetingPage.list(model.meetings, missing: model.missing, running: model.live, now: Date())
        if groups.isEmpty {
            ContentUnavailableView("No meetings yet", systemImage: "person.2.wave.2",
                                   description: Text("Every transcript is added here. For notes made before this version, use Add notes…"))
        } else {
            List(selection: $model.selection) {
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
                    MeetingMenu(model: model, actions: actions, meeting: meeting, missing: model.missing.contains(meeting.id),
                                withOpen: true)
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
                FinishedMeeting(model: model, open: open, actions: actions).id(id)
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

    /// The texts of a question of §6 and §8.
    private func text(_ question: MeetingsModel.Question) -> (title: String, message: String, button: String, destructive: Bool) {
        switch question {
        case .merge(_, let person, _, let name):
            let shown: String
            if case .page(let page) = model.open?.content { shown = page.people.first { $0.key == person }?.name ?? person } else { shown = person }
            return ("\(name) is already in this meeting", "Merge \(shown) into \(name)?", "Merge", false)
        case .reset:
            return ("Reset people?", "Every line goes back to the person speaker detection gave it. Names given to people stay.", "Reset", false)
        case .remove(let meeting):
            return ("Remove “\(MeetingPage.title(meeting.title, meeting.app))” from the list?",
                    "The note stays. Names given here and Reset people are lost; Add notes… adds the note again with the labels it has.",
                    "Remove", true)
        case .trash(let meeting):
            return ("Move “\(URL(fileURLWithPath: meeting.path).lastPathComponent)” to the Trash?", "The meeting is removed from the list too.",
                    "Move to Trash", true)
        }
    }
}

/// Open note, Reveal in Finder, Copy path, Remove note from list…, Move file to Trash…: the ⋯ menu and a row's
/// right-click menu.
private struct MeetingMenu: View {
    let model: MeetingsModel
    let actions: WindowActions
    let meeting: MeetingStore.Meeting
    let missing: Bool
    var withOpen = false

    var body: some View {
        let note = URL(fileURLWithPath: meeting.path)
        if withOpen {
            Button("Open note") { NSWorkspace.shared.open(note) }.disabled(missing)
        }
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([note]) }.disabled(missing)
        Button("Copy path") { actions.perform(.copyText(meeting.path)) }
        Divider()
        Button("Remove note from list…") { model.question = .remove(meeting) }
        Button("Move file to Trash…") { model.question = .trash(meeting) }.disabled(missing)
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

/// A finished meeting (§6): the name, People and the transcript.
private struct FinishedMeeting: View {
    let model: MeetingsModel
    let open: MeetingsModel.Open
    let actions: WindowActions
    @State private var title = ""
    @FocusState private var editingTitle: Bool
    /// The transcript row whose "Give this line to" is open.
    @State private var giving: Int?

    private static let colors: [Color] = [.green, .purple, .orange, .cyan, .pink, .blue, .yellow, .indigo, .mint, .brown]
    private var meeting: MeetingStore.Meeting { open.meeting }
    private var missing: Bool { open.content == .missing }
    private var note: URL { URL(fileURLWithPath: meeting.path) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                TextField(MeetingPage.title(nil, meeting.app), text: $title)
                    .textFieldStyle(.plain).font(.title2).fontWeight(.semibold)
                    .focused($editingTitle)
                    .onSubmit(saveTitle)
                    .onChange(of: editingTitle) { if !editingTitle { saveTitle() } }
                HStack(spacing: 6) {
                    ForEach(MeetingPage.facts(meeting), id: \.self) { fact in
                        Text(fact).font(.caption).padding(.horizontal, 8).padding(.vertical, 3).background(.quaternary, in: Capsule())
                    }
                    Spacer()
                    Button("Copy", action: copy).disabled(missing)
                    Button("Open note") { NSWorkspace.shared.open(note) }.disabled(missing)
                    Menu {
                        MeetingMenu(model: model, actions: actions, meeting: meeting, missing: missing)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                }
                switch open.content {
                case .missing:
                    Text("The note was moved, renamed or deleted:").padding(.top, 12)
                    Text(meeting.path).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    HStack {
                        Button("Locate note…", action: model.locate)
                        Button("Remove note from list…") { model.question = .remove(meeting) }
                    }
                case .page(let page):
                    people(page)
                    Caption("Transcript (read only) · click a line to give it to another person")
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(page.rows.enumerated()), id: \.offset) { index, row in
                            transcriptRow(row, index: index, people: page.people)
                        }
                    }
                case .reading:
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .padding(20)
        }
        .onAppear { title = meeting.title ?? "" }
        .onChange(of: meeting.title) { title = meeting.title ?? "" }
    }

    private func saveTitle() {
        if !model.rename(meeting, typed: title) { title = meeting.title ?? "" }
    }

    private func people(_ page: MeetingPage.Page) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Caption("People")
            VStack(spacing: 0) {
                ForEach(Array(page.people.enumerated()), id: \.element.key) { index, person in
                    if index > 0 { Divider().padding(.leading, 46) }
                    personRow(person, color: color(of: person.key, in: page), page: page)
                }
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
            HStack {
                Spacer()
                Button("Reset people…") { model.question = .reset(meeting: meeting.id) }.disabled(!page.canReset)
            }
        }
    }

    private func color(of person: String, in page: MeetingPage.Page) -> Color {
        Self.colors[(page.people.firstIndex { $0.key == person } ?? 0) % Self.colors.count]
    }

    private func personRow(_ person: MeetingPage.PersonRow, color: Color, page: MeetingPage.Page) -> some View {
        HStack(spacing: 10) {
            Text(person.initials).font(.caption2).fontWeight(.bold).foregroundStyle(.white)
                .frame(width: 26, height: 26).background(color, in: Circle())
            NameField(text: person.given ?? "", placeholder: person.key, suggestions: open.suggestions, cancels: model.cancels) {
                model.name(meeting.id, person: person.key, typed: $0)
            }
            .frame(width: 230)
            Spacer()
            let share = "\(Int((person.share * 100).rounded()))%"
            Text(person.isYou ? "you · \(share)" : share).foregroundStyle(.secondary).monospacedDigit()
            if !person.mergeTargets.isEmpty {
                Menu("Merge into") {
                    ForEach(person.mergeTargets, id: \.self) { target in
                        Button(page.people.first { $0.key == target }?.name ?? target) { model.merge(meeting.id, person: person.key, into: target) }
                    }
                }
                .fixedSize()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    @ViewBuilder private func transcriptRow(_ row: MeetingPage.Row, index: Int, people: [MeetingPage.PersonRow]) -> some View {
        let entry = EntryRow(name: row.name, time: row.time, text: row.text)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(giving == index ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 6))
        if let place = row.place {
            entry
                .contentShape(Rectangle())
                .onTapGesture { giving = index }
                .popover(isPresented: Binding(get: { giving == index }, set: { if !$0 { giving = nil } }), arrowEdge: .trailing) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Give this line to").font(.caption).foregroundStyle(.secondary).padding(.bottom, 4)
                        ForEach(people.filter { $0.key != row.person }, id: \.key) { person in
                            Button(person.name) { giving = nil; model.give(meeting.id, line: place, to: person.key) }
                        }
                        Divider().padding(.vertical, 4)
                        Button("New person") { giving = nil; model.giveToNewPerson(meeting.id, line: place) }
                    }
                    .buttonStyle(.borderless)
                    .padding(12)
                }
        } else {
            entry
        }
    }

    private func copy() {
        guard let text = try? String(contentsOf: note, encoding: .utf8) else { return }
        actions.perform(.copyText(MeetingNote.stripFrontMatter(text)))
    }
}

/// A person's name: a combo box of the names Shepit knows. While typing, its list opens with the names that match.
/// Saved on Enter, when it loses focus, or when a name is picked from the list.
private struct NameField: NSViewRepresentable {
    let text: String
    let placeholder: String
    let suggestions: [String]
    /// A change here drops what is being typed and shows `text` again (Cancel on the merge question).
    let cancels: Int
    let commit: (String) -> Void

    func makeNSView(context: Context) -> NSComboBox {
        let box = NSComboBox()
        box.numberOfVisibleItems = 12
        box.delegate = context.coordinator
        return box
    }

    func updateNSView(_ box: NSComboBox, context: Context) {
        context.coordinator.commit = commit
        context.coordinator.names = suggestions
        context.coordinator.stored = text
        box.placeholderString = placeholder
        if context.coordinator.cancels != cancels {
            context.coordinator.cancels = cancels
            box.abortEditing() // no second save of the dropped name when the field loses focus
        }
        guard box.currentEditor() == nil else { return } // not while typing: the list then shows the matches
        if box.stringValue != text { box.stringValue = text }
        if box.objectValues as? [String] != suggestions {
            box.removeAllItems()
            box.addItems(withObjectValues: suggestions)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(commit: commit, cancels: cancels) }

    @MainActor
    final class Coordinator: NSObject, NSComboBoxDelegate {
        var commit: (String) -> Void
        var names: [String] = []
        var cancels: Int
        /// The name the field shows when nothing is typed: Escape goes back to it.
        var stored = ""

        init(commit: @escaping (String) -> Void, cancels: Int) {
            self.commit = commit
            self.cancels = cancels
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let box = notification.object as? NSComboBox else { return }
            let matches = MeetingPage.matching(names, typed: box.stringValue)
            box.removeAllItems()
            box.addItems(withObjectValues: matches)
            // Opens or closes the list, as clicking ▾ does.
            box.cell?.setAccessibilityExpanded(!matches.isEmpty)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            if let box = notification.object as? NSComboBox { commit(box.stringValue) }
        }

        /// A name picked with a click or Enter; moving through the list with the arrows doesn't save, and Escape backs out.
        func comboBoxWillDismiss(_ notification: Notification) {
            guard let box = notification.object as? NSComboBox else { return }
            if let event = NSApp.currentEvent, event.type == .keyDown, event.keyCode == 53 { // Escape
                let stored = stored
                // After the list has closed: the arrows put the highlighted name in the field, which would be saved on leaving it.
                DispatchQueue.main.async {
                    box.abortEditing()
                    box.stringValue = stored
                }
                return
            }
            guard box.indexOfSelectedItem >= 0, let name = box.objectValueOfSelectedItem as? String else { return }
            box.stringValue = name
            commit(name)
        }
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
