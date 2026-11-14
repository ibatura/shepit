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
        let engine = settings.engine(for: .meetings)
        return ModelCatalog.isDownloaded(engine) && MeetingModel.vad.isDownloaded() ? nil : "download the model in Settings"
    }

    var meetingActive: Bool { meeting?.state.isActive == true }

    func recoverMeeting() {
        if let note = MeetingSession.recover(stateDir: Paths.dataDir, sessionsRoot: Self.meetingSessionsRoot, now: Date()) {
            addToMeetings(note, you: settings.myName())
            panel.message("⚠ The last meeting transcript was interrupted: \(note.lastPathComponent)")
        }
    }

    /// Puts a note in the meetings list (Meetings design §4); a failure is logged, the note itself is kept.
    func addToMeetings(_ note: URL, you: String, start: Date? = nil, duration: TimeInterval? = nil) {
        do {
            _ = try meetings.add(note: note, you: you, start: start, duration: duration)
        } catch {
            NSLog("Shepit meetings list: %@", String(describing: error))
        }
        refreshStatus()
    }

    /// The meeting hotkey: what the menu's Start or Stop does at this moment.
    func toggleMeeting() {
        switch MeetingControl(meeting?.state ?? .idle, missing: meetingMissing) {
        case .stop: Task { await meeting?.stop() }
        case .busy: panel.message("Transcript is finishing")
        case .blocked(let missing): panel.message("⚠ Meeting transcript not started", detail: missing)
        case .start: Task { await startMeeting() }
        }
    }

    func startMeeting() async {
        guard !meetingActive, meetingMissing == nil, !startingByHand else { return }
        startingByHand = true
        defer { startingByHand = false }
        let settings = settings
        let front = NSWorkspace.shared.frontmostApplication
        let first = await Task.detached {
            MeetingApps.keepAccessibilityBuilt()
            return MeetingApps.scan(limit: 2)
        }.value
        var detected = first.detected
        var muteButton = first.mute
        var title = detected.title
        let names = MeetingNames.load(Paths.dataDir.appending(path: MeetingNames.fileName))
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
            let guess = detected.title ?? MeetingNames.repeating(names, at: Date(), app: detected.app?.rawValue) ?? ""
            guard let answer = askMeetingName(guess, recent: MeetingNames.recent(names), later: later) else { return } // Cancel: no session, no file
            if let scan = later.result {
                let found = scan.detected
                if detected.app == nil || (detected.title == nil && found.app == detected.app) { detected = found }
                muteButton = muteButton ?? scan.mute
            }
            title = answer.isEmpty ? nil : answer
        }
        front?.activate()
        startMeeting(title: title, app: detected.app, mute: muteButton)
    }

    /// Starts a transcript with the name and app as given, without asking (call offer design §5.4).
    /// Without `mute`, `MuteWatch` looks for the button itself. `fromCall`: started by the call panel.
    func startMeeting(title: String?, app: CallApp?, mute muteButton: MuteButton? = nil, fromCall: Bool = false) {
        guard !meetingActive, meetingMissing == nil else { return }
        let settings = settings
        let start = Date()
        meetingNamesBefore = nil
        if let title {
            let namesFile = Paths.dataDir.appending(path: MeetingNames.fileName)
            let names = MeetingNames.load(namesFile)
            do {
                try MeetingNames.save(MeetingNames.adding(names, title: title, app: app?.rawValue, start: start), to: namesFile)
                meetingNamesBefore = names
            } catch {
                NSLog("Shepit meeting names: %@", String(describing: error))
            }
        }
        let folder = settings.meetingsFolderURL(home: Paths.home)
        let relative = MeetingFileName.relativePath(settings.meetingFileName, start: start, title: title, app: app?.rawValue)
        let note = MeetingFileName.unique(relative, in: folder) { FileManager.default.fileExists(atPath: $0.path) }
        let engine = settings.engine(for: .meetings)
        var config = MeetingConfig(noteFile: note, frontMatter: MeetingNote.frontMatter(start: start, title: title, app: app?.rawValue),
                                   myName: settings.myName(),
                                   sessionDir: Self.meetingSessionsRoot.appending(path: "meeting-\(UUID().uuidString)", directoryHint: .isDirectory),
                                   stateDir: Paths.dataDir, engine: engine)
        config.title = title
        config.app = app
        let session = MeetingSession(config: config, mic: MicSource(recorder: recorder, device: settings.microphone),
                                     call: CallTapSource(), services: meetingServices(language: settings.meetingLanguage))
        session.onState = { [weak self] state in
            self?.refreshStatus() // every second while it records: the clock
            switch state {
            case .finishing, .detectingSpeakers: self?.callEvent(.sessionStopping)
            default: break
            }
        }
        // Notices from start() (no speaker model, microphone fallback) go with the "started" message:
        // shown on their own, the next message replaced them at once.
        final class Box { var items: [String] = [] }
        let startNotices = Box()
        session.onNotice = { startNotices.items.append($0) }
        session.onFinished = { [weak self, weak session] record in
            guard let self, let session else { return }
            self.meetingTimer?.cancel()
            self.meetingTimer = nil
            self.meetingMute?.cancel()
            self.meetingMute = nil
            let detail = CallOffer.readyDetail(title: title, duration: record.duration, speakers: record.speakers)
            // An empty transcript of a call is removed and gets no statistics row.
            let effects = self.callEvent(.sessionFinished(entries: session.entries, detail: detail))
            guard !effects.contains(.removeEmptyNote) else { return }
            self.addToMeetings(note, you: config.myName, start: record.start, duration: record.duration)
            self.recordMeeting(record)
            // The call panel says "Transcript ready", unless an offer or a stop countdown is in its place.
            if case .ready = self.callOffer.panel {} else { self.panel.message("Transcript ready", detail: detail) }
        }
        recorder.onDictationStart = { [weak session] in session?.dictationStarted(at: $0) }
        recorder.onDictationEnd = { [weak session] in session?.dictationEnded(at: $0) }
        do {
            try session.start()
        } catch {
            restoreMeetingNames() // a transcript that never started leaves no name behind
            showAlert(error.localizedDescription)
            return
        }
        session.onNotice = { [weak self] in self?.panel.message($0) }
        meeting = session
        meetingTimer = TimerBox(repeating: 1) { [weak session] in session?.tick() }
        let recorder = recorder
        meetingMute = MuteWatch(muteButton) { [weak session] muted in session?.micMuted(muted, at: recorder.streamPosition) }
        panel.message("⏺ Meeting transcript started", detail: startNotices.items.joined(separator: " "))
        refreshStatus()
        callEvent(.sessionStarted(byPanel: fromCall))
    }

    /// A finished transcript of a call without a single entry leaves nothing behind (call offer design §5.4):
    /// no note, no name in `meeting-names.json`, the earlier `last-meeting`. Called in place of `recordMeeting`.
    func removeEmptyMeeting() {
        guard let meeting, meeting.removeEmptyNote() else { return }
        panel.message("Empty meeting transcript removed")
        restoreMeetingNames()
    }

    /// Puts `meeting-names.json` back as it was before this transcript's name was added.
    private func restoreMeetingNames() {
        if let names = meetingNamesBefore {
            do {
                try MeetingNames.save(names, to: Paths.dataDir.appending(path: MeetingNames.fileName))
            } catch {
                NSLog("Shepit meeting names: %@", String(describing: error))
            }
        }
        meetingNamesBefore = nil
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
        if let session = meeting, session.state.isActive {
            session.interrupt()
            addToMeetings(session.config.noteFile, you: session.config.myName, start: session.startedAt,
                          duration: Date().timeIntervalSince(session.startedAt))
        }
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
