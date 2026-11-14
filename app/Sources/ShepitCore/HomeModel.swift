import Foundation

/// What the window's Home section shows (window shell design §5), as data.
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

    public struct EngineRow: Equatable, Sendable, Identifiable {
        public struct Choice: Equatable, Sendable {
            public var choice: EngineChoice
            public var title: String
        }

        public var task: EngineTask
        public var title, hint: String
        /// The downloaded pairs, and the configured one when it is not downloaded.
        public var choices: [Choice]
        public var current: EngineChoice
        /// Off while this job runs.
        public var enabled: Bool
        public var id: EngineTask { task }
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
        public var text, when: String
    }

    public var status: String
    /// A dictation runs: Mode, Language and Reload model wait for it, as in the menu.
    public var dictating: Bool
    /// The connected microphones, and the configured one when it is not connected.
    public var microphones: [String]
    /// Off while a dictation or a transcript uses the microphone.
    public var microphoneEnabled: Bool
    public var warnings: [Warning]
    public var engines: [EngineRow]
    public var meeting: MeetingRow
    public var card: Card?
    public var dictations: [Dictation]
    /// Shown in place of the list when it is empty.
    public var noDictations: String
}

public enum HomeModel {
    /// How many of the last dictations Home lists.
    public static let dictationCount = 10

    public static func build(_ view: AppSnapshot) -> Home {
        Home(status: view.statusLine, dictating: view.state != .idle,
             microphones: Microphones.choices(connected: view.microphones, configured: view.settings.microphone),
             microphoneEnabled: view.state == .idle && !view.meeting.isActive, warnings: warnings(view), engines: engines(view), meeting: meeting(view), card: card(view),
             dictations: view.history.prefix(dictationCount).map { Home.Dictation(text: $0.text, when: History.when($0, today: view.today)) },
             noDictations: view.settings.saveHistory ? "No dictations yet" : "History is off (Settings → History and privacy)")
    }

    private static func warnings(_ view: AppSnapshot) -> [Home.Warning] {
        var warnings = view.hotkeyProblem.map { [Home.Warning(text: $0)] } ?? []
        if !view.accessibilityGranted {
            warnings.append(Home.Warning(text: "Accessibility not granted (needed to paste)", button: Home.Button(title: "Allow…", action: .grantAccessibility)))
        }
        if view.microphoneDenied {
            warnings.append(Home.Warning(text: "Microphone access denied", button: Home.Button(title: "Open System Settings", action: .grantMicrophone)))
        }
        return warnings
    }

    private static func engines(_ view: AppSnapshot) -> [Home.EngineRow] {
        let dictating = view.state != .idle
        let rows: [(EngineTask, String, String, Bool)] = [
            (.dictation, "Dictation", "The text that gets pasted", !dictating),
            (.preview, "Live draft", "The preview in the panel while you speak", !dictating),
            (.meetings, "Meetings", "Meeting transcripts", !view.meeting.isActive),
        ]
        return rows.map { task, title, hint, enabled in
            let current = view.settings.engine(for: task)
            var choices = view.downloaded.map { Home.EngineRow.Choice(choice: $0, title: $0.pairTitle) }
            if !view.downloaded.contains(current) {
                choices.append(Home.EngineRow.Choice(choice: current, title: "\(current.pairTitle) (not downloaded)"))
            }
            return Home.EngineRow(task: task, title: title, hint: hint, choices: choices, current: current, enabled: enabled)
        }
    }

    private static func card(_ view: AppSnapshot) -> Home.Card? {
        let headline: String
        switch view.meeting {
        case .recording(let elapsed, _): headline = "Recording \(StatusText.clock(elapsed))"
        case .finishing: headline = "Finishing"
        case .detectingSpeakers: headline = "Detecting speakers"
        case .idle, .done, .interrupted: return nil
        }
        return Home.Card(headline: headline, detail: [view.meetingTitle, view.meetingApp].compactMap { $0 }.joined(separator: " · "))
    }

    private static func meeting(_ view: AppSnapshot) -> Home.MeetingRow {
        switch view.meeting {
        case .recording(let elapsed, let waiting):
            let parts = [view.meetingApp, StatusText.clock(elapsed), StatusText.phrasesWaiting(waiting)]
            return Home.MeetingRow(recording: true, title: view.meetingTitle ?? "Meeting transcript",
                                   hint: parts.compactMap { $0 }.joined(separator: " · "), button: Home.Button(title: "Stop", action: .stopMeeting))
        case .finishing(let left): return Home.MeetingRow(title: "Finishing the transcript (\(left) left)")
        case .detectingSpeakers: return Home.MeetingRow(title: "Detecting speakers…")
        case .idle, .done, .interrupted: break
        }
        // Without the model Start is off, but the row still names the call that runs (spec §10).
        let missing = view.meetingMissing.map { "To start a transcript, \($0)" }
        if let call = view.call {
            let hint = [call.name == nil ? nil : call.app.rawValue, missing].compactMap { $0 }.joined(separator: " · ")
            return Home.MeetingRow(title: call.name ?? "\(call.app.rawValue) call", hint: hint.isEmpty ? nil : hint,
                                   button: Home.Button(title: "Start transcript", action: missing == nil ? .startCall : nil))
        }
        return Home.MeetingRow(title: "No call right now",
                               hint: missing ?? (view.settings.callOffer ? "Shepit offers a transcript when a call starts" : "Call offers are off"),
                               button: Home.Button(title: "Start transcript", action: missing == nil ? .startMeeting : nil))
    }
}
