import AppKit
import SwiftUI
import ShepitCore

/// What the window needs from the app besides the settings themselves.
@MainActor
struct SettingsActions {
    var microphones: () -> [String]
    /// Runs an action the menu also has (reload, start and stop a meeting, copy).
    var perform: (MenuAction) -> Void
    var hotkeyProblem: () -> String?
    var openSettingsFile: () -> Void
    var openDataFolder: () -> Void
    var openHistory: () -> Void
    var openMeetingsFolder: () -> Void
    var clearHistory: () -> Void
    var clearStatistics: () -> Void
    var setLaunchAtLogin: (Bool) -> String?
    /// The shortcut recorder turns the global hotkeys off while it listens, and back on after.
    var suspendHotkeys: () -> Void
    var resumeHotkeys: () -> Void
    /// Shows the panel with sample text in the current style.
    var previewOverlay: () -> Void
    /// Stored dictation attempts in a period (all of them for nil).
    var statistics: (DateInterval?) -> [DictationRow]
    /// Stored meetings that started in a period (all of them for nil).
    var meetingStatistics: (DateInterval?) -> [MeetingRecord]
    /// Why this engine can't do the configured language, or nil when it can.
    var languageNote: (EngineChoice, String) async -> String?
    var downloads: ModelDownloads
}

/// The window's Settings section (window shell design §6): its own list of sections; every control saves at once.
struct SettingsView: View {
    let model: SettingsModel
    let actions: SettingsActions
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

/// settings.json errors (controls are read-only until the file is fixed) and refused writes.
struct ProblemBanner: View {
    let model: SettingsModel
    let openFile: () -> Void

    var body: some View {
        let lines = model.errors + model.dictionaryErrors + (model.lastError.map { [$0] } ?? [])
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(lines, id: \.self) { Text("⚠ \($0)") }
                if model.isReadOnly || model.dictionaryIsReadOnly {
                    HStack {
                        Text("Fix the file to change these settings here.")
                        Button("Open settings file", action: openFile)
                    }
                }
            }
            .font(.callout)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.15))
        }
    }
}

/// A picker over a setting with a fixed list (`Settings.modes`, `.languages`, `.themes`).
struct ChoicePicker: View {
    let title: String
    let choices: [ShepitCore.Settings.Choice]
    let selection: Binding<String>

    var body: some View {
        Picker(title, selection: selection) {
            ForEach(choices, id: \.value) { Text($0.title).tag($0.value) }
        }
    }
}

/// A control with the README's one-line hint under it.
struct Hinted<Content: View>: View {
    let hint: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            content
            Text(hint).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
