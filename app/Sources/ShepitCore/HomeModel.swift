import Foundation

/// What the window's Home section shows (window shell design §5, settings review design §5), as data: a status page.
public struct Home: Equatable, Sendable {
    public struct Button: Equatable, Sendable {
        public var title: String
        /// nil: the button is off.
        public var action: AppAction?
    }

    public struct Warning: Equatable, Sendable {
        public var text: String
        /// nil: nothing to press.
        public var button: Button?
    }

    public struct MeetingRow: Equatable, Sendable {
        /// A transcript is being recorded: the red dot and a red button.
        public var recording = false
        public var title: String
        public var hint: String?
        public var button: Button?
    }

    /// The sidebar's card while a transcript runs: "Recording 12:34" over "Weekly sync · Teams".
    public struct Card: Equatable, Sendable {
        public var headline, detail: String
    }

    public struct Dictation: Equatable, Sendable {
        /// "14:02 · Slack".
        public var text, detail: String
    }

    /// A listed meeting; a click opens it in Meetings.
    public struct Meeting: Equatable, Sendable, Identifiable {
        public var id: Int
        /// "Teams · 45 min".
        public var title, detail: String
    }

    public var status: String
    /// Needs attention: shown only while something is wrong.
    public var warnings: [Warning]
    public var meeting: MeetingRow
    public var card: Card?
    public var dictations: [Dictation]
    /// Shown in place of the list when it is empty.
    public var noDictations: String
    /// Empty: no Recent meetings at all.
    public var meetings: [Meeting]
}

public enum HomeModel {
    /// How many of the last dictations, and of the last meetings, Home lists.
    public static let dictationCount = 10

    public static func build(_ view: AppSnapshot) -> Home {
        Home(status: view.statusLine, warnings: warnings(view), meeting: meeting(view), card: card(view),
             dictations: view.history.prefix(dictationCount).map {
                 Home.Dictation(text: $0.text, detail: [DictationPage.when($0.time, now: view.now), $0.appName].compactMap { $0 }.joined(separator: " · "))
             },
             noDictations: view.settings.saveHistory ? "No dictations yet" : "History is off (Settings → History and privacy)",
             meetings: view.recentMeetings.prefix(dictationCount).map {
                 Home.Meeting(id: $0.id, title: MeetingPage.title($0.title, $0.app),
                              detail: [$0.app.map(CallApp.title(of:)), MeetingPage.minutes($0.duration)].compactMap { $0 }.joined(separator: " · "))
             })
    }

    private static func warnings(_ view: AppSnapshot) -> [Home.Warning] {
        var warnings = view.hotkeyProblem.map { [Home.Warning(text: $0)] } ?? []
        if !view.accessibilityGranted {
            warnings.append(Home.Warning(text: "Accessibility not granted (needed to paste)", button: Home.Button(title: "Allow…", action: .grantAccessibility)))
        }
        if view.microphoneDenied {
            warnings.append(Home.Warning(text: "Microphone access denied", button: Home.Button(title: "Open System Settings", action: .grantMicrophone)))
        }
        let missing = missingModels(view)
        if !missing.models.isEmpty {
            warnings.append(Home.Warning(text: "Not downloaded: \(missing.models.joined(separator: ", "))",
                                         button: Home.Button(title: "Download…", action: .openModels)))
        }
        if !missing.apple.isEmpty {
            warnings.append(Home.Warning(text: "Apple Speech needs macOS 26 (\(missing.apple.joined(separator: ", ")))",
                                         button: Home.Button(title: "Choose another…", action: .openModels)))
        }
        return warnings
    }

    /// Each missing model once with its jobs ("whisper.cpp large-v3 (Dictation, Live draft)", "Silero VAD (Voice detection)"),
    /// and the jobs given to Apple Speech on a macOS without it, which has nothing to download. The live draft's model
    /// counts only while the live draft is on.
    private static func missingModels(_ view: AppSnapshot) -> (models: [String], apple: [String]) {
        var engines: [(EngineChoice, [String])] = []
        var apple: [String] = []
        for task in EngineTask.allCases where task != .preview || view.settings.livePreview {
            let choice = view.settings.engine(for: task)
            guard !view.downloaded.contains(choice) else { continue }
            if choice.engine == .apple {
                apple.append(task.title)
            } else if let at = engines.firstIndex(where: { $0.0 == choice }) {
                engines[at].1.append(task.title)
            } else {
                engines.append((choice, [task.title]))
            }
        }
        let models = engines.map { "\($0.0.title) (\($0.1.joined(separator: ", ")))" }
            + MeetingModel.allCases.filter { !view.meetingModels.contains($0) }.map { "\($0.title) (\($0.job))" }
        return (models, apple)
    }

    /// What happens when a call starts, by the apps' choices; rules by name can change it for some calls.
    private static func callHint(_ settings: Settings) -> String {
        let hint = switch Set(CallApp.allCases.map(settings.callMode)).subtracting([.off]) {
        case []: "Call offers are off"
        case [.auto]: "Shepit starts a transcript when a call starts"
        default: "Shepit offers a transcript when a call starts"
        }
        let rules = CallApp.allCases.contains { settings.callMode(for: $0) != .off && settings.hasCallRules(for: $0) }
        return rules ? hint + ", or as a rule by its name says" : hint
    }

    private static func card(_ view: AppSnapshot) -> Home.Card? {
        let headline: String
        switch view.meeting?.state ?? .idle {
        case .recording(let elapsed, _): headline = "Recording \(StatusText.clock(elapsed))"
        case .finishing: headline = "Finishing"
        case .detectingSpeakers: headline = "Detecting speakers"
        case .idle, .done, .interrupted: return nil
        }
        return Home.Card(headline: headline, detail: [view.meeting?.title, view.meeting?.app?.title].compactMap { $0 }.joined(separator: " · "))
    }

    private static func meeting(_ view: AppSnapshot) -> Home.MeetingRow {
        switch view.meeting?.state ?? .idle {
        case .recording(let elapsed, let waiting):
            let parts = [view.meeting?.app?.title, StatusText.clock(elapsed), StatusText.phrasesWaiting(waiting)]
            return Home.MeetingRow(recording: true, title: view.meeting?.title ?? "Meeting transcript",
                                   hint: parts.compactMap { $0 }.joined(separator: " · "), button: Home.Button(title: "Stop", action: .stopMeeting))
        case .finishing(let left): return Home.MeetingRow(title: "Finishing the transcript (\(left) left)")
        case .detectingSpeakers: return Home.MeetingRow(title: "Detecting speakers…")
        case .idle, .done, .interrupted: break
        }
        // Without the model Start is off, but the row still names the call that runs (spec §10).
        let missing = view.meetingMissing.map { "To start a transcript, \($0)" }
        if let call = view.call {
            let hint = [call.name == nil ? nil : call.app.title, missing].compactMap { $0 }.joined(separator: " · ")
            return Home.MeetingRow(title: call.name ?? "\(call.app.title) call", hint: hint.isEmpty ? nil : hint,
                                   button: Home.Button(title: "Start transcript", action: missing == nil ? .startCall : nil))
        }
        return Home.MeetingRow(title: "No call right now",
                               hint: missing ?? callHint(view.settings),
                               button: Home.Button(title: "Start transcript", action: missing == nil ? .startMeeting : nil))
    }
}
