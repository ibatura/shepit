import AppKit
import SwiftUI
import ShepitCore

struct GeneralSection: View {
    let model: SettingsModel
    let actions: SettingsActions
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
            Hinted(hint: "Keep Ukrainian for Ukrainian with English terms. Auto-detect may translate your speech into one language") {
                Picker("Language", selection: model.binding("language", \.language)) {
                    Text("Ukrainian").tag("uk")
                    Text("English").tag("en")
                    Text("Auto-detect").tag("auto")
                }
            }
        }
        Section("Files") {
            HStack {
                Button("Open settings file", action: actions.openSettingsFile)
                Button("Open data folder", action: actions.openDataFolder)
            }
        }
    }
}

struct HotkeysSection: View {
    let model: SettingsModel
    let actions: SettingsActions

    var body: some View {
        Section {
            Hinted(hint: "Toggle: press to start, press to stop. Hold: speak while holding the key") {
                Picker("Mode", selection: Binding(get: { model.settings.mode }, set: { model.set("mode", $0) })) {
                    Text("Toggle").tag("toggle")
                    Text("Hold to talk").tag("hold")
                }
                .pickerStyle(.segmented)
            }
            Hinted(hint: conflict ?? "The dictation hotkey") {
                ShortcutField(title: "Dictation hotkey", hotkey: model.settings.hotkey, allowsModifiers: true, actions: actions) {
                    model.set("hotkey", hotkey: $0)
                }
            }
            Hinted(hint: "Cancels a recording. Only active while recording, so it works normally otherwise") {
                ShortcutField(title: "Cancel key", hotkey: Hotkey(mods: [], key: model.settings.cancelKey), allowsModifiers: false, actions: actions) {
                    model.set("cancelKey", $0.key)
                }
            }
            Hinted(hint: conflict ?? "Adds the selected word to the dictionary") {
                ShortcutField(title: "Add-word hotkey", hotkey: model.settings.addWordHotkey, allowsModifiers: true, actions: actions) {
                    model.set("addWordHotkey", hotkey: $0)
                }
            }
            if let problem = actions.hotkeyProblem() {
                Text("⚠ \(problem)").foregroundStyle(.orange)
            }
        }
    }

    private var conflict: String? {
        model.settings.hotkey == model.settings.addWordHotkey ? "⚠ The dictation and add-word hotkeys are the same" : nil
    }
}

/// Click, then press the keys. The global hotkeys are off meanwhile, so pressing the current one records it.
struct ShortcutField: View {
    let title: String
    let hotkey: Hotkey
    let allowsModifiers: Bool
    let actions: SettingsActions
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
            }
        }
        .onDisappear(perform: stop)
    }

    private var label: String {
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
            if allowsModifiers, mods.isEmpty, !key.hasPrefix("f") {
                problem = "Add ⌃, ⌥, ⇧ or ⌘"
                return nil
            }
            onChange(Hotkey(mods: allowsModifiers ? mods : [], key: key))
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
    let actions: SettingsActions

    var body: some View {
        Section {
            Hinted(hint: "System default follows the macOS input. If the chosen device isn't connected, the default is used and the panel says so") {
                Picker("Microphone", selection: Binding(get: { model.settings.microphone }, set: { model.set("microphone", $0) })) {
                    Text("System default").tag("")
                    ForEach(microphones, id: \.self) { Text($0).tag($0) }
                }
            }
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
            Hinted(hint: "Recording stops and is transcribed automatically after this many seconds (5–3600)") {
                Stepper(value: model.binding("maxRecordingSeconds", \.maxRecordingSeconds), in: 5...3600, step: 30) {
                    Text("Max recording length: \(model.settings.maxRecordingSeconds) s")
                }
            }
        }
    }

    /// The configured device stays in the list even while it's disconnected.
    private var microphones: [String] {
        let connected = actions.microphones()
        let current = model.settings.microphone
        return current.isEmpty || connected.contains(current) ? connected : connected + [current]
    }
}

struct HistoryPrivacySection: View {
    let model: SettingsModel
    let actions: SettingsActions

    var body: some View {
        Section("History") {
            Hinted(hint: "Save every result to history.log. With this off nothing new is written") {
                Toggle("Save history", isOn: model.binding("saveHistory", \.saveHistory))
            }
            Hinted(hint: "Delete history entries older than this many days. 0 = keep forever") {
                Stepper(value: model.binding("historyDays", \.historyDays), in: 0...3650) {
                    Text(model.settings.historyDays == 0 ? "Keep history: forever" : "Keep history: \(model.settings.historyDays) days")
                }
            }
            Hinted(hint: "How many recent dictations the Recent submenu shows. 0 hides it") {
                Stepper(value: model.binding("historyMenuItems", \.historyMenuItems), in: 0...50) {
                    Text("Recent menu items: \(model.settings.historyMenuItems)")
                }
            }
            Hinted(hint: "How long the audio of a failed transcription is kept so you can retry. 0 = delete it right away") {
                Stepper(value: model.binding("failedAudioHours", \.failedAudioHours), in: 0...720) {
                    Text("Keep failed audio: \(model.settings.failedAudioHours) h")
                }
            }
            HStack {
                Button("Open history", action: actions.openHistory)
                Button("Clear history…", action: actions.clearHistory)
            }
        }
        Section("Statistics") {
            Hinted(hint: "Record usage statistics on this Mac: numbers only, never what you dictated") {
                Toggle("Collect statistics", isOn: model.binding("collectStats", \.collectStats))
            }
            Hinted(hint: "Your typing speed, for “time saved” in Statistics (10–200)") {
                Stepper(value: model.binding("typingSpeedWpm", \.typingSpeedWpm), in: 10...200, step: 5) {
                    Text("Typing speed: \(model.settings.typingSpeedWpm) words per minute")
                }
            }
            Button("Clear statistics…", action: actions.clearStatistics)
        }
    }
}

/// Saves the style prompt after a short pause in typing, not on every keystroke.
private struct StylePromptEditor: View {
    let model: SettingsModel
    @State private var text: String?
    @State private var pending: Task<Void, Never>?

    var body: some View {
        TextEditor(text: Binding(get: { text ?? model.settings.stylePrompt }, set: { value in
            text = value
            pending?.cancel()
            pending = Task {
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled else { return }
                model.set("stylePrompt", value)
                text = nil
            }
        }))
        .font(.body)
        .frame(minHeight: 70)
        .onDisappear {
            if let text, pending != nil { model.set("stylePrompt", text) }
            pending?.cancel()
        }
    }
}
