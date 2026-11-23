import AppKit
import SwiftUI
import ShepitCore

struct GeneralSection: View {
    let model: SettingsModel
    let actions: WindowActions
    @State private var loginProblem: String?

    var body: some View {
        Section {
            Hinted(hint: loginProblem ?? "Start Shepit when you log in") {
                Toggle("Launch at login", isOn: Binding(get: { model.settings.launchAtLogin }, set: { on in
                    model.set("launchAtLogin", on)
                    loginProblem = actions.setLaunchAtLogin(on)
                }))
            }
            Hinted(hint: "Start / done / error sounds") {
                Toggle("Sounds", isOn: model.binding("sounds", \.sounds))
            }
        }
        Section("Files") {
            HStack {
                Button("Open settings file", action: actions.openSettingsFile)
                Button("Reload settings") { actions.perform(.reloadConfig) }
                    .help("Reads settings.json again after you edit it by hand")
                Button("Open data folder", action: actions.openDataFolder)
            }
        }
    }
}

struct HotkeysSection: View {
    let model: SettingsModel
    let actions: WindowActions

    var body: some View {
        Section {
            Hinted(hint: "Toggle: press to start, press to stop. Hold: speak while holding the key") {
                ChoicePicker(title: "Mode", choices: ShepitCore.Settings.modes, selection: model.binding("mode", \.mode))
                    .pickerStyle(.segmented)
            }
            Hinted(hint: clash("hotkey", model.settings.hotkey) ?? "The dictation hotkey") {
                ShortcutField(title: "Dictation hotkey", hotkey: model.settings.hotkey, allowsModifiers: true, actions: actions,
                              refuse: { model.settings.hotkeyClash($0, for: "hotkey") }) {
                    model.set("hotkey", hotkey: $0)
                }
            }
            Hinted(hint: clash("cancelKey", Hotkey(mods: [], key: model.settings.cancelKey))
                ?? "Cancels a recording. Only active while recording, so it works normally otherwise") {
                ShortcutField(title: "Cancel key", hotkey: Hotkey(mods: [], key: model.settings.cancelKey), allowsModifiers: false, actions: actions,
                              refuse: { model.settings.hotkeyClash($0, for: "cancelKey") }) {
                    model.set("cancelKey", $0.key)
                }
            }
            Hinted(hint: clash("addWordHotkey", model.settings.addWordHotkey) ?? "Adds the selected word to the dictionary") {
                ShortcutField(title: "Add-word hotkey", hotkey: model.settings.addWordHotkey, allowsModifiers: true, actions: actions,
                              refuse: { model.settings.hotkeyClash($0, for: "addWordHotkey") }) {
                    model.set("addWordHotkey", hotkey: $0)
                }
            }
            Hinted(hint: clash("meetingHotkey", model.settings.meetingHotkey)
                ?? "Starts a meeting transcript, or stops the running one. No shortcut until you record one") {
                ShortcutField(title: "Meeting transcript hotkey", hotkey: model.settings.meetingHotkey, allowsModifiers: true, actions: actions,
                              refuse: { model.settings.hotkeyClash($0, for: "meetingHotkey") }, onRemove: { model.remove("meetingHotkey") }) {
                    model.set("meetingHotkey", hotkey: $0)
                }
            }
            if let problem = actions.hotkeyProblem() {
                Text("⚠ \(problem)").foregroundStyle(.orange)
            }
        }
    }

    /// The hint under a field whose keys another hotkey also has (a hand edit of settings.json).
    private func clash(_ key: String, _ hotkey: Hotkey?) -> String? {
        hotkey.flatMap { model.settings.hotkeyClash($0, for: key) }.map { "⚠ \($0)" }
    }
}

/// Click, then press the keys. The global hotkeys are off meanwhile, so pressing the current one records it.
struct ShortcutField: View {
    let title: String
    /// nil: no shortcut set.
    let hotkey: Hotkey?
    let allowsModifiers: Bool
    let actions: WindowActions
    /// Why a recorded shortcut can't be used, or nil when it can.
    var refuse: (Hotkey) -> String? = { _ in nil }
    /// Set for a shortcut that may be absent: shows Remove.
    var onRemove: (() -> Void)?
    let onChange: (Hotkey) -> Void
    @State private var monitor: Any?
    @State private var problem: String?

    var body: some View {
        LabeledContent(title) {
            HStack {
                if let problem { Text(problem).foregroundStyle(.orange).font(.caption) }
                Button(monitor == nil ? label : "Press keys… (click to stop)") {
                    monitor == nil ? start() : stop()
                }
                .frame(minWidth: 150)
                if let onRemove, hotkey != nil, monitor == nil { Button("Remove", action: onRemove) }
            }
        }
        .onDisappear(perform: stop)
        // The window is kept when it closes, so the field doesn't disappear: closing must end the recording as well,
        // or the monitor would go on taking keys typed in Shepit's dialogs.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in stop() }
    }

    private var label: String {
        guard let hotkey else { return "Record shortcut" }
        let symbols = ["ctrl": "⌃", "alt": "⌥", "shift": "⇧", "cmd": "⌘"]
        return hotkey.mods.compactMap { symbols[$0] }.joined() + hotkey.key.capitalized
    }

    private func start() {
        problem = nil
        actions.suspendHotkeys()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let key = KeyNames.name(forKeyCode: UInt32(event.keyCode)) else {
                problem = "That key can't be used"
                return nil
            }
            let flags = event.modifierFlags
            let mods = [(NSEvent.ModifierFlags.control, "ctrl"), (.option, "alt"), (.shift, "shift"), (.command, "cmd")]
                .filter { flags.contains($0.0) }.map(\.1)
            if allowsModifiers, mods.isEmpty, !KeyNames.isFunctionKey(key) {
                problem = "Add ⌃, ⌥, ⇧ or ⌘"
                return nil
            }
            let recorded = Hotkey(mods: allowsModifiers ? mods : [], key: key)
            if let reason = refuse(recorded) {
                problem = reason
                return nil
            }
            onChange(recorded)
            stop()
            return nil
        }
    }

    private func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        actions.resumeHotkeys()
    }
}

