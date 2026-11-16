import SwiftUI
import ShepitCore

/// The window's Home section (window shell design §5): status and quick controls, drawn from `Home`.
struct HomeSection: View {
    let model: SettingsModel
    let actions: WindowActions
    /// Read in `body`, so the meeting clock redraws Home and not the window around it.
    let live: WindowModel
    let navigation: WindowNavigation

    private var home: Home { live.home }

    var body: some View {
        Form {
            Section("Dictation") {
                LabeledContent("Status", value: home.status)
                ForEach(home.warnings, id: \.text) { warning in
                    HStack {
                        Label(warning.text, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        Spacer()
                        if let button = warning.button { self.button(button) }
                    }
                }
                Group {
                    ChoicePicker(title: "Mode", choices: ShepitCore.Settings.modes, selection: model.binding("mode", \.mode))
                    ChoicePicker(title: "Language", choices: ShepitCore.Settings.languages, selection: model.binding("language", \.language))
                }
                .disabled(home.dictating || model.isReadOnly)
                Picker("Microphone", selection: model.binding("microphone", \.microphone)) {
                    Text("System default").tag("")
                    ForEach(home.microphones, id: \.self) { Text($0).tag($0) }
                }
                .disabled(!home.microphoneEnabled || model.isReadOnly)
                HStack {
                    Text("Changes apply at once").foregroundStyle(.secondary)
                    Spacer()
                    Button("Reload settings") { actions.perform(.reloadConfig) }
                    Button("Reload model") { actions.perform(.reloadModels) }.disabled(home.dictating)
                }
            }
            Section("Engines: which model does which job") {
                ForEach(home.engines) { row in
                    Hinted(hint: row.hint) {
                        Picker(row.title, selection: Binding(get: { row.current }, set: { model.setEngine(row.task, $0) })) {
                            ForEach(row.choices, id: \.choice) { Text($0.title).tag($0.choice) }
                        }
                    }
                    .disabled(!row.enabled || model.isReadOnly)
                }
                Button("Download models…") { navigation.openSettings(.engines) }.buttonStyle(.link)
            }
            Section("Meeting") { meeting }
            Section("Last dictations") {
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
                    Text("The last \(HomeModel.dictationCount) are shown here").foregroundStyle(.secondary)
                    Spacer()
                    Button("All dictations") { navigation.section = .dictations }
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
