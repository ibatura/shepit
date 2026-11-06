import Foundation

public enum Language: String, Sendable {
    case uk
    case en
    case auto
}

public struct TranscriptionRequest: Sendable {
    public var samples: [Float]
    public var language: Language
    public var prompt: String
    public var wantSegments: Bool
    /// The prompt when the speech is English: the style sentence is Ukrainian and makes Whisper write English
    /// speech in Ukrainian (Task 11), so this one is the dictionary terms only. nil = `prompt`.
    public var englishPrompt: String?
    /// With language auto: "en" when this stream has been English lately (`LanguageLeaning`), so unsure
    /// pieces are taken as English. nil = unsure pieces are Ukrainian.
    public var leaning: String?

    public init(samples: [Float], language: Language, prompt: String, wantSegments: Bool, englishPrompt: String? = nil) {
        self.samples = samples
        self.language = language
        self.prompt = prompt
        self.wantSegments = wantSegments
        self.englishPrompt = englishPrompt
    }

    /// The prompt for speech in `language` ("uk" or "en").
    public func prompt(for language: String) -> String {
        language == "en" ? englishPrompt ?? prompt : prompt
    }
}

public struct Segment: Equatable, Sendable {
    public var text: String
    public var start: Double
    public var end: Double

    public init(text: String, start: Double, end: Double) {
        self.text = text
        self.start = start
        self.end = end
    }
}

public struct Transcript: Equatable, Sendable {
    public var text: String
    public var segments: [Segment]
    public var detectedLanguage: String?

    public init(text: String, segments: [Segment], detectedLanguage: String?) {
        self.text = text
        self.segments = segments
        self.detectedLanguage = detectedLanguage
    }
}

public struct EngineCapabilities: Sendable {
    public var supportsPrompt: Bool
    public var forcibleLanguages: Set<Language>
    public var detectsLanguage: Bool
    public var givesSegmentTimes: Bool

    public init(supportsPrompt: Bool, forcibleLanguages: Set<Language>, detectsLanguage: Bool, givesSegmentTimes: Bool) {
        self.supportsPrompt = supportsPrompt
        self.forcibleLanguages = forcibleLanguages
        self.detectsLanguage = detectsLanguage
        self.givesSegmentTimes = givesSegmentTimes
    }

    public func check(_ language: Language) -> EngineError? {
        switch language {
        case .auto:
            detectsLanguage ? nil : .languageNotSupported(language)
        case .uk, .en:
            forcibleLanguages.contains(language) ? nil : .languageNotSupported(language)
        }
    }
}

public enum EngineError: Error, Equatable {
    case modelMissing(String)
    case loadFailed(String)
    case languageNotSupported(Language)
    case recognitionFailed(String)
    case unavailableOnThisMac(String)
}

public protocol SpeechEngine: Actor {
    var choice: EngineChoice { get }
    var capabilities: EngineCapabilities { get async }
    func load() async throws
    func unload() async
    var isLoaded: Bool { get }
    func transcribe(_ request: TranscriptionRequest) async throws -> Transcript
}
