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

/// Remote speaker labels after the call (spec §5.5) and renaming (§5.7). Only entry header lines
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
        var byTime: [String: [String?]] = [:]
        for entry in entries { byTime[entry.timestamp, default: []].append(entry.label) }
        var headers: [String: Int] = [:]
        for line in lines(note) { if let (_, timestamp) = header(line) { headers[timestamp, default: 0] += 1 } }
        var seen: [String: Int] = [:]
        return mapHeaders(note) { label, timestamp in
            let index = seen[timestamp, default: 0]
            seen[timestamp] = index + 1
            guard label == live, let labels = byTime[timestamp], labels.count == headers[timestamp], let new = labels[index] else { return nil }
            return new
        }
    }

    /// Distinct labels in order of first appearance, with the time and text of the first entry that has at
    /// least four words (else the first entry), so the user can find that speaker in the Teams transcript.
    public static func labels(in note: String) -> [(label: String, firstAt: String, firstText: String)] {
        let lines = lines(note).map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        var order: [String] = []
        var first: [String: (String, String)] = [:]
        var long: [String: (String, String)] = [:]
        for (i, line) in lines.enumerated() {
            guard let (label, timestamp) = header(line) else { continue }
            let text = i + 1 < lines.count && header(lines[i + 1]) == nil ? lines[i + 1] : ""
            if first[label] == nil {
                order.append(label)
                first[label] = (timestamp, text)
            }
            if long[label] == nil, text.split(separator: " ").count >= 4 { long[label] = (timestamp, text) }
        }
        return order.map { label in
            let (at, text) = long[label] ?? first[label]!
            return (label, at, text)
        }
    }

    /// Renames labels in header lines. Empty or unchanged names are skipped; two labels with one name merge.
    public static func rename(_ note: String, _ names: [String: String]) -> String {
        mapHeaders(note) { label, _ in
            // A name is one line: a newline in it would split the header.
            guard let name = names[label]?.split(whereSeparator: \.isWhitespace).joined(separator: " "), !name.isEmpty, name != label else { return nil }
            return name
        }
    }

    /// Rewrites header lines whose `change(label, timestamp)` returns a new label.
    private static func mapHeaders(_ note: String, _ change: (String, String) -> String?) -> String {
        lines(note).map { line in
            guard let (label, timestamp) = header(line), let new = change(label, timestamp) else { return line }
            return "[\(new)] \(timestamp)" + (line.hasSuffix("\r") ? "\r" : "")
        }.joined(separator: "\n")
    }

    /// Lines split on "\n" only; with CRLF endings each line keeps its "\r" (String.split would treat "\r\n" as one character).
    private static func lines(_ note: String) -> [String] {
        note.components(separatedBy: "\n")
    }

    private static func header(_ raw: String) -> (label: String, timestamp: String)? {
        let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
        guard let match = line.wholeMatch(of: /\[(.+)\] (\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})/) else { return nil }
        return (String(match.1), String(match.2))
    }
}
