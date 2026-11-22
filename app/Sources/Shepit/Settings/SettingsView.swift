import AppKit
import SwiftUI
import ShepitCore

/// The window's Settings section (window shell design §6): its own list of sections; every control saves at once.
struct SettingsView: View {
    let model: SettingsModel
    let actions: WindowActions
    @Binding var section: SettingsModel.Section

    var body: some View {
        HStack(spacing: 0) {
            List(SettingsModel.Section.allCases, selection: Binding(get: { section }, set: { section = $0 ?? section })) { section in
                Label(section.rawValue, systemImage: section.symbol).tag(section)
            }
            .frame(width: 210)
            Divider()
            Form {
                // What the page is for (settings review design §4): an empty section shows only its header.
                Section {} header: { Text(section.line).font(.body).fontWeight(.regular).foregroundStyle(.secondary) }
                switch section {
                case .general: GeneralSection(model: model, actions: actions)
                case .hotkeys: HotkeysSection(model: model, actions: actions)
                case .dictation: DictationSection(model: model, actions: actions)
                case .meetings: MeetingsSection(model: model, actions: actions)
                case .engines: EnginesSection(model: model, actions: actions)
                case .historyPrivacy: HistoryPrivacySection(model: model, actions: actions)
                case .appearance: AppearanceSection(model: model)
                }
            }
            .formStyle(.grouped)
            // History and privacy locks only its settings: its file actions work while settings.json is broken.
            .disabled(model.isReadOnly && section != .historyPrivacy)
        }
    }
}
