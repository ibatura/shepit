import SwiftUI
import ShepitCore

/// The window's People section (voices design §6, mockup 6 in Meetings' two columns): Remember voices at the top, the
/// people named in meetings, and the chosen person's voice and meetings.
struct PeopleView: View {
    @Bindable var model: PeopleModel
    let settings: SettingsModel
    /// Opens a meeting in the Meetings section.
    let openMeeting: (Int) -> Void
    /// May also be in…, Show…
    @State private var suggesting = false

    var body: some View {
        VStack(spacing: 0) {
            remember.padding(12)
            Divider()
            HStack(spacing: 0) {
                list.frame(width: 270)
                Divider()
                detail.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { model.reload() }
        .alert(model.question.map { text($0).title } ?? "",
               isPresented: Binding(get: { model.question != nil }, set: { if !$0 { model.question = nil } }),
               presenting: model.question) { question in
            Button(text(question).button, role: text(question).destructive ? .destructive : nil) { model.answer(question, yes: true) }
            if case .taken(let person, let name, _) = question {
                Button("Keep both") { model.rename(person, typed: name, keepBoth: true) }
            }
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

    private var remember: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Remember voices").fontWeight(.semibold)
                Text("Keeps a voice print for each person you name, so they are named in later meetings. Stored on this Mac only."
                     + (settings.settings.rememberVoices ? "" : " While off, no voice is saved or recognised; saved voices stay until deleted."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Delete all voices…") { model.question = .deleteAll }
            Toggle("Remember voices", isOn: settings.binding("rememberVoices", \.rememberVoices))
                .toggleStyle(.switch).labelsHidden().disabled(settings.isReadOnly)
        }
    }

    @ViewBuilder private var list: some View {
        if model.people.isEmpty {
            ContentUnavailableView("No people yet", systemImage: "person.crop.circle",
                                   description: Text("People you name in Meetings are listed here."))
        } else {
            List(selection: $model.selection) {
                ForEach(model.people) { person in
                    HStack(spacing: 8) {
                        Avatar(initials: person.initials, color: Avatar.color(person.id))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(person.name).lineLimit(1)
                            Text(person.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if person.voiceMeetings > 0 {
                            Image(systemName: "waveform").foregroundStyle(.secondary).help("Voice saved").accessibilityLabel("Voice saved")
                        }
                    }
                    .padding(.vertical, 2)
                    .tag(person.id)
                    .contextMenu {
                        Button("Delete voice…") { model.question = .deleteVoice(person) }.disabled(!canDeleteVoice(person))
                    }
                }
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let person = model.chosen {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Avatar(initials: person.initials, color: Avatar.color(person.id))
                        if person.isYou {
                            Text(person.name).font(.title2).fontWeight(.semibold)
                        } else {
                            PersonName(name: person.name) { model.rename(person, typed: $0) }.id(person.id)
                            Menu("Merge into") {
                                ForEach(model.people.filter { $0.id != person.id }) { other in
                                    // The detail tells apart two people with one name (Keep both).
                                    Button("\(other.name) · \(other.detail)") { model.question = .merge(person, into: other) }
                                }
                            }
                            .fixedSize()
                        }
                    }
                    if person.isYou {
                        Text("You. Your name in notes is set in Settings → Meetings.").font(.caption).foregroundStyle(.secondary)
                    }
                    Caption("Voice")
                    VStack(spacing: 0) {
                        HStack {
                            Text(person.voice)
                            Spacer()
                            if canDeleteVoice(person) { Button("Delete voice…") { model.question = .deleteVoice(person) } }
                        }
                        .padding(10)
                        if !model.suggestions.isEmpty {
                            Divider().padding(.leading, 10)
                            HStack {
                                Text(PeoplePage.mayAlsoBeIn(model.suggestions))
                                Spacer()
                                Button("Show…") { suggesting = true }
                            }
                            .padding(10)
                        }
                    }
                    .boxed()
                    HStack {
                        Caption("Who talked how much")
                        Spacer()
                        Picker("Period", selection: $model.period) {
                            ForEach(Period.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.menu).labelsHidden().fixedSize()
                    }
                    StatTiles(tiles: model.talk).padding(12).boxed()
                    Caption("Meetings")
                    VStack(spacing: 0) {
                        ForEach(Array(person.meetings.enumerated()), id: \.element.id) { index, meeting in
                            if index > 0 { Divider().padding(.leading, 10) }
                            Button { openMeeting(meeting.id) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(meeting.title).lineLimit(1)
                                        Text(meeting.date).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                    }
                                    Spacer()
                                    Text(meeting.talk).foregroundStyle(.secondary).monospacedDigit()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .boxed()
                }
                .padding(20)
            }
            .sheet(isPresented: $suggesting) {
                SuggestionsSheet(person: person, suggestions: model.suggestions) { model.name(person, suggestions: $0, checked: $1) }
            }
        } else {
            ContentUnavailableView("Choose a person", systemImage: "person.crop.circle")
        }
    }

    /// You has no Delete (voices design §6): Delete all voices… covers yours.
    private func canDeleteVoice(_ person: PeoplePage.Person) -> Bool {
        !person.isYou && person.voiceMeetings > 0
    }

    private func text(_ question: PeopleModel.Question) -> (title: String, message: String, button: String, destructive: Bool) {
        switch question {
        case .deleteVoice(let person):
            ("Delete the voice of \(person.name)?",
             "\(person.name) stays in the meetings. A new voice is saved when they are named in a later meeting.",
             "Delete voice", true)
        case .deleteAll:
            ("Delete all voices?",
             "Every saved voice sample is deleted, also of people with no name. Names in meetings stay. With Remember voices on, later meetings save voices again.",
             "Delete all", true)
        case .merge(let person, let other):
            ("Merge \(person.name) into \(other.name)?",
             "Every meeting with \(person.name) goes to \(other.name), and the notes get the name \(other.name). \(person.name) is removed from People.",
             "Merge", false)
        case .taken(let person, _, let other):
            ("\(other.name) is already in People", "Merge \(person.name) into \(other.name)?", "Merge", false)
        }
    }
}

/// A person's name as an editable title (voices design §6): saved on Enter or when it loses focus; a name that isn't
/// saved goes back to the person's.
private struct PersonName: View {
    let name: String
    let save: (String) -> Void
    @State private var typed = ""
    @FocusState private var editing: Bool

    var body: some View {
        TextField("Name", text: $typed)
            .textFieldStyle(.plain).font(.title2).fontWeight(.semibold)
            .focused($editing)
            .onSubmit(commit)
            .onChange(of: editing) { if !editing { commit() } }
            .onAppear { typed = name }
            .onChange(of: name) { typed = name }
    }

    private func commit() {
        save(typed)
        typed = name
    }
}

/// May also be in…, Show… (voices design §6): the meetings and their Person N, all checked. Name them names the checked
/// ones as the Meetings section does; the unchecked ones aren't suggested again. The list stays as it was opened: a
/// meeting suggested meanwhile isn't declined unseen.
private struct SuggestionsSheet: View {
    let person: PeoplePage.Person
    let name: ([PeoplePage.Suggestion], Set<Int>) -> Void
    @State private var suggestions: [PeoplePage.Suggestion]
    @State private var checked: Set<Int>
    @Environment(\.dismiss) private var dismiss

    init(person: PeoplePage.Person, suggestions: [PeoplePage.Suggestion], name: @escaping ([PeoplePage.Suggestion], Set<Int>) -> Void) {
        self.person = person
        self.name = name
        _suggestions = State(initialValue: suggestions)
        _checked = State(initialValue: Set(suggestions.map(\.id)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(person.name) may also be in").font(.headline)
            Text("The checked people are named \(person.name) in their meetings; the unchecked ones aren't suggested again.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(suggestions) { suggestion in
                        Toggle(isOn: Binding(get: { checked.contains(suggestion.id) },
                                             set: { if $0 { checked.insert(suggestion.id) } else { checked.remove(suggestion.id) } })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.title).lineLimit(1)
                                Text("\(suggestion.date) · \(suggestion.key)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 320)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Name them") {
                    name(suggestions, checked)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
