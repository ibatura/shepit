import SwiftUI
import ShepitCore

/// Settings → Engines and models (`04-settings.md` §3, `02-engines.md` §3–5, settings review design §4): the model of
/// every job (speech recognition per task, the meetings' voice and speaker detection), idle unload, and every model on
/// this Mac by its kind, each saying what it is for and what uses it.
struct EnginesSection: View {
    let model: SettingsModel
    let actions: WindowActions

    private let tasks: [(EngineTask, String)] = [
        (.dictation, "The text that gets pasted"),
        (.preview, "The draft text in the panel while you speak"),
        (.meetings, "Meeting transcripts"),
    ]

    /// The meetings' other jobs: one model each for now, shown as chosen all the same (the author, 2026-11-23).
    private let detection: [(MeetingModel, String)] = [
        (.vad, "Where someone speaks in a meeting's audio"),
        (.diarization, "Which voice in a call is whose"),
    ]

    var body: some View {
        Section {
            ForEach(tasks, id: \.0) { task, hint in
                TaskEngineRow(model: model, actions: actions, task: task, hint: hint)
            }
            ForEach(detection, id: \.0) { meetingModel, hint in
                DetectionRow(meetingModel: meetingModel, hint: hint, downloads: actions.downloads)
            }
        } footer: {
            Text("The same engine and model can serve several tasks; it's loaded once.").font(.caption).foregroundStyle(.secondary)
        }
        Section {
            Hinted(hint: "Frees the speech models' memory; they load again on the next dictation") {
                NumberMenu(title: "Unload models when idle", values: [0, 5, 15, 30, 60, 120, 240, 480],
                           selection: model.binding("idleUnloadMinutes", \.idleUnloadMinutes)) { $0 == 0 ? "Never" : "After " + NumberMenu.seconds($0 * 60) }
            }
        }
        Section("Speech recognition models") {
            ForEach(allChoices, id: \.self) { choice in
                let usedBy = tasks.filter { model.settings.engines[$0.0] == choice }.map(\.0.title)
                ModelRow(item: .engine(choice), about: Self.about(choice),
                         use: usedBy.isEmpty ? nil : "Used for: \(usedBy.joined(separator: ", "))",
                         downloads: actions.downloads, language: model.settings.language)
            }
        }
        ForEach(detection, id: \.0) { meetingModel, _ in
            Section("\(meetingModel.job) models") {
                ModelRow(item: .meeting(meetingModel), about: Self.about(meetingModel), use: "Used for: \(meetingModel.job)",
                         downloads: actions.downloads, language: model.settings.language)
            }
        }
    }

    private var allChoices: [EngineChoice] {
        EngineID.allCases.flatMap { engine in ModelCatalog.models(for: engine).map { EngineChoice(engine: engine, model: $0) } }
    }

    /// What each model is good at ("What each engine is for", the author, 2026-11-16), as README's engine table says.
    private static func about(_ choice: EngineChoice) -> String {
        switch (choice.engine, choice.model) {
        case (.whispercpp, "large-v3-turbo"): "Most accurate on Ukrainian with the style prompt, and fast. About 1.8 GB of memory"
        case (.whispercpp, _): "A bit slower than turbo, about as accurate. About 3.5 GB of memory"
        case (.whisperkit, _): "The same Whisper model on Core ML. The first load compiles it: a few minutes, once"
        case (.parakeet, _): "Very fast, but writes English terms in Cyrillic and takes no style prompt"
        case (.apple, _): "Built into macOS 26. Ukrainian only through the older dictation recognizer: the weakest results"
        }
    }

    private static func about(_ meetingModel: MeetingModel) -> String {
        switch meetingModel {
        case .vad: "Small and fast, on Core ML. A meeting can't start without it"
        case .diarization: "On Core ML. Without it every call voice stays “Співрозмовники”"
        }
    }
}

private struct TaskEngineRow: View {
    let model: SettingsModel
    let actions: WindowActions
    let task: EngineTask
    let hint: String
    @State private var languageNote: String?