struct DictationSection: View {
    let model: SettingsModel
    let actions: WindowActions

    var body: some View {
        Section("Dictation") {
            Hinted(hint: "Keep Ukrainian for Ukrainian with English terms. Auto-detect may translate your speech into one language") {
                ChoicePicker(title: "Language", choices: ShepitCore.Settings.languages, selection: model.binding("language", \.language))
            }
            Hinted(hint: "System default follows the macOS input. If the chosen device isn't connected, the default is used and the panel says so") {
                Picker("Microphone", selection: Binding(get: { model.settings.microphone }, set: { model.set("microphone", $0) })) {
                    Text("System default").tag("")
                    ForEach(Microphones.choices(connected: actions.microphones(), configured: model.settings.microphone), id: \.self) { Text($0).tag($0) }
                }
            }
            Hinted(hint: "Recording stops and is transcribed automatically after this long") {
                // In seconds, not minutes (the author, 2026-11-23).
                NumberMenu(title: "Max recording length", values: [30, 60, 90, 120, 180, 300, 600, 900, 1800, 3600],
                           selection: model.binding("maxRecordingSeconds", \.maxRecordingSeconds)) { NumberMenu.count($0, "second") }
            }
        }
        Section("Text") {
            Hinted(hint: "Example text the engine imitates. Keep English terms in Latin script here — this is what makes it write pull request instead of «пул реквест»") {
                VStack(alignment: .leading) {
                    Text("Style prompt")
                    StylePromptEditor(model: model)
                }
            }
            Hinted(hint: "Paste into the app you started in, even if you switched apps while speaking") {
                Toggle("Paste into the original app", isOn: model.binding("refocusOriginalApp", \.refocusOriginalApp))
            }
            Hinted(hint: "Put your previous clipboard back after pasting") {
                Toggle("Restore clipboard", isOn: model.binding("restoreClipboard", \.restoreClipboard))
            }
        }
        DictationPanelSections(model: model, actions: actions)
    }
}

struct HistoryPrivacySection: View {
    let model: SettingsModel
    let actions: WindowActions

    var body: some View {
        Section("Dictations") {
            Group {
                Hinted(hint: "Keep every dictation in history, with the app it went to. With this off nothing new is kept") {
                    Toggle("Save history", isOn: model.binding("saveHistory", \.saveHistory))
                }
                Hinted(hint: "History entries older than this are deleted") {
                    NumberMenu(title: "Keep history", values: [0, 7, 30, 90, 180, 365, 730],
                               selection: model.binding("historyDays", \.historyDays)) { $0 == 0 ? "Forever" : NumberMenu.days($0) }
                }
                Hinted(hint: "How many recent dictations the Recent dictations submenu shows") {
                    NumberMenu(title: "Recent menu items", values: [0, 5, 10, 15, 20],
                               selection: model.binding("historyMenuItems", \.historyMenuItems)) { $0 == 0 ? "None: the submenu is hidden" : "\($0)" }
                }
                Hinted(hint: "How long the audio of a failed transcription is kept so you can retry") {
                    NumberMenu(title: "Keep failed audio", values: [0, 1, 6, 24, 72, 168],
                               selection: model.binding("failedAudioHours", \.failedAudioHours)) { $0 == 0 ? "Delete at once" : NumberMenu.hours($0) }
                }
            }
            .disabled(model.isReadOnly)
            Button("Clear history…") { actions.perform(.clearHistory) }
        }
        Section("Statistics") {
            Group {
                Hinted(hint: "Record usage statistics on this Mac: numbers only, never what you dictated") {
                    Toggle("Collect statistics", isOn: model.binding("collectStats", \.collectStats))
                }
                Hinted(hint: "Your typing speed, for “time saved” in Statistics") {
                    NumberMenu(title: "Typing speed", values: [20, 30, 40, 50, 60, 70, 80, 100],
                               selection: model.binding("typingSpeedWpm", \.typingSpeedWpm)) { "\($0) words per minute" }
                }
            }
            .disabled(model.isReadOnly)
            Button("Clear statistics…", action: actions.clearStatistics)
        }
        Section("Voices") {
            Text("Remember voices and the saved voice prints are in People, in the sidebar.").foregroundStyle(.secondary)
        }
        Section("Databases") {
            FolderRow(model: model, key: "databasesFolder", path: \.databasesFolder, url: { $0.databasesFolderURL(home: Paths.home) },
                      hint: "Where dictations, meetings and statistics are kept. Used from the next start of Shepit; files already there are not moved. A synced folder (iCloud) uploads them")
                .disabled(model.isReadOnly)
        }
    }
}

/// The style prompt in a bordered box, saved with Save; Cancel puts the saved text back.
private struct StylePromptEditor: View {
    let model: SettingsModel
    @State private var draft = ""

    var body: some View {
        let saved = model.settings.stylePrompt
        VStack(alignment: .trailing) {
            TextEditor(text: $draft)
                .font(.body)
                .frame(minHeight: 70)
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.separator)) // a field, as SettingField
            if draft != saved { // saved on purpose, as SettingField
                HStack {
                    Button("Cancel") { draft = saved }
                    Button("Save") { model.set("stylePrompt", draft) }
                }
            }
        }
        .onAppear { draft = saved }
        .onChange(of: saved) { draft = $1 }
    }
}
