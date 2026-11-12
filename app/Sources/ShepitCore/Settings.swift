import Foundation

public enum EngineID: String, CaseIterable, Sendable {
    case whisperkit
    case whispercpp
    case parakeet
    case apple
}

public struct EngineChoice: Equatable, Hashable, Sendable {
    public var engine: EngineID
    public var model: String

    public init(engine: EngineID, model: String) {
        self.engine = engine
        self.model = model
    }
}

public enum EngineTask: String, CaseIterable, Sendable {
    case dictation
    case preview
    case meetings
}

public struct Hotkey: Equatable, Sendable {
    public var mods: [String]
    public var key: String

    public init(mods: [String], key: String) {
        self.mods = mods
        self.key = key
    }
}

public struct OverlayStyle: Equatable, Sendable {
    public var position: String
    public var width: Int
    public var opacity: Double
    public var backgroundColor: String
    public var textColor: String
    public var fontSize: Int
    public var listeningText: String
    public var transcribingText: String
    public var doneText: String
    public var showTimer: Bool
    public var showMeter: Bool
    public var meterColor: String
    public var bars: Int
    public var doneSeconds: Double
    public var messageSeconds: Double

    public init(
        position: String,
        width: Int,
        opacity: Double,
        backgroundColor: String,
        textColor: String,
        fontSize: Int,
        listeningText: String,
        transcribingText: String,
        doneText: String,
        showTimer: Bool,
        showMeter: Bool,
        meterColor: String,
        bars: Int,
        doneSeconds: Double,
        messageSeconds: Double
    ) {
        self.position = position
        self.width = width
        self.opacity = opacity
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.fontSize = fontSize
        self.listeningText = listeningText
        self.transcribingText = transcribingText
        self.doneText = doneText
        self.showTimer = showTimer
        self.showMeter = showMeter
        self.meterColor = meterColor
        self.bars = bars
        self.doneSeconds = doneSeconds
        self.messageSeconds = messageSeconds
    }

    public static let defaults = OverlayStyle(
        position: "bottom",
        width: 560,
        opacity: 0.88,
        backgroundColor: "#141414",
        textColor: "#FFFFFF",
        fontSize: 14,
        listeningText: "Слухаю",
        transcribingText: "Розпізнаю…",
        doneText: "Готово",
        showTimer: true,
        showMeter: true,
        meterColor: "#FF4D4D",
        bars: 10,
        doneSeconds: 1.0,
        messageSeconds: 2.5
    )
}

public struct Settings: Equatable, Sendable {
    public var mode: String
    public var hotkey: Hotkey
    public var cancelKey: String
    public var model: String
    public var language: String
    public var stylePrompt: String
    public var refocusOriginalApp: Bool
    public var restoreClipboard: Bool
    public var sounds: Bool
    public var maxRecordingSeconds: Int
    public var serverPort: Int
    public var idleUnloadMinutes: Int
    public var overlay: Bool
    public var livePreview: Bool
    public var previewModel: String
    public var overlayStyle: OverlayStyle
    public var historyMenuItems: Int
    public var addWordHotkey: Hotkey
    public var microphone: String
    public var saveHistory: Bool
    public var historyDays: Int
    public var failedAudioHours: Int
    public var engines: [EngineTask: EngineChoice]
    public var launchAtLogin: Bool
    public var typingSpeedWpm: Int
    public var collectStats: Bool
    public var meetingsFolder: String
    public var meetingFileName: String
    public var meetingAskTitle: Bool
    public var meetingBlocksDictation: Bool
    public var meetingMyName: String
    public var meetingLanguage: String
    /// Offer a transcript when a call starts (call offer design §5.6).
    public var callOffer: Bool
    /// Seconds until the offer panel hides; 0 keeps it until a button is pressed.
    public var callOfferSeconds: Int
    public var callAutoStart: Bool
    public var callAutoStartSeconds: Int
    public var callAutoStopSeconds: Int
    /// Apps that get an offer: any of `Settings.callAppNames`.
    public var callApps: [String]

    public static let callAppNames = ["Teams", "Zoom", "Meet"]

