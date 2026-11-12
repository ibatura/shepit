import AppKit
import ServiceManagement
import ShepitCore
import ShepitEngines

/// Wires the pieces together (port of init.lua): settings and dictionary stores, engines,
/// recorder, hotkeys, panel, live draft, menu — and is the controller's window to the system.
@MainActor
final class AppHost: ControllerHost {
    static let promptTokens = 200.0

    let settingsStore = SettingsStore(file: Paths.settingsFile)
    let dictionaryStore = DictionaryStore(file: Paths.dictionaryFile)
    let recorder = AudioRecorder()
    let stats = StatsDatabase(file: Paths.dataDir.appending(path: "stats.sqlite"))
    lazy var models = ModelHost(factory: EngineFactory.make, onLoad: { [weak self] choice, seconds in
        Task { @MainActor in self?.recordLoad(choice, seconds) }
    })
    private let hotkeys = HotkeyCenter(registrar: CarbonHotkeyRegistrar())
    lazy var panel = OverlayPanel(style: { [unowned self] in self.settings.overlayStyle },
                                          tail: { [unowned self] in self.recorder.tail($0) })
    private var preview: LivePreview!
    private(set) lazy var controller = Controller(host: self)
    var menu: MenuController?
    /// The current or last meeting (AppHost+Meetings.swift).
    var meeting: MeetingSession?
    var meetingTimer: TimerBox?
    var meetingMute: MuteWatch?
    /// `meeting-names.json` as it was before this session added its name; nil when it added none.
    var meetingNamesBefore: [MeetingNames.Entry]?
    private lazy var settingsModel = SettingsModel(store: settingsStore, dictionaryStore: dictionaryStore)
    private lazy var settingsWindow = SettingsWindow(model: settingsModel, actions: SettingsActions(
        microphones: { AudioRecorder.inputDevices().map(\.name) },
        hotkeyProblem: { [unowned self] in self.hotkeyProblem },
        openSettingsFile: { [unowned self] in self.edit(Paths.settingsFile, empty: "{}") },
        openDataFolder: { NSWorkspace.shared.open(Paths.dataDir) },
        openHistory: { [unowned self] in self.perform(.openHistory) },
        openMeetingsFolder: { [unowned self] in self.openMeetingsFolder() },
        clearHistory: { [unowned self] in self.perform(.clearHistory) },
        clearStatistics: { [unowned self] in self.clearStatistics() },
        setLaunchAtLogin: { Self.setLaunchAtLogin($0) },
        suspendHotkeys: { [unowned self] in self.hotkeys.suspend() },
        resumeHotkeys: { [unowned self] in self.hotkeys.apply(self.settings) },
        previewOverlay: { [unowned self] in self.previewOverlay() },
        statistics: { [unowned self] in (try? self.stats.dictations(in: $0)) ?? [] },
        meetingStatistics: { [unowned self] in (try? self.stats.meetings(in: $0)) ?? [] },
        languageNote: { choice, language in await Self.languageNote(choice, language) },
        downloads: downloads))
    private let downloads = ModelDownloads()
    private var dictationLoad = LoadState.unloaded
    private var configErrors: [String] = []
    private var microphoneNotice: String?
    /// The settings the hotkeys and engines were last set up for.
    private var applied: ShepitCore.Settings?
    private var poller: TimerBox?
    /// Engine, language and draft count as they were when the recording stopped (settings may change meanwhile).
    private var finishedRecording: (engine: EngineChoice?, language: String, previews: Int)?

    var settings: Settings { settingsStore.settings }

