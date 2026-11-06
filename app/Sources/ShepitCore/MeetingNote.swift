import Foundation

/// Text of the meeting note (spec §5.4 "Content"): front matter, then `[label] YYYY-MM-DD HH:MM:SS` + one text line per entry.
public enum MeetingNote {
    public static func frontMatter(start: Date, title: String?, app: String?, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: start)
        var lines = ["---", "date: \(date(c))", #"time: "\#(two(c.hour)):\#(two(c.minute))""#]
        if let title, !title.isEmpty {
            let escaped = title.replacingOccurrences(of: #"\"#, with: #"\\"#).replacingOccurrences(of: #"""#, with: #"\""#)
            lines.append(#"title: "\#(escaped)""#)
        }
        if let app, !app.isEmpty { lines.append("app: \(app)") }
        lines += ["tags: [transcript]", "---"]
        return lines.joined(separator: "\n") + "\n"
    }

    public static func entry(label: String, at time: Date, text: String, calendar: Calendar = .current) -> String {
        "[\(label)] \(timestamp(time, calendar: calendar))\n\(escapeLeadingMarker(oneLine(text)))\n"
    }

    /// `YYYY-MM-DD HH:MM:SS` in local time, as in entry headers.
    /// Sounds and Whisper's inventions on near-silence: an entry made only of these is left out of the note
    /// (the Teams call of 2026-11-04 had 25 "Mm-hmm." and a few "you").
    static let fillers: Set<String> = ["mm", "mmm", "mm-hmm", "mhm", "hmm", "hm", "uh", "uh-huh", "um", "ah", "oh", "you",
                                       "мгм", "угу", "ем", "еее", "ммм", "хм"]

    public static func isFiller(_ text: String) -> Bool {
        let words = text.lowercased().split { !$0.isLetter && $0 != "-" }.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "-")) }
            .filter { !$0.isEmpty }
        return !words.isEmpty && words.allSatisfy(fillers.contains)
    }

    public static func timestamp(_ time: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: time)
        return "\(date(c)) \(clock(c))"
    }

    /// The note without its front matter, for Copy (§5.7).
    public static func stripFrontMatter(_ note: String) -> String {
        guard note.hasPrefix("---\n"), let close = note.range(of: "\n---\n", range: note.index(note.startIndex, offsetBy: 3)..<note.endIndex) else {
            return note
        }
        return String(note[close.upperBound...])
    }

    public static func interruptedLine(at time: Date, calendar: Calendar = .current) -> String {
        "⚠ Запис перервано о \(clock(calendar.dateComponents([.hour, .minute, .second], from: time)))\n"
    }

    public static func stoppedLine(_ stream: MeetingStream, at time: Date, calendar: Calendar = .current) -> String {
        let what = stream == .mine ? "Мікрофон перестав записувати" : "Звук дзвінка перестав записуватися"
        return "⚠ \(what) о \(clock(calendar.dateComponents([.hour, .minute, .second], from: time)))\n"
    }

    private static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// A body line must not read as Markdown structure or as an entry header (§10: escaped with a backslash).
    private static func escapeLeadingMarker(_ line: String) -> String {
        if let first = line.first, "#->+*[|".contains(first) { return "\\" + line }
        if let match = line.prefixMatch(of: /(\d+)([.)])(\s|$)/) {
            return match.1 + "\\" + line.dropFirst(match.1.count)
        }
        return line
    }

    private static func two(_ value: Int?) -> String { String(format: "%02d", value ?? 0) }
    private static func date(_ c: DateComponents) -> String { "\(String(format: "%04d", c.year ?? 0))-\(two(c.month))-\(two(c.day))" }
    private static func clock(_ c: DateComponents) -> String { "\(two(c.hour)):\(two(c.minute)):\(two(c.second))" }
}

/// Appends to the meeting note as entries arrive. A note that disappeared mid-call is recreated
/// at the same path with the same front matter (§6).
public final class NoteWriter: @unchecked Sendable {
    public let file: URL
    private let frontMatter: String

    public init(file: URL, frontMatter: String) {
        self.file = file
        self.frontMatter = frontMatter
    }

    public func create() throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(frontMatter.utf8).write(to: file)
    }

    public func append(_ text: String) throws {
        guard FileManager.default.fileExists(atPath: file.path) else {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data((frontMatter + text).utf8).write(to: file)
            return
        }
        let handle = try FileHandle(forUpdating: file)
        defer { try? handle.close() }
        var data = Data(text.utf8)
        let end = try handle.seekToEnd()
        if end > 0 {
            try handle.seek(toOffset: end - 1)
            if try handle.read(upToCount: 1) != Data("\n".utf8) { data.insert(contentsOf: Data("\n".utf8), at: 0) }
        }
        try handle.write(contentsOf: data)
    }
}
