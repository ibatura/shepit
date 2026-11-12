import AppKit
import SwiftUI
import ShepitCore

/// What the Settings window needs from the app besides the settings themselves.
@MainActor
struct SettingsActions {
    var microphones: () -> [String]
    var hotkeyProblem: () -> String?
    var openSettingsFile: () -> Void
    var openDataFolder: () -> Void
    var openHistory: () -> Void
    var openMeetingsFolder: () -> Void
    var clearHistory: () -> Void
    var clearStatistics: () -> Void
    var setLaunchAtLogin: (Bool) -> String?
    /// The shortcut recorder turns the global hotkeys off while it listens, and back on after.
    var suspendHotkeys: () -> Void
    var resumeHotkeys: () -> Void
    /// Shows the panel with sample text in the current style.
    var previewOverlay: () -> Void
    /// Stored dictation attempts in a period (all of them for nil).
    var statistics: (DateInterval?) -> [DictationRow]
    /// Stored meetings that started in a period (all of them for nil).
    var meetingStatistics: (DateInterval?) -> [MeetingRecord]
    /// Why this engine can't do the configured language, or nil when it can.
    var languageNote: (EngineChoice, String) async -> String?
    var downloads: ModelDownloads
}

/// The Settings window (`04-settings.md` §3): a sidebar of sections; every control saves at once.
@MainActor
final class SettingsWindow {
    private let model: SettingsModel
    private let actions: SettingsActions
    private var window: NSWindow?

    init(model: SettingsModel, actions: SettingsActions) {
        self.model = model
        self.actions = actions
    }

    func show(_ section: SettingsModel.Section? = nil) {
        let window = self.window ?? makeWindow()
        self.window = window
        if let section {
            let frame = window.frame // swapping the content must not shrink the window
            window.contentViewController = hosting(section)
            window.setFrame(frame, display: false)
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Only a minimum size comes from SwiftUI; otherwise the window would shrink to the content's ideal size.
    private func hosting(_ section: SettingsModel.Section) -> NSHostingController<SettingsView> {
        let controller = NSHostingController(rootView: SettingsView(model: model, actions: actions, section: section))
        controller.sizingOptions = [.minSize]
        return controller
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: hosting(.general))
        window.title = "Shepit Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.setContentSize(NSSize(width: 900, height: 700))
        window.setFrameAutosaveName("ShepitSettings") // remembers the size and place the user chose
        window.isReleasedWhenClosed = false
        window.center()
        // A shortcut being recorded when the window closes would leave the global hotkeys off.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [actions] _ in
            MainActor.assumeIsolated { actions.resumeHotkeys() }
        }
        return window
    }
}

struct SettingsView: View {
    let model: SettingsModel
    let actions: SettingsActions
    @State private var section: SettingsModel.Section?

    init(model: SettingsModel, actions: SettingsActions, section: SettingsModel.Section = .general) {
        self.model = model
        self.actions = actions
        _section = State(initialValue: section)
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsModel.Section.allCases, selection: $section) { section in
                Label(section.rawValue, systemImage: section.symbol).tag(section)
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                ProblemBanner(model: model, openFile: actions.openSettingsFile)
                Form {
                    switch section ?? .general {
                    case .general: GeneralSection(model: model, actions: actions)
                    case .hotkeys: HotkeysSection(model: model, actions: actions)
                    case .dictation: DictationSection(model: model, actions: actions)
                    case .meetings: MeetingsSection(model: model, actions: actions)
                    case .calls: CallsSection(model: model)
                    case .engines: EnginesSection(model: model, actions: actions)
                    case .overlay: OverlaySection(model: model, actions: actions)
                    case .dictionary: DictionarySection(model: model)
                    case .historyPrivacy: HistoryPrivacySection(model: model, actions: actions)
                    case .statistics: StatisticsSection(model: model, actions: actions, section: $section)
                    }
                }
                .formStyle(.grouped)
                .disabled(section == .dictionary ? model.dictionaryIsReadOnly : section != .statistics && model.isReadOnly)
            }
            .navigationTitle(section?.rawValue ?? "")
        }
    }
}

/// settings.json errors (controls are read-only until the file is fixed) and refused writes.
private struct ProblemBanner: View {
    let model: SettingsModel
    let openFile: () -> Void

    var body: some View {
        let lines = model.errors + model.dictionaryErrors + (model.lastError.map { [$0] } ?? [])
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(lines, id: \.self) { Text("⚠ \($0)") }
                if model.isReadOnly || model.dictionaryIsReadOnly {
                    HStack {
                        Text("Fix the file to change these settings here.")
                        Button("Open settings file", action: openFile)
                    }
                }
            }
            .font(.callout)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.15))
        }
    }
}

/// A control with the README's one-line hint under it.
struct Hinted<Content: View>: View {
    let hint: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            content
            Text(hint).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
