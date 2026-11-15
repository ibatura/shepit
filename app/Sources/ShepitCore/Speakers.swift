/// One diarizer turn on the call stream, in seconds from the stream start.
public struct SpeakerTurn: Equatable, Sendable {
    public var speaker: String
    public var start: Double
    public var end: Double

    public init(speaker: String, start: Double, end: Double) {
        self.speaker = speaker
        self.start = start
        self.end = end
    }
}

/// Remote speaker labels after the call (spec §5.5) and changes from the window (Meetings design §8). Only entry header lines
/// (`[label] YYYY-MM-DD HH:MM:SS`) are ever changed; everything else in the note stays as the user left it.
public enum Speakers {
    public static let nearestWithin = 2.0

    /// `Person N` for each call entry (offsets in seconds, in note order), numbered by first appearance; nil = no speaker found.
    public static func assign(_ entries: [Range<Double>], turns: [SpeakerTurn]) -> [String?] {
        var numbers: [String: Int] = [:]
        return entries.map { entry in
            guard let speaker = speaker(for: entry, turns: turns) else { return nil }
            if numbers[speaker] == nil { numbers[speaker] = numbers.count + 1 }
            return "Person \(numbers[speaker]!)"
        }
    }

    private static func speaker(for entry: Range<Double>, turns: [SpeakerTurn]) -> String? {
        let ordered = turns.sorted { $0.start < $1.start }
        // Overlap summed per speaker: diarizers often split one speaker's speech into short turns.
        var overlap: [String: Double] = [:]
        var order: [String] = []
        for t in ordered {
            let o = min(entry.upperBound, t.end) - max(entry.lowerBound, t.start)
            guard o > 0 else { continue }
            if overlap[t.speaker] == nil { order.append(t.speaker) }
            overlap[t.speaker, default: 0] += o
        }
        if let best = order.max(by: { overlap[$0]! < overlap[$1]! }) {
            return order.first { overlap[$0] == overlap[best] } // the earliest speaker on a tie
        }
        func distance(_ t: SpeakerTurn) -> Double { max(t.start - entry.upperBound, entry.lowerBound - t.end, 0) }
        guard let nearest = ordered.min(by: { distance($0) < distance($1) }), distance(nearest) <= nearestWithin else { return nil }
        return nearest.speaker
    }

    /// Sets new labels on live headers. `entries` are all entries written to the note, in order, with the
    /// new label for call entries (nil = leave it). The k-th header with a timestamp, whatever its label, is the
    /// k-th entry with that timestamp; it changes only if it still reads exactly `[live] <timestamp>`.
    /// If the user deleted or added headers at a timestamp, the order can't be trusted and that second keeps its live labels.
    public static func relabel(_ note: String, live: String, entries: [(timestamp: String, label: String?)]) -> String {
        let written = Dictionary(uniqueKeysWithValues: zip(MeetingNote.places(entries.map(\.timestamp)), entries.map(\.label)))
        let headers = MeetingNote.parse(note).entries
        var labels: [Int: String] = [:]
        for (header, new) in zip(headers, MeetingNote.pair(headers, written)) where header.label == live {
            if let new = new ?? nil { labels[header.line] = new }
        }
        return setLabels(note, labels)
    }

    /// Sets the labels of the header lines at the given line numbers (as `MeetingNote.parse` counts them).
    /// Lines that are not headers, empty labels and every other line stay byte for byte.
    public static func setLabels(_ note: String, _ labels: [Int: String]) -> String {
        var lines = lines(note)
        for (index, label) in labels where lines.indices.contains(index) {
            let name = MeetingNote.oneLine(label)
            guard !name.isEmpty, let (_, timestamp) = header(lines[index]) else { continue }
            lines[index] = "[\(name)] \(timestamp)" + (lines[index].hasSuffix("\r") ? "\r" : "")
        }
        return lines.joined(separator: "\n")
    }

    /// Lines split on "\n" only; with CRLF endings each line keeps its "\r" (String.split would treat "\r\n" as one character).
    private static func lines(_ note: String) -> [String] {
        note.components(separatedBy: "\n")
    }

    static func header(_ raw: String) -> (label: String, timestamp: String)? {
        let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
        guard let match = line.wholeMatch(of: /\[(.+)\] (\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})/) else { return nil }
        return (String(match.1), String(match.2))
    }
}
