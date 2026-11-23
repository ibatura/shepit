import AppKit
import SwiftUI
import ShepitCore

/// Settings → Meetings (spec §5.9, `04-settings.md`; settings review design §4): when calls start a transcript, where
/// notes go and how they're named, the meeting name dialog, the microphone label and language, and whether the models
/// a meeting needs are on this Mac (they are in Engines and models).
struct MeetingsSection: View {
    let model: SettingsModel
    let actions: WindowActions
    let openEngines: () -> Void

    var body: some View {
        CallsSection(model: model)
        Section("Notes") {
            FolderRow(model: model, key: "meetingsFolder", path: \.meetingsFolder, url: { $0.meetingsFolderURL(home: Paths.home) },
                      hint: "Where notes go; created if missing. Point it at a folder in your Obsidian vault. A synced folder (iCloud) uploads the notes")
            FileNameRow(model: model)
            Hinted(hint: "At Start, ask for the meeting name, prefilled with the one found in Teams, Zoom or Google Meet. Only when the file name uses {title}") {
                Toggle("Ask for the meeting name", isOn: model.binding("meetingAskTitle", \.meetingAskTitle))
            }
            Button("Open meetings folder") { actions.perform(.openMeetingsFolder) }
        }
        Section("Transcript") {
            Hinted(hint: "Label for what your microphone hears. Empty = your macOS account name (\(model.settings.myName()))") {
                LabeledContent("Your name") {
                    SettingField(saved: model.settings.meetingMyName, prompt: model.settings.myName()) { model.set("meetingMyName", $0) }
                }
            }
            Hinted(hint: "Language of the meeting. Auto-detect handles calls that switch between Ukrainian and English") {
                ChoicePicker(title: "Language", choices: ShepitCore.Settings.languages, selection: model.binding("meetingLanguage", \.meetingLanguage))
            }
            Hinted(hint: "When on, the dictation hotkey does nothing while a meeting is recording. When off, you can dictate during a meeting; that audio is left out of the transcript") {
                Toggle("Block dictation during a meeting", isOn: model.binding("meetingBlocksDictation", \.meetingBlocksDictation))
            }
            let _ = actions.downloads.revision // re-read the disk after a download or delete
            let engine = model.settings.engine(for: .meetings)
            // Each is a link to where it's chosen and downloaded (the author, 2026-11-23).
            LabeledContent("Recognition") {
                Button(engine.title + (ModelCatalog.isDownloaded(engine) ? "" : " — not downloaded"), action: openEngines)
                    .buttonStyle(.link).help("Choose the engine in Engines and models")
            }
            let missing = MeetingModel.allCases.filter { !$0.isDownloaded() }.map { $0 == .vad ? "voice detection" : "speaker detection" }
            LabeledContent("Voice and speaker detection") {
                Button(missing.isEmpty ? "Installed" : "Not downloaded: \(missing.joined(separator: ", "))", action: openEngines)
                    .buttonStyle(.link).help("Download the models in Engines and models")
            }
        }
    }
}

/// A folder setting (`meetingsFolder`, `databasesFolder`): typed (saved with Save or Enter) or chosen in a folder picker.
struct FolderRow: View {
    let model: SettingsModel
    let key: String
    let path: KeyPath<ShepitCore.Settings, String>
    let url: (ShepitCore.Settings) -> URL
    let hint: String

    var body: some View {
        Hinted(hint: hint) {
            LabeledContent("Folder") {
                HStack {
                    SettingField(saved: model.settings[keyPath: path]) { model.set(key, $0) }
                    Button("Choose…", action: choose)
                }
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use this folder"
        let current = url(model.settings)
        if FileManager.default.fileExists(atPath: current.path) { panel.directoryURL = current }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let home = Paths.home.path.hasSuffix("/") ? Paths.home.path : Paths.home.path + "/"
        model.set(key, url.path.hasPrefix(home) ? "~/" + url.path.dropFirst(home.count) : url.path)
    }
}

/// `meetingFileName` with a live example; saved with Save or Enter, and only when it's valid.
private struct FileNameRow: View {
    let model: SettingsModel
    /// The name as typed, for the example.
    @State private var draft = ""

    var body: some View {
        let error = MeetingFileName.validate(draft)
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent("File name") {
                SettingField(saved: model.settings.meetingFileName, canSave: { MeetingFileName.validate($0) == nil },
                             edited: { draft = $0 }) { model.set("meetingFileName", $0) }
            }
            Group {
                if let error {
                    Text("⚠ The file name \(error)").foregroundStyle(.orange)
                } else {
                    Text("Example: " + MeetingFileName.relativePath(draft, start: Self.exampleDate, title: "Weekly sync", app: "Teams"))
                        .foregroundStyle(.secondary)
                }
                Text("Placeholders: " + MeetingFileName.placeholders.map { "{\($0)}" }.joined(separator: " ") + ". A / makes subfolders.")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }

    /// A fixed moment so the example doesn't tick: Monday 26 Oct 2026, 14:05.
    private static let exampleDate = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 14, minute: 5)) ?? Date()
}
