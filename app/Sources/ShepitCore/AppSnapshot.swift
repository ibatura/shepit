import Foundation

/// What the app can be asked to do: from the menu, the window and the meeting hotkey.
public enum AppAction: Equatable, Sendable {
    case setMode(String)
    case setEngine(EngineChoice)
    case setLanguage(String)
    case addToDictionary
    case openWindow
    case openSettings
    case reloadConfig
    case reloadModels
    case openHistory
    case clearHistory
    case copyText(String)
    case grantAccessibility
    case grantMicrophone
    case startMeeting
    /// Start for the call the app has noticed (`CallOffer.current`): with its name, no dialog, as its offer does.
    case startCall
    case stopMeeting
    case openMeetingsFolder
    case quit
}

/// The app's state as the menu, its title and the window show it, gathered by the app (`AppHost.snapshot`).
public struct AppSnapshot: Sendable {
    public var state: ControllerState = .idle
    public var load: LoadState = .loaded
    public var settings: Settings = .defaults
    public var downloaded: [EngineChoice] = []
    public var configErrors: [String] = []
    public var hotkeyProblem: String?
    public var today = ""
    public var microphones: [String] = []
    public var accessibilityGranted = true
    public var microphoneDenied = false
    /// The transcript being recorded or finished; nil when none runs.
    public var meeting: LiveMeeting?
    /// A call that runs now and is not recorded.
    public var call: CallOffer.Current?
    /// The newest history entries, newest first: enough for Home and for Recent (`historyMenuItems`).
    public var history: [History.Entry] = []
    /// nil when a meeting can start; else what to download first.
    public var meetingMissing: String?

    public init() {}
}

/// The transcript being recorded, as the menu, Home and the Meetings section show it (Meetings design §7), from the session's memory.
public struct LiveMeeting: Equatable, Sendable {
    public var state: MeetingState
    /// Its name; nil when it has none.
    public var title: String?
    /// The app it was started for; nil when unknown.
    public var app: CallApp?
    /// Words recognized so far on both sides.
    public var words: Int
    /// nil while the call app's mute button can't be read.
    public var muted: Bool?
    /// The entries written so far, with their live labels; `line` is the entry's index. Empty unless the window shows them.
    public var entries: [MeetingNote.Entry]
    /// The note being written: Add notes… and Locate note… leave it alone until it is finished.
    public var note: String?

    public init(state: MeetingState, title: String? = nil, app: CallApp? = nil, words: Int = 0, muted: Bool? = nil,
                entries: [MeetingNote.Entry] = [], note: String? = nil) {
        self.state = state
        self.title = title
        self.app = app
        self.words = words
        self.muted = muted
        self.entries = entries
        self.note = note
    }
}
