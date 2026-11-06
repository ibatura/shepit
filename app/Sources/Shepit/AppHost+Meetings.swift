import AppKit
import ShepitCore
import ShepitEngines

/// Meeting transcripts in the app (spec §5.4–5.7, §5.10): Start/Stop, the name dialog, Copy, Open folder,
/// launch recovery and quit. The session itself is `MeetingSession` (ShepitCore).
extension AppHost {
    /// Private session dirs live here; leftovers are deleted at launch (spec §5.10).
    static var meetingSessionsRoot: URL {
        FileManager.default.temporaryDirectory.appending(path: "dictation", directoryHint: .isDirectory)
    }

    /// nil when a meeting can start; else what the menu says is missing.
    var meetingMissing: String? {
        let engine = settings.engines[.meetings] ?? Settings.defaults.engines[.meetings]!
        return ModelCatalog.isDownloaded(engine) && MeetingModel.vad.isDownloaded() ? nil : "download the model in Settings"
    }

    var meetingActive: Bool {
        switch meeting?.state {
        case .recording, .finishing, .detectingSpeakers: true
        default: false
        }
    }

    func recoverMeeting() {
        if let note = MeetingSession.recover(stateDir: Paths.dataDir, sessionsRoot: Self.meetingSessionsRoot, now: Date()) {
            panel.message("⚠ The last meeting transcript was interrupted: \(note.lastPathComponent)")
        }
    }

    func startMeeting() async {
        guard !meetingActive, meetingMissing == nil else { return }
        let settings = settings
        let front = NSWorkspace.shared.frontmostApplication
        let first = await Task.detached {
            MeetingApps.keepAccessibilityBuilt()
            return MeetingApps.scan(limit: 2)
        }.value
        var detected = first.detected
        var muteButton = first.mute
        var title = detected.title
        let namesFile = Paths.dataDir.appending(path: MeetingNames.fileName)
        let names = MeetingNames.load(namesFile)
        if settings.meetingAskTitle, settings.meetingFileName.contains("{title}") {
            // The call window's tree can still be building: keep looking while the dialog is open.
            let later = LaterScan()
            // Looks for what Start missed (the name, the mute button, or both); keeps the last look that found any.
            let needName = detected.title == nil, needMute = muteButton == nil
            if needName || needMute {
                later.task = Task.detached {
                    var best: MeetingApps.Scan?
                    for _ in 0..<5 {
                        try? await Task.sleep(for: .seconds(1))
                        let scan = MeetingApps.scan(limit: 2)
                        let named = scan.detected.title != nil, muted = scan.mute != nil
                        if (needName && named) || (needMute && muted) { best = scan }
                        if (!needName || named) && (!needMute || muted) { return scan }
                    }
                    return best
                }
            }
            // A repeating meeting (same time last week, or daily) is named like last time, unless the app named it.
            let guess = detected.title ?? MeetingNames.repeating(names, at: Date(), app: detected.app) ?? ""
            guard let answer = askMeetingName(guess, recent: MeetingNames.recent(names), later: later) else { return } // Cancel: no session, no file
            if let scan = later.result {
                let found = scan.detected
                if detected.app == nil || (detected.title == nil && found.app == detected.app) { detected = found }
                muteButton = muteButton ?? scan.mute
            }
            title = answer.isEmpty ? nil : answer
        }
        front?.activate()

        let start = Date()
        if let title {
            do {
                try MeetingNames.save(MeetingNames.adding(names, title: title, app: detected.app, start: start), to: namesFile)
            } catch {
                NSLog("Shepit meeting names: %@", String(describing: error))
            }
        }
        let folder = settings.meetingsFolderURL(home: Paths.home)
        let relative = MeetingFileName.relativePath(settings.meetingFileName, start: start, title: title, app: detected.app)
        let note = MeetingFileName.unique(relative, in: folder) { FileManager.default.fileExists(atPath: $0.path) }
        let engine = settings.engines[.meetings] ?? Settings.defaults.engines[.meetings]!
        let config = MeetingConfig(noteFile: note, frontMatter: MeetingNote.frontMatter(start: start, title: title, app: detected.app),
                                   myName: settings.myName(),
                                   sessionDir: Self.meetingSessionsRoot.appending(path: "meeting-\(UUID().uuidString)", directoryHint: .isDirectory),
                                   stateDir: Paths.dataDir, engine: engine)
        let session = MeetingSession(config: config, mic: MicSource(recorder: recorder, device: settings.microphone),
                                     call: CallTapSource(), services: meetingServices(language: settings.meetingLanguage))
        session.onState = { [weak self] _ in self?.menu?.refreshTitle() }
        // Notices from start() (no speaker model, microphone fallback) go with the "started" message:
        // shown on their own, the next message replaced them at once.
        final class Box { var items: [String] = [] }
        let startNotices = Box()
        session.onNotice = { startNotices.items.append($0) }
        session.onFinished = { [weak self] record in
            self?.meetingTimer?.cancel()
            self?.meetingTimer = nil
            self?.meetingMute?.cancel()
            self?.meetingMute = nil
            self?.recordMeeting(record)
        }
        recorder.onDictationStart = { [weak session] in session?.dictationStarted(at: $0) }
        recorder.onDictationEnd = { [weak session] in session?.dictationEnded(at: $0) }
        do {
            try session.start()
        } catch {
            showAlert(error.localizedDescription)
            return
        }
        session.onNotice = { [weak self] in self?.panel.message($0) }
        meeting = session
        meetingTimer = TimerBox(repeating: 1) { [weak session] in session?.tick() }
        let recorder = recorder
        meetingMute = MuteWatch(muteButton) { [weak session] muted in session?.micMuted(muted, at: recorder.streamPosition) }
        panel.message("⏺ Meeting transcript started", detail: startNotices.items.joined(separator: " "))
        menu?.refreshTitle()
    }

