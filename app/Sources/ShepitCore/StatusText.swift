import Foundation

extension AppSnapshot {
    /// The dictation status, first in the menu and on Home: "Ready — whisper.cpp large-v3-turbo".
    public var statusLine: String {
        switch state {
        case .recording: return "Recording… (Esc to cancel)"
        case .transcribing: return "Transcribing…"
        case .idle: break
        }
        let engine = settings.engine(for: .dictation).title
        switch load {
        case .loading: return "Loading \(engine)…"
        case .failed(let detail): return StatusText.shorten("Error: \(detail)")
        case .unloaded: return "Model unloaded — loads on next use"
        case .loaded: return "Ready — \(engine)"
        }
    }
}

extension EngineChoice {
    /// "whisper.cpp large-v3-turbo"; engines with one model show the name alone.
    public var title: String {
        switch engine {
        case .whispercpp: "whisper.cpp \(model)"
        case .whisperkit: "WhisperKit \(model)"
        case .parakeet: "Parakeet"
        case .apple: "Apple Speech"
        }
    }
}

/// Pieces of text the menu, Home and Settings share.
public enum StatusText {
    /// "90 seconds", "5 minutes", "1 hour".
    public static func seconds(_ seconds: Int) -> String {
        seconds > 0 && seconds % 3600 == 0 ? count(seconds / 3600, "hour")
            : seconds > 0 && seconds % 60 == 0 ? count(seconds / 60, "minute") : count(seconds, "second")
    }

    /// "6 hours", "1 day", "1 week".
    public static func hours(_ hours: Int) -> String {
        hours > 0 && hours % 168 == 0 ? count(hours / 168, "week") : hours > 0 && hours % 24 == 0 ? count(hours / 24, "day") : count(hours, "hour")
    }

    /// "30 days", "1 year".
    public static func days(_ days: Int) -> String {
        days > 0 && days % 365 == 0 ? count(days / 365, "year") : count(days, "day")
    }

    /// "1 second", "2 seconds".
    public static func count(_ number: Int, _ unit: String) -> String { number == 1 ? "1 \(unit)" : "\(number) \(unit)s" }

    static let maxLine = 90

    static func shorten(_ s: String, to max: Int = maxLine) -> String {
        s.count > max ? String(s.prefix(max - 2)) + "…" : s
    }

    /// "0:09", "12:34", "1:02:03".
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let (h, m, s) = (total / 3600, total / 60 % 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "2 phrases waiting"; nil when none wait.
    static func phrasesWaiting(_ count: Int) -> String? {
        count > 0 ? "\(count) phrase\(count == 1 ? "" : "s") waiting" : nil
    }
}
