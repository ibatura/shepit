import SwiftUI
import ShepitCore

/// The window's Home section (window shell design §5, settings review design §5): a status page, drawn from `Home`;
/// the settings are in Settings and the menu.
struct HomeSection: View {
    let actions: WindowActions
    /// Read in `body`, so the meeting clock redraws Home and not the window around it.
    let live: WindowModel
    let navigation: WindowNavigation

    private var home: Home { live.home }

    var body: some View {
        Form {
            if !home.warnings.isEmpty {
                Section("Needs attention") {
                    ForEach(home.warnings, id: \.text) { warning in
                        HStack {
                            Label(warning.text, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                            Spacer()
                            if let button = warning.button { self.button(button) }
                        }
                    }
                }
            }
            Section("Dictation") {
                LabeledContent("Status", value: home.status)
            }
            Section("Meeting") { meeting }
            Section("Recent dictations") {
                if home.dictations.isEmpty { Text(home.noDictations).foregroundStyle(.secondary) }
                ForEach(Array(home.dictations.enumerated()), id: \.offset) { _, dictation in
                    HStack {
                        Text(dictation.text).lineLimit(2)
                        Spacer()
                        Text(dictation.detail).foregroundStyle(.secondary).monospacedDigit()
                        Button("Copy") { actions.perform(.copyText(dictation.text)) }
                    }
                }
                HStack {
                    Text("The last \(HomeModel.recentCount) are shown here").foregroundStyle(.secondary)
                    Spacer()
                    Button("All dictations") { navigation.section = .dictations }
                }
            }
            if !home.meetings.isEmpty {
                Section("Recent meetings") {
                    ForEach(home.meetings) { meeting in
                        Button { navigation.openMeeting(meeting.id) } label: {
                            HStack {
                                Text(meeting.title).lineLimit(1)
                                Spacer()
                                Text(meeting.detail).foregroundStyle(.secondary).monospacedDigit()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    HStack {
                        Spacer()
                        Button("All meetings") { navigation.section = .meetings }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var meeting: some View {
        let row = home.meeting
        return HStack {
            if row.recording { Circle().fill(.red).frame(width: 8, height: 8) }
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                if let hint = row.hint { Text(hint).font(.caption).foregroundStyle(.secondary).monospacedDigit() }
            }
            Spacer()
            if let button = row.button {
                self.button(button)
                    .buttonStyle(.borderedProminent)
                    .tint(row.recording ? .red : nil)
            }
        }
    }

    private func button(_ button: Home.Button) -> some View {
        Button(button.title) { if let action = button.action { actions.perform(action) } }
            .disabled(button.action == nil)
    }
}