    /// One stats row per meeting: numbers and the engine only (`05-statistics.md` §1).
    func recordMeeting(_ record: MeetingRecord) {
        guard settings.collectStats else { return }
        do {
            try stats.insertMeeting(record)
        } catch {
            NSLog("Shepit statistics: %@", String(describing: error))
        }
    }

    /// Recognition for meetings: the `meetings` engine, segment times, dictionary fixes on every segment.
    /// Prompt and dictionary are taken at Start, like the engine (spec §6: changes apply to the next session).
    private func meetingServices(language: String) -> MeetingServices {
        let models = models
        let template = request([], language: language, segments: true)
        let dictionary = dictionaryStore.dictionary
        let speakers: (@Sendable ([Float]) async throws -> [SpeakerTurn])? =
            MeetingModel.diarization.isDownloaded() ? { @Sendable samples in try await Diarizer.turns(samples) } : nil
        return MeetingServices(
            makeVAD: { SileroDetector(vad: try SileroVAD()) },
            transcribe: { samples, leaning in
                var request = template
                request.samples = samples
                request.leaning = leaning
                var transcript = try await MeetingLanguage.transcribe(request) { try await models.transcribe(.meetings, $0) }
                transcript.segments = transcript.segments.map {
                    Segment(text: DictionaryRules.process($0.text, dictionary).text, start: $0.start, end: $0.end)
                }
                transcript.text = DictionaryRules.process(transcript.text, dictionary).text
                return transcript
            },
            speakers: speakers)
    }

