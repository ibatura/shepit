import Foundation

/// Who spoke when in a transcript Teams or Zoom saved of a call (import names design §4). Only each cue's times and
/// speaker are kept: the text is dropped as it is read.
public enum SpeakerTranscript {
    public struct Cue: Equatable, Sendable {
        /// Seconds from the file's start.
        public var start: TimeInterval
        public var end: TimeInterval
        public var speaker: String
    }

    public enum Problem: LocalizedError, Equatable {
        case notWebVTT, noSpeakers

        public var errorDescription: String? {
            switch self {
            case .notWebVTT: "This isn't a WebVTT transcript."
            case .noSpeakers: "This transcript has no speaker names."
            }
        }
    }

    /// The cues that name a speaker: Teams' `<v Olena K.>text`, Zoom's `Olena K.: text`.
    public static func cues(_ text: String) throws -> [Cue] {
        // "\r\n" is one Character, and a newline.
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        guard let first = lines.first, first.trimmingPrefix("\u{FEFF}").hasPrefix("WEBVTT") else { throw Problem.notWebVTT }
        var cues: [Cue] = [], timings = 0
        for (index, line) in lines.enumerated() {
            guard let timing = line.firstMatch(of: /^\s*([\d:.]+)\s+-->\s+([\d:.]+)/),
                  let start = seconds(timing.1), let end = seconds(timing.2) else { continue }
            timings += 1
            guard index + 1 < lines.count, let speaker = speaker(lines[index + 1]) else { continue }
            cues.append(Cue(start: start, end: end, speaker: speaker))
        }
        // Zoom's captions file has no names, yet a few of its lines have a colon in the text.
        guard !cues.isEmpty, cues.count * 2 >= timings else { throw Problem.noSpeakers }
        return cues
    }

    /// `01:02:03.450` or `02:03.450`.
    private static func seconds(_ text: Substring) -> TimeInterval? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false).map { Double($0) }
        guard (2...3).contains(parts.count), !parts.contains(nil) else { return nil }
        return parts.reduce(0) { $0 * 60 + $1! }
    }

    /// The speaker a cue's first line of text names, trimmed and as written; nil when it names none.
    private static func speaker(_ line: String) -> String? {
        let name = if let voice = line.firstMatch(of: /^<v\s+([^>]+)>/) { String(voice.1) }
            else if let colon = line.range(of: ": ") { String(line[..<colon.lowerBound]) }
            else { "" }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
