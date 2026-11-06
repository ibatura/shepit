import SwiftUI
import ShepitCore

/// Settings → Engines & Models (`04-settings.md` §3, `02-engines.md` §3–5): an engine and model per
/// task, idle unload, and what is on disk. Downloads come with the model downloader.
struct EnginesSection: View {
    let model: SettingsModel
    let actions: SettingsActions

    private let tasks: [(EngineTask, String, String)] = [
        (.dictation, "Dictation", "The text that gets pasted"),
        (.preview, "Live draft", "The draft text in the panel while you speak"),
        (.meetings, "Meetings", "Meeting transcripts"),
    ]

    var body: some View {
        Section {
            ForEach(tasks, id: \.0) { task, title, hint in
                TaskEngineRow(model: model, actions: actions, task: task, title: title, hint: hint)
            }
        } footer: {
            Text("The same engine and model can serve several tasks; it's loaded once.").font(.caption).foregroundStyle(.secondary)
        }
        Section {
            Hinted(hint: "Free the models' memory after this many idle minutes; they load again on the next dictation. 0 = always keep loaded") {
                Stepper(value: model.binding("idleUnloadMinutes", \.idleUnloadMinutes), in: 0...1440, step: 5) {
                    Text(model.settings.idleUnloadMinutes == 0 ? "Unload when idle: never" : "Unload when idle: after \(model.settings.idleUnloadMinutes) min")
                }
            }
        }
        Section("Models on this Mac") {
            ForEach(allChoices, id: \.self) { choice in
                ModelRow(choice: choice, usedBy: tasks.filter { model.settings.engines[$0.0] == choice }.map(\.1),
                         downloads: actions.downloads, language: model.settings.language,
                         inUse: { model.settings.engines.values.contains(choice) })
            }
        }
    }

    private var allChoices: [EngineChoice] {
        EngineID.allCases.flatMap { engine in ModelCatalog.models(for: engine).map { EngineChoice(engine: engine, model: $0) } }
    }
}

private struct TaskEngineRow: View {
    let model: SettingsModel
    let actions: SettingsActions
    let task: EngineTask
    let title: String
    let hint: String
    @State private var languageNote: String?

    var body: some View {
        let current = model.settings.engines[task] ?? ShepitCore.Settings.defaults.engines[task]!
        Hinted(hint: languageNote ?? (ModelCatalog.isDownloaded(current) ? hint : "⚠ Not downloaded — \(hint.lowercased())")) {
            LabeledContent(title) {
                HStack {
                    Picker("Engine", selection: Binding(get: { current.engine }, set: { engine in
                        let models = ModelCatalog.models(for: engine)
                        let downloaded = models.first { ModelCatalog.isDownloaded(EngineChoice(engine: engine, model: $0)) }
                        model.setEngine(task, EngineChoice(engine: engine, model: downloaded ?? models[0]))
                    })) {
                        ForEach(EngineID.allCases, id: \.self) { Text(engineName($0)).tag($0) }
                    }
                    .labelsHidden()
                    if ModelCatalog.models(for: current.engine).count > 1 {
                        Picker("Model", selection: Binding(get: { current.model }, set: { model.setEngine(task, EngineChoice(engine: current.engine, model: $0)) })) {
                            ForEach(ModelCatalog.models(for: current.engine), id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                    }
                }
            }
        }
        .task(id: "\(current.engine.rawValue)/\(current.model)/\(model.settings.language)") {
            languageNote = await actions.languageNote(current, model.settings.language)
        }
    }

    private func engineName(_ engine: EngineID) -> String {
        switch engine {
        case .whispercpp: "whisper.cpp"
        case .whisperkit: "WhisperKit"
        case .parakeet: "Parakeet"
        case .apple: "Apple Speech"
        }
    }
}

private struct ModelRow: View {
    let choice: EngineChoice
    let usedBy: [String]
    let downloads: ModelDownloads
    let language: String
    let inUse: () -> Bool
    @State private var confirmDelete = false

    var body: some View {
        let _ = downloads.revision // re-read the disk after a download or delete
        LabeledContent(MenuModel.engineTitle(choice)) {
            HStack(spacing: 10) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(state)
                    if !usedBy.isEmpty { Text("Used for: \(usedBy.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary) }
                    if let error = downloads.errors[.engine(choice)] { Text("⚠ \(error)").font(.caption).foregroundStyle(.orange) }
                }
                if let progress = downloads.progress[.engine(choice)] {
                    if progress < 0 { ProgressView().controlSize(.small) } else { ProgressView(value: progress).frame(width: 90) }
                    Button("Cancel") { downloads.cancel(.engine(choice)) }
                } else if choice.engine == .apple {
                    if ModelCatalog.isDownloaded(choice) {
                        Button("Install language") { downloads.download(.engine(choice), language: language) }
                            .disabled(downloads.running != nil)
                            .help("Asks macOS to install the speech assets for the dictation language")
                    }
                } else if ModelCatalog.isDownloaded(choice) {
                    Button("Delete…") { confirmDelete = true }
                        .disabled(!usedBy.isEmpty)
                        .help(usedBy.isEmpty ? "Remove this model from disk" : "In use — choose another engine for those tasks first")
                } else {
                    Button("Download") { downloads.download(.engine(choice), language: language) }
                        .disabled(!downloads.canDownload || downloads.running != nil)
                        .help(downloads.running == nil ? "Download and verify this model" : "One download at a time")
                }
            }
        }
        .confirmationDialog("Delete \(MenuModel.engineTitle(choice))?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { downloads.delete(.engine(choice), inUse: inUse()) }
        } message: {
            Text("It can be downloaded again later.")
        }
    }

    private var state: String {
        if choice.engine == .apple {
            return ModelCatalog.isDownloaded(choice) ? "System-managed" : "Needs macOS 26"
        }
        guard ModelCatalog.isDownloaded(choice) else { return "Not downloaded" }
        let size = ModelCatalog.sizeOnDisk(choice).map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        return "Downloaded" + (size.map { " · \($0)" } ?? "")
    }
}