    /// The meeting-name dialog: prefilled with the detected name; Enter accepts, Cancel returns nil. A name
    /// found by `later` while the dialog is open fills the field, unless something was typed already.
    private func askMeetingName(_ detected: String, recent: [String], later: LaterScan) -> String? {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Meeting name"
        alert.informativeText = recent.isEmpty ? "Used in the note's file name. Leave empty for none."
            : "Used in the note's file name. Leave empty for none. ▾ lists recent names."
        // A combo box: type a name or pick one used before (kept locally in meeting-names.json).
        let field = NSComboBox(frame: NSRect(x: 0, y: 0, width: 320, height: 26))
        field.stringValue = detected
        field.addItems(withObjectValues: recent)
        field.numberOfVisibleItems = 12
        field.completes = true
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.addButton(withTitle: "Start")
        alert.addButton(withTitle: "Cancel")
        let filler = later.task.map { task in
            Task { @MainActor in
                guard let scan = await task.value else { return }
                later.result = scan
                if field.stringValue == detected, let name = scan.detected.title {
                    field.stringValue = name
                    field.currentEditor()?.selectAll(nil)
                }
            }
        }
        let response = alert.runModal()
        filler?.cancel()
        guard response == .alertFirstButtonReturn else { return nil }
        return field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The newest note (`last-meeting`, spec §5.7), or a notice when it's gone.
    func lastMeetingNote() -> URL? {
        let file = Paths.dataDir.appending(path: MeetingSession.lastMeetingFile)
        guard let path = try? String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            panel.message("No meeting transcript yet")
            return nil
        }
        let note = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: note.path) else {
            panel.message("The last meeting transcript was moved or deleted")
            return nil
        }
        return note
    }

    func copyLastMeeting() {
        guard let note = lastMeetingNote(), let text = try? String(contentsOf: note, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(MeetingNote.stripFrontMatter(text), forType: .string)
        panel.message("📋 Meeting transcript copied")
    }

    func openMeetingsFolder() {
        let folder = settings.meetingsFolderURL(home: Paths.home)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            showAlert("Can't create \(folder.path): \(error.localizedDescription)")
            return
        }
        NSWorkspace.shared.open(folder)
    }

    /// Rename speakers (spec §5.7): one prompt per label in order of first appearance; empty or unchanged = skip,
    /// Cancel = stop asking (names given so far still apply). Only header lines change, via temp file + rename.
    func renameSpeakers(in note: URL) {
        guard !meetingActive else { return }
        guard let text = try? String(contentsOf: note, encoding: .utf8) else {
            showAlert("Can't read \(note.lastPathComponent)")
            return
        }
        let labels = Speakers.labels(in: text)
        guard !labels.isEmpty else {
            panel.message("No speakers in \(note.lastPathComponent)")
            return
        }
        var names: [String: String] = [:]
        for (index, speaker) in labels.enumerated() {
            guard let name = askSpeakerName(speaker, number: index + 1, of: labels.count) else { break }
            names[speaker.label] = name
        }
        // Read again: the prompts can take minutes, and the note may have been edited meanwhile (Obsidian).
        guard !names.isEmpty, let current = try? String(contentsOf: note, encoding: .utf8) else { return }
        let renamed = Speakers.rename(current, names)
        guard renamed != current else { return }
        do {
            try Data(renamed.utf8).write(to: note, options: .atomic)
            panel.message("✏️ Speakers renamed in \(note.lastPathComponent)")
        } catch {
            showAlert("Can't write \(note.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// A note for "Rename speakers in another note…", picked in `meetingsFolder`.
    func pickMeetingNote() -> URL? {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.message = "Choose a meeting note"
        panel.prompt = "Rename speakers"
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.allowsMultipleSelection = false
        let folder = settings.meetingsFolderURL(home: Paths.home)
        if FileManager.default.fileExists(atPath: folder.path) { panel.directoryURL = folder }
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func askSpeakerName(_ speaker: (label: String, firstAt: String, firstText: String), number: Int, of total: Int) -> String? {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Who is \(speaker.label)? (\(number) of \(total))"
        let quote = speaker.firstText.count > 200 ? String(speaker.firstText.prefix(200)) + "…" : speaker.firstText
        alert.informativeText = "First said at \(speaker.firstAt):\n“\(quote)”\n\nLeave empty to keep the label. The same name for two labels merges them."
        let field = NSTextField(string: "")
        field.placeholderString = speaker.label
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.addButton(withTitle: number < total ? "Next" : "Rename")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Quit mid-session: ask first (spec §5.10). Returns false when the user keeps the app running.
    func confirmQuitDuringMeeting() -> Bool {
        guard meetingActive else { return true }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "A meeting transcript is recording"
        alert.informativeText = "Quitting stops it. What was written stays in the note, marked as interrupted."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Keep recording")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func interruptMeeting() {
        meeting?.interrupt()
        meetingTimer?.cancel()
        meetingTimer = nil
        meetingMute?.cancel()
        meetingMute = nil
    }

    /// whisper.cpp's Metal device asserts in its static destructor if a context is still alive at exit():
    /// unload every engine before quitting.
    func prepareToQuit() async {
        interruptMeeting()
        await models.setChoices([:])
    }
}

struct SileroDetector: VoiceDetector {
    let vad: SileroVAD
    func probability(_ frame: [Float]) async throws -> Float { try await vad.probability(frame) }
}

/// The shared microphone as a meeting stream.
@MainActor
final class MicSource: MeetingAudioSource {
    private let recorder: AudioRecorder
    private let device: String

    init(recorder: AudioRecorder, device: String) {
        self.recorder = recorder
        self.device = device
    }

    func start(onSamples: @escaping @Sendable ([Float], Int) -> Void, onFailure: @escaping @MainActor (String) -> Void) throws -> String? {
        recorder.onStreamLost = onFailure
        return try recorder.startStream(deviceName: device, onSamples: onSamples)
    }

    func stop() {
        recorder.stopStream()
        recorder.onStreamLost = nil
    }
}

/// The call tap as a meeting stream.
@MainActor
final class CallTapSource: MeetingAudioSource {
    private let tap = CallTap()

    func start(onSamples: @escaping @Sendable ([Float], Int) -> Void, onFailure: @escaping @MainActor (String) -> Void) throws -> String? {
        tap.onSamples = onSamples
        tap.onFailure = onFailure
        try tap.start()
        return nil
    }

    func stop() { tap.stop() }
}

/// A look at the meeting apps still running while the name dialog is open.
@MainActor
final class LaterScan {
    var task: Task<MeetingApps.Scan?, Never>?
    var result: MeetingApps.Scan?
}