    var body: some View {
        let current = model.settings.engine(for: task)
        LabeledContent {
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
        } label: {
            TitleAndAbout(title: task.title, about: languageNote ?? (ModelCatalog.isDownloaded(current) ? hint : "⚠ Not downloaded — \(hint.lowercased())"))
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

/// A meeting job with its one model, and whether that model is on this Mac.
private struct DetectionRow: View {
    let meetingModel: MeetingModel
    let hint: String
    let downloads: ModelDownloads

    var body: some View {
        let _ = downloads.revision // re-read the disk after a download or delete
        LabeledContent {
            Picker("Model", selection: .constant(meetingModel)) { Text(meetingModel.title).tag(meetingModel) }.labelsHidden()
        } label: {
            TitleAndAbout(title: meetingModel.job, about: meetingModel.isDownloaded() ? hint : "⚠ Not downloaded — \(hint.lowercased())")
        }
    }
}

/// A row's name with a line under it on what it is for.
private struct TitleAndAbout: View {
    let title: String
    let about: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(about).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// A model on this Mac: an engine's, or one a meeting needs. What uses it, its state, and Download, Cancel or Delete….
private struct ModelRow: View {
    let item: DownloadItem
    let about: String
    /// "Used for: …"; nil when no job uses the model.
    let use: String?
    let downloads: ModelDownloads
    let language: String
    @State private var confirmDelete = false

    var body: some View {
        let _ = downloads.revision // re-read the disk after a download or delete
        LabeledContent {
            HStack(spacing: 10) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(state)
                    if let use {
                        Text(use).font(.caption).foregroundStyle(.secondary)
                    } else if downloaded, !isApple {
                        Text("Not used: can be deleted").font(.caption).foregroundStyle(.secondary)
                    }
                    if let error = downloads.errors[item] { Text("⚠ \(error)").font(.caption).foregroundStyle(.orange) }
                }
                if let progress = downloads.progress[item] {
                    if progress < 0 { ProgressView().controlSize(.small) } else { ProgressView(value: progress).frame(width: 90) }
                    Button("Cancel") { downloads.cancel(item) }
                } else if isApple {
                    if downloaded {
                        Button("Install language") { downloads.download(item, language: language) }
                            .disabled(downloads.running != nil)
                            .help("Asks macOS to install the speech assets for the dictation language")
                    }
                } else if downloaded {
                    Button("Delete…") { confirmDelete = true }
                        .disabled(engineInUse)
                        .help(engineInUse ? "In use — choose another engine for those tasks first" : "Remove this model from disk")
                } else {
                    Button("Download") { downloads.download(item, language: language) }
                        .disabled(!downloads.canDownload || downloads.running != nil)
                        .help(downloads.running == nil ? "Download and verify this model" : "One download at a time")
                }
            }
        } label: {
            TitleAndAbout(title: title, about: about)
        }
        .confirmationDialog("Delete \(title)?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { downloads.delete(item, inUse: engineInUse) }
        } message: {
            Text("It can be downloaded again later.")
        }
    }

    private var title: String {
        switch item {
        case .engine(let choice): choice.title
        case .meeting(let meetingModel): meetingModel.title
        }
    }

    private var downloaded: Bool {
        switch item {
        case .engine(let choice): ModelCatalog.isDownloaded(choice)
        case .meeting(let meetingModel): meetingModel.isDownloaded()
        }
    }

    private var isApple: Bool { if case .engine(let choice) = item { choice.engine == .apple } else { false } }

    /// An engine a job uses can't be deleted; the meetings' models can, as before.
    private var engineInUse: Bool { if case .engine = item { use != nil } else { false } }

    private var state: String {
        if isApple { return downloaded ? "System-managed" : "Needs macOS 26" }
        guard downloaded else { return "Not downloaded" }
        guard case .engine(let choice) = item else { return "Downloaded" }
        let size = ModelCatalog.sizeOnDisk(choice).map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        return "Downloaded" + (size.map { " · \($0)" } ?? "")
    }
}
