import AppKit
import SwiftUI
import ShepitCore

/// Settings → Meetings (spec §5.9, `04-settings.md`): where notes go and how they're named, the meeting name
/// dialog, the microphone label and language, and the voice/speaker detection models.
struct MeetingsSection: View {
    let model: SettingsModel
    let actions: SettingsActions

    var body: some View {
        Section("Notes") {
            FolderRow(model: model)
            FileNameRow(model: model)
            Hinted(hint: "At Start, ask for the meeting name, prefilled with the one found in Teams, Zoom or Google Meet. Only when the file name uses {title}") {
                Toggle("Ask for the meeting name", isOn: model.binding("meetingAskTitle", \.meetingAskTitle))
            }
            Button("Open meetings folder", action: actions.openMeetingsFolder)
        }
        Section("Dictation") {
            Hinted(hint: "When on, the dictation hotkey does nothing while a meeting is recording. When off, you can dictate during a meeting; that audio is left out of the transcript") {
                Toggle("Block dictation during a meeting", isOn: model.binding("meetingBlocksDictation", \.meetingBlocksDictation))
            }
        }
        Section("Transcript") {
            Hinted(hint: "Label for what your microphone hears. Empty = your macOS account name (\(model.settings.myName()))") {
                TextField("Your name", text: model.binding("meetingMyName", \.meetingMyName), prompt: Text(model.settings.myName()))
            }
            Hinted(hint: "Language of the meeting. Auto-detect handles calls that switch between Ukrainian and English") {
                Picker("Language", selection: model.binding("meetingLanguage", \.meetingLanguage)) {
                    Text("Ukrainian").tag("uk")
                    Text("English").tag("en")
                    Text("Auto-detect").tag("auto")
                }
            }
            let engine = model.settings.engines[.meetings] ?? ShepitCore.Settings.defaults.engines[.meetings]!
            LabeledContent("Recognition") {
                Text(MenuModel.engineTitle(engine) + (ModelCatalog.isDownloaded(engine) ? "" : " — not downloaded"))
            }
            Text("Choose the engine in Engines & Models.").font(.caption).foregroundStyle(.secondary)
        }
        Section {
            ForEach(MeetingModel.allCases, id: \.self) { meetingModel in
                MeetingModelRow(meetingModel: meetingModel, downloads: actions.downloads)
            }
        } header: {
            Text("Models")
        } footer: {
            Text("Voice detection is needed to start a meeting. Without speaker detection all call voices stay “Співрозмовники”.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// `meetingsFolder`: typed (saved on Enter) or chosen in a folder picker.
private struct FolderRow: View {
    let model: SettingsModel
    @State private var draft = ""

    var body: some View {
        Hinted(hint: "Where notes go; created if missing. Point it at a folder in your Obsidian vault. A synced folder (iCloud) uploads the notes") {
            LabeledContent("Folder") {
                HStack {
                    TextField("Folder", text: $draft).labelsHidden().onSubmit { model.set("meetingsFolder", draft) }
                    Button("Choose…", action: choose)
                }
            }
        }
        .onAppear { draft = model.settings.meetingsFolder }
        .onChange(of: model.settings.meetingsFolder) { draft = $1 }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use this folder"
        let current = model.settings.meetingsFolderURL(home: Paths.home)
        if FileManager.default.fileExists(atPath: current.path) { panel.directoryURL = current }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let home = Paths.home.path.hasSuffix("/") ? Paths.home.path : Paths.home.path + "/"
        model.set("meetingsFolder", url.path.hasPrefix(home) ? "~/" + url.path.dropFirst(home.count) : url.path)
    }
}

/// `meetingFileName` with a live example; saved on Enter, and only when it's valid.
private struct FileNameRow: View {
    let model: SettingsModel
    @State private var draft = ""

    var body: some View {
        let error = MeetingFileName.validate(draft)
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent("File name") {
                TextField("File name", text: $draft).labelsHidden().onSubmit { if error == nil { model.set("meetingFileName", draft) } }
            }
            Group {
                if let error {
                    Text("⚠ The file name \(error)").foregroundStyle(.orange)
                } else {
                    Text("Example: " + MeetingFileName.relativePath(draft, start: Self.exampleDate, title: "Weekly sync", app: "Teams")
                         + (draft == model.settings.meetingFileName ? "" : " — press Enter to save"))
                        .foregroundStyle(.secondary)
                }
                Text("Placeholders: " + MeetingFileName.placeholders.map { "{\($0)}" }.joined(separator: " ") + ". A / makes subfolders.")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .onAppear { draft = model.settings.meetingFileName }
        .onChange(of: model.settings.meetingFileName) { draft = $1 }
    }

    /// A fixed moment so the example doesn't tick: Monday 26 Oct 2026, 14:05.
    private static let exampleDate = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 14, minute: 5)) ?? Date()
}

private struct MeetingModelRow: View {
    let meetingModel: MeetingModel
    let downloads: ModelDownloads
    @State private var confirmDelete = false

    var body: some View {
        let _ = downloads.revision // re-read the disk after a download or delete
        let item = DownloadItem.meeting(meetingModel)
        LabeledContent(meetingModel.title) {
            HStack(spacing: 10) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(meetingModel.isDownloaded() ? "Downloaded" : "Not downloaded")
                    if let error = downloads.errors[item] { Text("⚠ \(error)").font(.caption).foregroundStyle(.orange) }
                }
                if let progress = downloads.progress[item] {
                    ProgressView(value: max(progress, 0)).frame(width: 90)
                    Button("Cancel") { downloads.cancel(item) }
                } else if meetingModel.isDownloaded() {
                    Button("Delete…") { confirmDelete = true }.help("Remove this model from disk")
                } else {
                    Button("Download") { downloads.download(item) }
                        .disabled(!downloads.canDownload || downloads.running != nil)
                        .help(downloads.running == nil ? "Download and verify this model" : "One download at a time")
                }
            }
        }
        .confirmationDialog("Delete \(meetingModel.title)?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { downloads.delete(item, inUse: false) }
        } message: {
            Text("It can be downloaded again later.")
        }
    }
}
