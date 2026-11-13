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
    /// Start for a call the app has noticed: with its name, no dialog.
    case startCall(title: String?, app: CallApp)
    case stopMeeting
    case copyLastMeeting
    case openMeetingsFolder
    case renameSpeakers
    case renameSpeakersInNote
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
    public var meeting: MeetingState = .idle
    /// The running transcript's name; nil when it has none.
    public var meetingTitle: String?
    /// The app the running transcript was started for ("Teams"); nil when unknown.
    public var meetingApp: String?
    /// A call that runs now and is not recorded.
    public var call: CallOffer.Current?
    /// The newest history entries, newest first: enough for Home and for Recent (`historyMenuItems`).
    public var history: [History.Entry] = []
    /// nil when a meeting can start; else what to download first.
    public var meetingMissing: String?

    public init() {}
}