    func start() {
        try? FileManager.default.createDirectory(at: Paths.configDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: Paths.dataDir, withIntermediateDirectories: true)
        // Teams and Chrome build their accessibility tree only when asked, and slowly: ask early (MeetingApps).
        DispatchQueue.global(qos: .utility).async { MeetingApps.keepAccessibilityBuilt() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: nil) { _ in
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) { MeetingApps.keepAccessibilityBuilt() }
        }
        settingsModel.onChange = { [unowned self] in self.reloadConfig(announce: false) }
        reloadConfig(announce: false, initial: true)
        let models = models
        preview = LivePreview(.init(
            enabled: { [unowned self] in self.draftWanted },
            every: { seconds, action in TimerBox(repeating: seconds, action) },
            tail: { [unowned self] in self.recorder.tail($0) },
            transcribe: { [unowned self] samples in try await models.transcribe(.preview, self.request(samples)) },
            process: { [unowned self] in DictionaryRules.process($0, self.dictionaryStore.dictionary).text },
            onText: { [unowned self] in self.panel.preview($0) }))
        menu = MenuController(view: { [unowned self] in self.menuView() }, title: { [unowned self] in self.titleView() },
                              perform: { [unowned self] in self.perform($0) })
        hotkeys.onDictationDown = { [unowned self] in self.controller.hotkeyDown() }
        hotkeys.onDictationUp = { [unowned self] in self.controller.hotkeyUp() }
        hotkeys.onCancel = { [unowned self] in self.controller.cancel() }
        hotkeys.onAddWord = { [unowned self] in Task { await self.addToDictionary() } }
        recorder.onLost = { [unowned self] message, samples in
            if samples == nil { self.controller.recorderFailed(message) } else { self.controller.finishRecording(message) }
        }
        tidyUp()
        recoverMeeting()
        syncLoginItem()
        Task { await self.models.preload([.dictation, .preview]) }
        // Settings files, model status and the Lua tool's hotkey change without an event we can rely on
        // (a directory watch misses in-place saves), so check every 2 s; the files are tiny.
        poller = TimerBox(repeating: 2) { [unowned self] in self.poll() }
    }

    // MARK: settings

    /// Re-reads settings.json and dictionary.json and applies what changed.
    func reloadConfig(announce: Bool, initial: Bool = false) {
        let settingsOK = settingsStore.load()
        let dictionaryOK = dictionaryStore.load()
        configErrors = settingsStore.errors + dictionaryStore.errors
        // Compared with what was last applied: a write from Settings or the menu has already changed the store.
        let before = applied
        let after = settings
        applied = after
        settingsModel.refresh()
        if initial || before?.hotkey != after.hotkey || before?.addWordHotkey != after.addWordHotkey || before?.cancelKey != after.cancelKey {
            hotkeys.apply(after)
        }
        if initial || before?.engines != after.engines || before?.idleUnloadMinutes != after.idleUnloadMinutes {
            let engines = after.engines
            let minutes = after.idleUnloadMinutes
            Task {
                await self.models.setChoices(engines)
                await self.models.setIdleUnload(minutes: minutes)
            }
        }
        if announce, settingsOK, dictionaryOK { panel.message("Config reloaded") }
        menu?.refreshTitle()
    }

    private func update(_ key: String, _ value: Any) {
        do {
            try settingsStore.update(key, value)
        } catch {
            showAlert(error.localizedDescription)
        }
        reloadConfig(announce: false)
    }

    /// Draft text needs the panel, the setting, and the preview engine on disk.
    private var draftWanted: Bool {
        settings.overlay && settings.livePreview && settings.engines[.preview].map { ModelCatalog.isDownloaded($0) } == true
    }

    func request(_ samples: [Float], language: String? = nil, segments: Bool = false) -> TranscriptionRequest {
        TranscriptionRequest(
            samples: samples,
            language: Language(rawValue: language ?? settings.language) ?? .uk,
            prompt: DictionaryRules.buildPrompt(style: settings.stylePrompt, terms: dictionaryStore.dictionary.terms, maxTokens: Self.promptTokens),
            wantSegments: segments,
            englishPrompt: DictionaryRules.buildPrompt(style: "", terms: dictionaryStore.dictionary.terms, maxTokens: Self.promptTokens))
    }

    private func poll() {
        reloadConfig(announce: false)
        Task {
            let load = await self.models.loadState(.dictation)
            if load != self.dictationLoad {
                self.dictationLoad = load
                self.menu?.refreshTitle()
            }
        }
    }

    /// Old history entries and old failed audio (retention settings).
    private func tidyUp() {
        if settings.historyDays > 0 {
            History.prune(Paths.historyFile, before: Date().addingTimeInterval(-Double(settings.historyDays) * 86_400))
        }
        FailedAudio.cleanup(Paths.failedDir, olderThanHours: settings.failedAudioHours, now: Date())
    }

    private func recordLoad(_ choice: EngineChoice, _ seconds: Double) {
        guard settings.collectStats else { return }
        try? stats.insertModelLoad(engine: choice, seconds: seconds, residentMB: residentMemoryMB(), at: Date())
    }

    // MARK: menu

    /// Just what the menu-bar title needs; refreshed often, so no device or disk lookups.
    private func titleView() -> MenuView {
        var view = MenuView()
        view.state = controller.state
        view.load = dictationLoad
        view.settings = settings
        view.hotkeyProblem = hotkeyProblem
        view.meeting = meeting?.state ?? .idle
        return view
    }

    private func menuView() -> MenuView {
        var view = MenuView()
        view.state = controller.state
        view.load = dictationLoad
        view.settings = settings
        view.downloaded = ModelCatalog.downloadedChoices()
        view.configErrors = configErrors
        view.hotkeyProblem = hotkeyProblem
        view.recent = settings.historyMenuItems > 0 ? History.recent(Paths.historyFile, count: settings.historyMenuItems) : nil
        view.today = String(History.stamp(Date()).prefix(10))
        view.microphones = AudioRecorder.inputDevices().map(\.name)
        view.accessibilityGranted = Permissions.accessibilityGranted
        view.microphoneDenied = Permissions.microphoneDenied
        view.meeting = meeting?.state ?? .idle
        view.meetingMissing = meetingMissing
        return view
    }

    private var hotkeyProblem: String? {
        switch hotkeys.state {
        case .active: nil
        case .failed(let errors): errors.joined(separator: "; ")
        }
    }

    private func previewOverlay() {
        panel.recording(Date())
        panel.preview("Сьогодні я відкрив pull request у GitHub і попросив колегу зробити code review")
        _ = TimerBox(after: 3) { [unowned self] in self.panel.done("Сьогодні я відкрив pull request у GitHub.") }
    }

    /// Opens Settings (menu, or launching the app again).
    func showSettings() {
        settingsWindow.show()
    }

    /// Asks the engine itself (Apple's languages depend on the system), without loading a model.
    private static func languageNote(_ choice: EngineChoice, _ language: String) async -> String? {
        guard let language = Language(rawValue: language), let engine = try? EngineFactory.make(choice) else { return nil }
        guard await engine.capabilities.check(language) != nil else { return nil }
        let name = MenuModel.engineTitle(choice)
        return language == .auto
            ? "⚠ \(name) can't detect the language — choose Ukrainian or English in General"
            : "⚠ \(name) can't be set to \(language == .uk ? "Ukrainian" : "English") — it detects the language itself"
    }

    /// The login item follows `launchAtLogin` (default on) — set up on the first start after install.
    private func syncLoginItem() {
        let registered = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
        if settings.launchAtLogin != registered { _ = Self.setLaunchAtLogin(settings.launchAtLogin) }
    }

    /// Registers or removes the login item; returns a problem to show next to the toggle.
    private static func setLaunchAtLogin(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            return "Could not change the login item: \(error.localizedDescription)"
        }
        return SMAppService.mainApp.status == .requiresApproval ? "Allow Shepit in System Settings → General → Login Items" : nil
    }

    private func clearStatistics() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Clear statistics?"
        alert.informativeText = "Deletes all recorded usage statistics on this Mac. This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try stats.clear()
            panel.message("🗑 Statistics cleared")
        } catch {
            showAlert(error.localizedDescription)
        }
    }

    func perform(_ action: MenuAction) {
        switch action {
        case .setMode(let mode): update("mode", mode)
        case .setLanguage(let language): update("language", language)
        case .setMicrophone(let name): update("microphone", name)
        case .setEngine(let choice):
            var engines = settings.engines
            engines[.dictation] = choice
            update("engines", Dictionary(uniqueKeysWithValues: engines.map { ($0.key.rawValue, ["engine": $0.value.engine.rawValue, "model": $0.value.model]) }))
        case .addToDictionary: Task { await addToDictionary() }
        case .editDictionary: edit(Paths.dictionaryFile, empty: #"{"terms": [], "replace": {}, "dropPhrases": []}"#)
        case .openSettings: showSettings()
        case .openStatistics: settingsWindow.show(.statistics)
        case .reloadConfig: reloadConfig(announce: true)
        case .reloadModels:
            let engines = settings.engines
            Task {
                await self.models.setChoices([:])
                await self.models.setChoices(engines)
                await self.models.preload([.dictation, .preview])
            }
        case .openHistory:
            if !FileManager.default.fileExists(atPath: Paths.historyFile.path) {
                try? History.append("(history started)", to: Paths.historyFile, at: Date())
            }
            openInTextEditor(Paths.historyFile)
        case .clearHistory: clearHistory()
        case .copyText(let text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            panel.message("📋 Скопійовано")
        case .grantAccessibility: Permissions.requestAccessibility()
        case .grantMicrophone: Permissions.requestMicrophone()
        case .startMeeting: Task { await startMeeting() }
        case .stopMeeting: Task { await meeting?.stop() }
        case .copyLastMeeting: copyLastMeeting()
        case .openMeetingsFolder: openMeetingsFolder()
        case .renameSpeakers: if let note = lastMeetingNote() { renameSpeakers(in: note) }
        case .renameSpeakersInNote: if let note = pickMeetingNote() { renameSpeakers(in: note) }
        case .quit: NSApp.terminate(nil)
        }
    }

    private func edit(_ file: URL, empty: String) {
        if !FileManager.default.fileExists(atPath: file.path) {
            try? empty.write(to: file, atomically: true, encoding: .utf8)
        }
        openInTextEditor(file)
    }

    private func openInTextEditor(_ file: URL) {
        let editor = NSWorkspace.shared.urlForApplication(toOpen: .plainText) ?? URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        NSWorkspace.shared.open([file], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
    }

    private func clearHistory() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Clear dictation history?"
        alert.informativeText = "Deletes everything in history.log and the kept audio of failed attempts. This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        try? History.clear(Paths.historyFile)
        FailedAudio.cleanup(Paths.failedDir, olderThanHours: 0, now: Date().addingTimeInterval(1))
        panel.message("🗑 History cleared")
    }

    /// Selected text (or nothing) → dialog → rule in dictionary.json.
    private func addToDictionary() async {
        let selected = await Paster.readSelection()
        let prompt = AddWord.prompt(selected: selected, existing: selected.isEmpty ? nil : dictionaryStore.ruleFor(selected))
        NSApp.activate() // the dialog needs Shepit in front to take keyboard input
        let alert = NSAlert()
        alert.messageText = prompt.title
        alert.informativeText = prompt.message
        let field = NSTextField(string: prompt.defaultValue)
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.addButton(withTitle: "Додати")
        alert.addButton(withTitle: "Скасувати")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        switch AddWord.parse(selected: selected, input: field.stringValue) {
        case .error(let message):
            panel.message(message)
        case .rule(let wrong, let right):
            do {
                try dictionaryStore.addRule(wrong: wrong, right: right)
                panel.message(wrong.isEmpty ? "📖 + \(right)" : "📖 \(wrong) → \(right)")
            } catch {
                showAlert(error.localizedDescription)
            }
        }
    }

    func showAlert(_ message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Shepit"
        alert.informativeText = message
        alert.runModal()
    }

    // MARK: ControllerHost

    var mode: String { settings.mode }
    var maxRecordingSeconds: Double { Double(settings.maxRecordingSeconds) }
    var dictationBlocked: String? {
        settings.meetingBlocksDictation && meetingActive ? "Dictation is off while a meeting is recording (Settings → Meetings)" : nil
    }

    func now() -> Date { Date() }

    func after(_ seconds: Double, _ action: @escaping @MainActor () -> Void) -> any TimerToken {
        TimerBox(after: seconds, action)
    }

    func frontApp() -> AppRef? {
        NSWorkspace.shared.frontmostApplication.map { AppRef(bundleID: $0.bundleIdentifier, name: $0.localizedName ?? "") }
    }

    func startRecording() throws {
        microphoneNotice = try recorder.start(deviceName: settings.microphone)
    }

    func stopRecording() -> [Float] { recorder.stop() }
    func cancelRecording() { recorder.cancel() }

    func transcribe(_ samples: [Float]) async throws -> Transcript {
        try await models.transcribe(.dictation, request(samples))
    }

    func process(_ text: String) -> (text: String, fired: [String]) {
        DictionaryRules.process(text, dictionaryStore.dictionary)
    }

    func appendHistory(_ text: String) {
        guard settings.saveHistory else { return }
        do {
            try History.append(text, to: Paths.historyFile, at: Date())
        } catch {
            panel.message("Could not write history: \(error.localizedDescription)")
        }
    }

    func paste(_ text: String, into app: AppRef?) async -> PasteOutcome {
        await Paster.paste(text, into: app, refocus: settings.refocusOriginalApp, restoreClipboard: settings.restoreClipboard)
    }

    func keepFailed(_ samples: [Float]) -> URL? {
        try? FailedAudio.keep(samples, in: Paths.failedDir, hours: settings.failedAudioHours, now: Date())
    }

    func setState(_ state: ControllerState) { menu?.refreshTitle() }

    /// Notices reach the user through the panel (`overlay` events); with the panel off,
    /// messages still show as a short transient panel.
    func notify(_ message: String) {}

    func overlay(_ event: OverlayEvent) {
        switch event {
        case .message(let text): panel.message(text)
        case _ where !settings.overlay: break
        case .recording(let at): panel.recording(at)
        case .transcribing: panel.transcribing()
        case .done(let text): panel.done(text)
        case .hide: panel.hide()
        }
    }

    func sound(_ sound: Sound) {
        guard settings.sounds else { return }
        let name = switch sound {
        case .start: "Tink"
        case .done: "Pop"
        case .error: "Basso"
        }
        NSSound(named: NSSound.Name(name))?.play()
    }

    func bindCancel(_ on: Bool) { hotkeys.setCancelEnabled(on) }
    func recordingStarted() {
        // Shown as the panel's text until the first draft replaces it ("…not found — using the system default").
        if let microphoneNotice { panel.preview(microphoneNotice) }
        preview.start()
    }
    func recordingEnded() {
        preview.stop()
        finishedRecording = (settings.engines[.dictation], settings.language, preview.requests)
    }
    /// Numbers only — DictationRecord has no text field (`05-statistics.md` §1).
    func record(_ dictation: DictationRecord) {
        let used = finishedRecording ?? (settings.engines[.dictation], settings.language, preview.requests)
        guard settings.collectStats, let engine = used.engine else { return }
        let row = DictationRow(dictation, engine: engine, languageRequested: used.language, previewRequests: used.previews)
        do {
            try stats.insert(row)
        } catch {
            NSLog("Shepit statistics: %@", String(describing: error))
        }
    }
}

/// A main-run-loop Timer as a controller TimerToken.
final class TimerBox: TimerToken {
    private var timer: Timer?

    @MainActor
    init(after seconds: Double, _ action: @escaping @MainActor () -> Void) {
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in MainActor.assumeIsolated { action() } }
    }

    @MainActor
    init(repeating seconds: Double, _ action: @escaping @MainActor () -> Void) {
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { _ in MainActor.assumeIsolated { action() } }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}
