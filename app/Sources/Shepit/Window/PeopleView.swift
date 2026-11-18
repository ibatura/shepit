import SwiftUI
import ShepitCore

/// The window's People section (voices design §6, mockup 6 in Meetings' two columns): Remember voices at the top, the
/// people named in meetings, and the chosen person's voice and meetings.
struct PeopleView: View {
    @Bindable var model: PeopleModel
    let settings: SettingsModel
    /// Opens a meeting in the Meetings section.
    let openMeeting: (Int) -> Void

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
            Button(text(question).button, role: .destructive) { model.answer(question, yes: true) }
            Button("Cancel", role: .cancel) { model.answer(question, yes: false) }
        } message: { question in
            Text(text(question).message)
        }
        .alert("Voices not deleted", isPresented: Binding(get: { model.failure != nil }, set: { if !$0 { model.failure = nil } })) {
            Button("OK") { model.failure = nil }
        } message: {
            Text(model.failure ?? "")
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
                        Text(person.name).font(.title2).fontWeight(.semibold)
                    }
                    if person.isYou {
                        Text("You. Your name in notes is set in Settings → Meetings.").font(.caption).foregroundStyle(.secondary)
                    }
                    Caption("Voice")
                    HStack {
                        Text(person.voice)
                        Spacer()
                        if canDeleteVoice(person) { Button("Delete voice…") { model.question = .deleteVoice(person) } }
                    }
                    .padding(10)
                    .boxed()
                    Caption("Meetings")
                    VStack(spacing: 0) {
                        ForEach(Array(person.meetings.enumerated()), id: \.element.id) { index, meeting in
                            if index > 0 { Divider().padding(.leading, 10) }
                            Button { openMeeting(meeting.id) } label: {
                                HStack {
                                    Text(meeting.title).lineLimit(1)
                                    Spacer()
                                    Text(meeting.date).foregroundStyle(.secondary).monospacedDigit()
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
        } else {
            ContentUnavailableView("Choose a person", systemImage: "person.crop.circle")
        }
    }

    /// You has no Delete (voices design §6): Delete all voices… covers yours.
    private func canDeleteVoice(_ person: PeoplePage.Person) -> Bool {
        !person.isYou && person.voiceMeetings > 0
    }

    private func text(_ question: PeopleModel.Question) -> (title: String, message: String, button: String) {
        switch question {
        case .deleteVoice(let person):
            ("Delete the voice of \(person.name)?",
             "\(person.name) stays in the meetings. A new voice is saved when they are named in a later meeting.",
             "Delete voice")
        case .deleteAll:
            ("Delete all voices?",
             "Every saved voice sample is deleted, also of people with no name. Names in meetings stay. With Remember voices on, later meetings save voices again.",
             "Delete all")
        }
    }
}
