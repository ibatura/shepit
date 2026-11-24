import AppKit
import ServiceManagement
import ShepitCore
import ShepitEngines

/// Wires the pieces together (port of init.lua): settings and dictionary stores, engines,
/// recorder, hotkeys, panel, live draft, menu — and is the controller's window to the system.
@MainActor
final class AppHost: ControllerHost {
    let settingsStore = SettingsStore(file: Paths.settingsFile)
    let dictionaryStore = DictionaryStore(file: Paths.dictionaryFile)
    let recorder = AudioRecorder()
    /// `databasesFolder` as it was at launch: the stores are opened there and stay there until the next start.
    /// First used after `start()` has read settings.json.
    private(set) lazy var databasesFolder = settings.databasesFolderURL(home: Paths.home)
    lazy var stats = StatsDatabase(file: databasesFolder.appending(path: "stats.sqlite"))
    lazy var meetingStore = MeetingStore(file: databasesFolder.appending(path: "meetings.sqlite"))
    lazy var dictations = DictationStore(file: databasesFolder.appending(path: "dictations.sqlite")) { [unowned self] in self.refreshHistory() }
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
    /// What `meetingMute` read last; nil until it has read the call app's button.
    var meetingMuted: Bool?
    /// `meeting-names.json` as it was before this session added its name; nil when it added none.
    var meetingNamesBefore: [MeetingNames.Entry]?
    /// The call offer (AppHost+Calls.swift).
    var callOffer = CallOffer()
    var callWatch: CallWatch?
    let callPanel = CallPanel()
    var callTicker: TimerBox?
    var callNameLookup: Task<Void, Never>?
    /// Old unnamed voices are being forgotten, off the main thread (AppHost+Meetings.swift).
    var forgettingVoices = false
    /// Start from the menu is under way (its scan, its name dialog): an automatic start stays out.
    var startingByHand = false
    private lazy var settingsModel = SettingsModel(store: settingsStore, dictionaryStore: dictionaryStore)
    private lazy var windowActions = WindowActions(
        microphones: { AudioRecorder.inputDevices().map(\.name) },
        perform: { [unowned self] in self.perform($0) },
        hotkeyProblem: { [unowned self] in self.hotkeyProblem },
        openSettingsFile: { [unowned self] in self.edit(Paths.settingsFile, empty: "{}") },
        openDictionaryFile: { [unowned self] in self.edit(Paths.dictionaryFile, empty: #"{"terms": [], "replace": {}, "dropPhrases": []}"#) },
        addWord: { [unowned self] in Task { await self.addToDictionary(readSelection: false) } },
        openDataFolder: { NSWorkspace.shared.open(Paths.dataDir) },
        clearStatistics: { [unowned self] in self.clearStatistics() },
        setLaunchAtLogin: { Self.setLaunchAtLogin($0) },
        suspendHotkeys: { [unowned self] in self.hotkeys.suspend() },
        resumeHotkeys: { [unowned self] in self.hotkeys.apply(self.settings) },
        previewOverlay: { [unowned self] in self.previewOverlay() },
        languageNote: { choice, language in await Self.languageNote(choice, language) },
        downloads: downloads)
    lazy var mainWindow = MainWindow(
        model: settingsModel, actions: windowActions,
        sections: WindowSections(meetings: MeetingsModel(store: meetingStore, settings: { [unowned self] in self.settings }),
                                 dictations: DictationsModel(store: dictations),
                                 statistics: StatisticsModel(stats: stats, typingSpeed: { [unowned self] in self.settings.typingSpeedWpm }),
                                 people: PeopleModel(store: meetingStore, settings: { [unowned self] in self.settings })),
        snapshot: { [unowned self] in self.snapshot() })
    /// The snapshot's device and disk lookups (AppHost+Window.swift says when they are gathered).
    var lookups = Lookups()
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
        menu = MenuController(view: { [unowned self] in self.gatherLookups(); return self.snapshot() }, title: { [unowned self] in self.snapshot() },
                              perform: { [unowned self] in self.perform($0) })
        hotkeys.onDictationDown = { [unowned self] in self.controller.hotkeyDown() }
        hotkeys.onDictationUp = { [unowned self] in self.controller.hotkeyUp() }
        hotkeys.onCancel = { [unowned self] in self.controller.cancel() }
        hotkeys.onAddWord = { [unowned self] in Task { await self.addToDictionary() } }
        hotkeys.onMeeting = { [unowned self] in self.toggleMeeting() }
        recorder.onLost = { [unowned self] message, samples in
            if samples == nil { self.controller.recorderFailed(message) } else { self.controller.finishRecording(message) }
        }
        tidyUp()
        recoverMeeting()
        startCallWatch()
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
        if initial || before?.hotkey != after.hotkey || before?.addWordHotkey != after.addWordHotkey || before?.cancelKey != after.cancelKey
            || before?.meetingHotkey != after.meetingHotkey {
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
        if initial || before?.theme != after.theme { applyTheme(after.theme) }
        if initial || before?.accentColor != after.accentColor { applyAccentColor(after.accentColor) }
        if announce, settingsOK, dictionaryOK { panel.message("Config reloaded") }
        refreshStatus()
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
            prompt: DictionaryRules.buildPrompt(style: settings.stylePrompt, terms: dictionaryStore.dictionary.terms),
            wantSegments: segments,
            englishPrompt: DictionaryRules.buildPrompt(style: "", terms: dictionaryStore.dictionary.terms))
    }

    private func poll() {
        reloadConfig(announce: false)
        refreshLookups()
        Task {
            let load = await self.models.loadState(.dictation)
            if load != self.dictationLoad {
                self.dictationLoad = load
                self.refreshStatus()
            }
        }
    }

    /// Old history entries and old failed audio (retention settings).
    private func tidyUp() {
        if settings.historyDays > 0 {
            _ = try? dictations.prune(before: Date().addingTimeInterval(-Double(settings.historyDays) * 86_400))
        }
        FailedAudio.cleanup(Paths.failedDir, olderThanHours: settings.failedAudioHours, now: Date())
    }

    private func recordLoad(_ choice: EngineChoice, _ seconds: Double) {
        guard settings.collectStats else { return }
        try? stats.insertModelLoad(engine: choice, seconds: seconds, residentMB: residentMemoryMB(), at: Date())
    }

    // MARK: snapshot

    /// What the menu, its title and the window show. Device and disk lookups come from `lookups`.
    func snapshot() -> AppSnapshot {
        var view = AppSnapshot()
        view.state = controller.state
        view.load = dictationLoad
        view.settings = settings
        view.configErrors = configErrors
        view.hotkeyProblem = hotkeyProblem
        view.now = Date()
        view.meeting = liveMeeting()
        view.call = callOffer.current
        view.downloaded = lookups.downloaded
        view.meetingModels = lookups.meetingModels
        view.history = lookups.history
        view.accessibilityGranted = lookups.accessibilityGranted
        view.microphoneDenied = lookups.microphoneDenied
        view.recentMeetings = lookups.recentMeetings
        return view
    }

    /// The parts of the snapshot that need a device or disk lookup.
    struct Lookups {
        var downloaded: [EngineChoice] = []
        var meetingModels: [MeetingModel] = MeetingModel.allCases
        var history: [DictationStore.Entry] = []
        var accessibilityGranted = true
        var microphoneDenied = false
        var recentMeetings: [MeetingStore.Meeting] = []
    }

    /// Enough history for Home and for the menu's Recent.
    var recentHistory: [DictationStore.Entry] {
        (try? dictations.page(limit: max(HomeModel.recentCount, settings.historyMenuItems))) ?? []
    }

    func gatherLookups() {
        lookups = Lookups(downloaded: ModelCatalog.downloadedChoices(), meetingModels: MeetingModel.allCases.filter { $0.isDownloaded() },
                          history: recentHistory,
                          accessibilityGranted: Permissions.accessibilityGranted, microphoneDenied: Permissions.microphoneDenied,
                          recentMeetings: (try? meetingStore.meetings(limit: HomeModel.recentCount)) ?? [])
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

    /// Asks the engine itself (Apple's languages depend on the system), without loading a model.
    private static func languageNote(_ choice: EngineChoice, _ language: String) async -> String? {
        guard let language = Language(rawValue: language), let engine = try? EngineFactory.make(choice) else { return nil }
        guard await engine.capabilities.check(language) != nil else { return nil }
        let name = choice.title
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
        askToClear("Clear statistics?", "Deletes all recorded usage statistics on this Mac. This cannot be undone.") { [unowned self] in
            do {
                try stats.clear()
                panel.message("🗑 Statistics cleared")
            } catch {
                showAlert(error.localizedDescription)
            }
        }
    }

    /// Clear history… and Clear statistics… are pressed in the window, so they ask in a sheet on it, as every Delete…
    /// there does (the author, 2026-11-23); a dialog of its own if no window is in front.
    private func askToClear(_ title: String, _ message: String, clear: @escaping @MainActor () -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        guard let window = NSApp.keyWindow else {
            NSApp.activate()
            if alert.runModal() == .alertFirstButtonReturn { clear() }
            return
        }
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { MainActor.assumeIsolated { clear() } }
        }
    }

    func perform(_ action: AppAction) {
        switch action {
        case .setLanguage(let language): update("language", language)
        case .setMeetingLanguage(let language): update("meetingLanguage", language)
        case .addToDictionary: Task { await addToDictionary() }
        case .openWindow: showWindow()
        case .openSettings: showWindow(.settings)
        case .openModels:
            mainWindow.navigation.openSettings(.engines)
            showWindow()
        case .reloadConfig: reloadConfig(announce: true)
        case .clearHistory: clearHistory()
        case .copyText(let text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            panel.message("📋 Copied")
        case .grantAccessibility: Permissions.requestAccessibility()
        case .grantMicrophone: Permissions.requestMicrophone()
        case .startMeeting: Task { await startMeeting() }
        case .startCall: callEvent(.startCurrent)
        case .stopMeeting: Task { await meeting?.stop() }
        case .openMeetingsFolder: openMeetingsFolder()
        case .about:
            NSApp.activate()
            NSApp.orderFrontStandardAboutPanel(nil)
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
        askToClear("Clear dictation history?", "Deletes every kept dictation and the kept audio of failed attempts. This cannot be undone.") { [unowned self] in
            do {
                try dictations.clear()
            } catch {
                return panel.message("Could not clear history: \(error.localizedDescription)")
            }
            FailedAudio.cleanup(Paths.failedDir, olderThanHours: 0, now: Date().addingTimeInterval(1))
            panel.message("🗑 History cleared")
        }
    }

    /// Selected text (or nothing) → dialog → rule in dictionary.json. The window's Add word reads no selection: ⌘C
    /// would go to Shepit itself.
    private func addToDictionary(readSelection: Bool = true) async {
        let selected = readSelection ? await Paster.readSelection() : ""
        let prompt = AddWord.prompt(selected: selected, existing: selected.isEmpty ? nil : dictionaryStore.ruleFor(selected))
        NSApp.activate() // the dialog needs Shepit in front to take keyboard input
        let alert = NSAlert()
        alert.messageText = prompt.title
        alert.informativeText = prompt.message
        let field = NSTextField(string: prompt.defaultValue)
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        switch AddWord.parse(selected: selected, input: field.stringValue) {
        case .error(let message):
            panel.message(message)
        case .rule(let wrong, let right):
            do {
                try dictionaryStore.addRule(wrong: wrong, right: right)
                settingsModel.refresh() // the open Dictionary section shows it at once
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

    func appendHistory(_ text: String, app: AppRef?) {
        guard settings.saveHistory else { return }
        do {
            try dictations.add(text: text, app: app, at: Date())
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

    func setState(_ state: ControllerState) { refreshStatus() }

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
        guard let engine = used.engine else { return }
        recordStats { try $0.insert(DictationRow(dictation, engine: engine, languageRequested: used.language, previewRequests: used.previews)) }
    }

    /// A row of stats.sqlite (numbers and names only), while collecting is on; an open Statistics section shows it at once.
    func recordStats(_ write: (StatsDatabase) throws -> Void) {
        guard settings.collectStats else { return }
        do {
            try write(stats)
            mainWindow.reload(.statistics)
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
    init(repeating seconds: Double, underDialogs: Bool = false, _ action: @escaping @MainActor () -> Void) {
        let timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { _ in MainActor.assumeIsolated { action() } }
        if underDialogs { RunLoop.main.add(timer, forMode: .common) }
        self.timer = timer
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}
