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

/// Pieces of text the menu and Home share.
public enum StatusText {
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
