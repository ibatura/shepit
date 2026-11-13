import Foundation

/// What the window's Home section shows (window shell design §5), as data.
public struct Home: Equatable, Sendable {
    public struct Warning: Equatable, Sendable {
        public var text: String
        /// nil: nothing to press.
        public var button: String?
        public var action: MenuAction?
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
        public var button: String?
        /// nil with a button: the button is off.
        public var action: MenuAction?
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
    public static func build(_ view: MenuView) -> Home {
        let microphone = view.settings.microphone
        return Home(status: MenuModel.statusLine(view), dictating: view.state != .idle,
             microphones: microphone.isEmpty || view.microphones.contains(microphone) ? view.microphones : view.microphones + [microphone],
             microphoneEnabled: view.state == .idle && !view.meeting.isActive, warnings: warnings(view), engines: engines(view), meeting: meeting(view), card: card(view),
             dictations: view.history.map { Home.Dictation(text: $0.text, when: History.when($0, today: view.today)) },
             noDictations: view.settings.saveHistory ? "No dictations yet" : "History is off (Settings → History and privacy)")
    }

    /// "whisper.cpp · large-v3"; engines with one model show the name alone.
    public static func pairTitle(_ choice: EngineChoice) -> String {
        switch choice.engine {
        case .whispercpp: "whisper.cpp · \(choice.model)"
        case .whisperkit: "WhisperKit · \(choice.model)"
        case .parakeet, .apple: MenuModel.engineTitle(choice)
        }
    }

    private static func warnings(_ view: MenuView) -> [Home.Warning] {
        var warnings = view.hotkeyProblem.map { [Home.Warning(text: $0)] } ?? []
        if !view.accessibilityGranted {
            warnings.append(Home.Warning(text: "Accessibility not granted (needed to paste)", button: "Allow…", action: .grantAccessibility))
        }
        if view.microphoneDenied {
            warnings.append(Home.Warning(text: "Microphone access denied", button: "Open System Settings", action: .grantMicrophone))
        }
        return warnings
    }

    private static func engines(_ view: MenuView) -> [Home.EngineRow] {
        let dictating = view.state != .idle
        let rows: [(EngineTask, String, String, Bool)] = [
            (.dictation, "Dictation", "The text that gets pasted", !dictating),
            (.preview, "Live draft", "The preview in the panel while you speak", !dictating),
            (.meetings, "Meetings", "Meeting transcripts", !view.meeting.isActive),
        ]
        return rows.map { task, title, hint, enabled in
            let current = view.settings.engines[task] ?? Settings.defaults.engines[task]!
            var choices = view.downloaded.map { Home.EngineRow.Choice(choice: $0, title: pairTitle($0)) }
            if !view.downloaded.contains(current) {
                choices.append(Home.EngineRow.Choice(choice: current, title: "\(pairTitle(current)) (not downloaded)"))
            }
            return Home.EngineRow(task: task, title: title, hint: hint, choices: choices, current: current, enabled: enabled)
        }
    }

    private static func card(_ view: MenuView) -> Home.Card? {
        let headline: String
        switch view.meeting {
        case .recording(let elapsed, _): headline = "Recording \(MenuModel.clock(elapsed))"
        case .finishing: headline = "Finishing"
        case .detectingSpeakers: headline = "Detecting speakers"
        case .idle, .done, .interrupted: return nil
        }
        return Home.Card(headline: headline, detail: [view.meetingTitle, view.meetingApp].compactMap { $0 }.joined(separator: " · "))
    }

    private static func meeting(_ view: MenuView) -> Home.MeetingRow {
        switch view.meeting {
        case .recording(let elapsed, let waiting):
            let parts = [view.meetingApp, MenuModel.clock(elapsed), waiting > 0 ? "\(waiting) phrase\(waiting == 1 ? "" : "s") waiting" : nil]
            return Home.MeetingRow(recording: true, title: view.meetingTitle ?? "Meeting transcript",
                                   hint: parts.compactMap { $0 }.joined(separator: " · "), button: "Stop", action: .stopMeeting)
        case .finishing(let left): return Home.MeetingRow(title: "Finishing the transcript (\(left) left)")
        case .detectingSpeakers: return Home.MeetingRow(title: "Detecting speakers…")
        case .idle, .done, .interrupted: break
        }
        if let missing = view.meetingMissing {
            return Home.MeetingRow(title: "No call right now", hint: "To start a transcript, \(missing)", button: "Start transcript")
        }
        if let call = view.call {
            return Home.MeetingRow(title: call.name ?? "\(call.app.rawValue) call", hint: call.name == nil ? nil : call.app.rawValue,
                                   button: "Start transcript", action: .startCall(title: call.name, app: call.app))
        }
        return Home.MeetingRow(title: "No call right now",
                               hint: view.settings.callOffer ? "Shepit offers a transcript when a call starts" : "Call offers are off",
                               button: "Start transcript", action: .startMeeting)
    }
}
