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
                switch section {
                case .general: GeneralSection(model: model, actions: actions)
                case .hotkeys: HotkeysSection(model: model, actions: actions)
                case .engines: EnginesSection(model: model, actions: actions)
                case .dictation: DictationSection(model: model, actions: actions)
                case .overlay: OverlaySection(model: model, actions: actions)
                case .meetings: MeetingsSection(model: model, actions: actions)
                case .calls: CallsSection(model: model)
                case .historyPrivacy: HistoryPrivacySection(model: model, actions: actions)
                case .appearance: AppearanceSection(model: model)
                }
            }
            .formStyle(.grouped)
            .disabled(model.isReadOnly)
        }
    }
}