    public init(
        mode: String,
        hotkey: Hotkey,
        cancelKey: String,
        model: String,
        language: String,
        stylePrompt: String,
        refocusOriginalApp: Bool,
        restoreClipboard: Bool,
        sounds: Bool,
        maxRecordingSeconds: Int,
        serverPort: Int,
        idleUnloadMinutes: Int,
        overlay: Bool,
        livePreview: Bool,
        previewModel: String,
        overlayStyle: OverlayStyle,
        historyMenuItems: Int,
        addWordHotkey: Hotkey,
        microphone: String,
        saveHistory: Bool,
        historyDays: Int,
        failedAudioHours: Int,
        engines: [EngineTask: EngineChoice],
        launchAtLogin: Bool,
        typingSpeedWpm: Int,
        collectStats: Bool,
        meetingsFolder: String = "~/.local/share/dictation/meetings",
        meetingFileName: String = "{date} {time} {title}",
        meetingAskTitle: Bool = true,
        meetingBlocksDictation: Bool = false,
        meetingMyName: String = "",
        meetingLanguage: String = "auto",
        callOffer: Bool = true,
        callOfferSeconds: Int = 15,
        callAutoStart: Bool = false,
        callAutoStartSeconds: Int = 5,
        callAutoStopSeconds: Int = 10,
        callApps: [String] = Settings.callAppNames
    ) {
        self.mode = mode
        self.hotkey = hotkey
        self.cancelKey = cancelKey
        self.model = model
        self.language = language
        self.stylePrompt = stylePrompt
        self.refocusOriginalApp = refocusOriginalApp
        self.restoreClipboard = restoreClipboard
        self.sounds = sounds
        self.maxRecordingSeconds = maxRecordingSeconds
        self.serverPort = serverPort
        self.idleUnloadMinutes = idleUnloadMinutes
        self.overlay = overlay
        self.livePreview = livePreview
        self.previewModel = previewModel
        self.overlayStyle = overlayStyle
        self.historyMenuItems = historyMenuItems
        self.addWordHotkey = addWordHotkey
        self.microphone = microphone
        self.saveHistory = saveHistory
        self.historyDays = historyDays
        self.failedAudioHours = failedAudioHours
        self.engines = engines
        self.launchAtLogin = launchAtLogin
        self.typingSpeedWpm = typingSpeedWpm
        self.collectStats = collectStats
        self.meetingsFolder = meetingsFolder
        self.meetingFileName = meetingFileName
        self.meetingAskTitle = meetingAskTitle
        self.meetingBlocksDictation = meetingBlocksDictation
        self.meetingMyName = meetingMyName
        self.meetingLanguage = meetingLanguage
        self.callOffer = callOffer
        self.callOfferSeconds = callOfferSeconds
        self.callAutoStart = callAutoStart
        self.callAutoStartSeconds = callAutoStartSeconds
        self.callAutoStopSeconds = callAutoStopSeconds
        self.callApps = callApps
    }

    /// `meetingsFolder` with a leading `~/` expanded.
    public func meetingsFolderURL(home: URL) -> URL {
        meetingsFolder.hasPrefix("~/")
            ? home.appending(path: String(meetingsFolder.dropFirst(2)), directoryHint: .isDirectory)
            : URL(fileURLWithPath: meetingsFolder, isDirectory: true)
    }

    /// Label for the microphone stream: `meetingMyName`, else the macOS account full name.
    public func myName(fullName: String = NSFullUserName()) -> String {
        let own = meetingMyName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !own.isEmpty { return own }
        let full = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        return full.isEmpty ? "Я" : full
    }

    public static let defaults = Settings(
        mode: "toggle",
        hotkey: Hotkey(mods: ["alt"], key: "space"),
        cancelKey: "escape",
        model: "large-v3",
        language: "uk",
        stylePrompt: "Сьогодні я відкрив pull request у GitHub, задеплоїв сервіс у Kubernetes і оновив README.",
        refocusOriginalApp: true,
        restoreClipboard: true,
        sounds: true,
        maxRecordingSeconds: 300,
        serverPort: 8178,
        idleUnloadMinutes: 0,
        overlay: true,
        livePreview: true,
        previewModel: "large-v3-turbo",
        overlayStyle: .defaults,
        historyMenuItems: 10,
        addWordHotkey: Hotkey(mods: ["ctrl", "alt"], key: "d"),
        microphone: "",
        saveHistory: true,
        historyDays: 0,
        failedAudioHours: 24,
        engines: [
            .dictation: EngineChoice(engine: .whispercpp, model: "large-v3-turbo"),
            .preview: EngineChoice(engine: .whispercpp, model: "large-v3-turbo"),
            .meetings: EngineChoice(engine: .whispercpp, model: "large-v3-turbo")
        ],
        launchAtLogin: true,
        typingSpeedWpm: 40,
        collectStats: true
    )
}
