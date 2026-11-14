import Foundation

/// Text of the meeting note (spec §5.4 "Content"): front matter, then `[label] YYYY-MM-DD HH:MM:SS` + one text line per entry.
public enum MeetingNote {
    /// The label of the call side until speakers are told apart (spec §5.4).
    public static let callLabel = "Співрозмовники"

    public static func frontMatter(start: Date, title: String?, app: String?, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: start)
        var lines = ["---", "date: \(date(c))", #"time: "\#(two(c.hour)):\#(two(c.minute))""#]
        if let title, !title.isEmpty { lines.append("title: \(quoted(title))") }
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

    /// A YAML double-quoted string.
    private static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: #"\"#, with: #"\\"#).replacingOccurrences(of: #"""#, with: #"\""#) + "\""
    }

    // MARK: Reading a note (Meetings design §4, §6)

    public struct Entry: Equatable, Sendable {
        /// nil: a ⚠ line of its own (a capture stopped, an interruption).
        public var label: String?
        public var timestamp: String
        /// The lines up to the next header, without Shepit's escapes.
        public var text: String
        /// The line number of its header (or of the ⚠ line), counting lines split on "\n" from 0.
        public var line: Int

        public init(label: String?, timestamp: String, text: String, line: Int) {
            self.label = label
            self.timestamp = timestamp
            self.text = text
            self.line = line
        }
    }

    public struct Parsed: Equatable, Sendable {
        /// From the front matter's `date` and `time`.
        public var start: Date?
        public var title: String?
        public var app: String?
        public var entries: [Entry]
    }

    public static func parse(_ note: String, calendar: Calendar = .current) -> Parsed {
        let lines = note.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        var fields: [String: String] = [:]
        var body = 0
        if lines.first == "---", let close = lines.dropFirst().firstIndex(of: "---") {
            for line in lines[1..<close] {
                guard let colon = line.firstIndex(of: ":") else { continue }
                fields[String(line[..<colon])] = unquoted(line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces))
            }
            body = close + 1
        }
        var entries: [Entry] = []
        for (i, line) in lines.enumerated().dropFirst(body) {
            if let (label, timestamp) = Speakers.header(line) {
                entries.append(Entry(label: label, timestamp: timestamp, text: "", line: i))
            } else if line.hasPrefix("⚠"), line != MeetingQueue.failedText || entries.last.map({ $0.label == nil || !$0.text.isEmpty }) ?? true {
                // A failed chunk right under its header is that entry's text; any other ⚠ line is a line of its own.
                entries.append(Entry(label: nil, timestamp: "", text: line, line: i))
            } else if let last = entries.indices.last, entries[last].label != nil {
                entries[last].text += (entries[last].text.isEmpty ? "" : "\n") + unescape(line)
            }
        }
        for i in entries.indices { entries[i].text = entries[i].text.trimmingCharacters(in: .whitespacesAndNewlines) }
        let start = fields["date"].flatMap { day in fields["time"].flatMap { date(day + " " + $0, calendar: calendar) } }
        return Parsed(start: start, title: fields["title"].flatMap { $0.isEmpty ? nil : $0 },
                      app: fields["app"].flatMap { $0.isEmpty ? nil : $0 }, entries: entries)
    }

    /// `YYYY-MM-DD HH:MM` or `YYYY-MM-DD HH:MM:SS` in the calendar's time zone, as headers and the front matter write it.
    public static func date(_ text: String, calendar: Calendar = .current) -> Date? {
        guard let m = text.wholeMatch(of: /(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})(?::(\d{2}))?/) else { return nil }
        let c = DateComponents(year: Int(m.1), month: Int(m.2), day: Int(m.3), hour: Int(m.4), minute: Int(m.5), second: m.6.flatMap { Int($0) } ?? 0)
        guard c.isValidDate(in: calendar) else { return nil }
        return calendar.date(from: c)
    }

    /// The front matter's `title` line set to `title`: added after `time` when missing, removed for no name.
    /// Nothing else changes; a note without front matter is returned as it is.
    public static func settingTitle(_ note: String, _ title: String?) -> String {
        var lines = note.components(separatedBy: "\n")
        let bare = lines.map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        guard bare.first == "---", let close = bare.dropFirst().firstIndex(of: "---") else { return note }
        let name = title.map(oneLine) ?? ""
        let line = name.isEmpty ? nil : "title: \(quoted(name))" + (lines[0].hasSuffix("\r") ? "\r" : "")
        if let i = bare[1..<close].firstIndex(where: { $0.hasPrefix("title:") }) {
            if let line { lines[i] = line } else { lines.remove(at: i) }
        } else if let line {
            lines.insert(line, at: bare[1..<close].firstIndex { $0.hasPrefix("time:") }.map { $0 + 1 } ?? close)
        }
        return lines.joined(separator: "\n")
    }

    /// A YAML scalar as Shepit and Obsidian write them: plain, "double" (with \" and \\) or 'single' (with '').
    private static func unquoted(_ value: String) -> String {
        guard value.count >= 2, let quote = value.first, quote == value.last, quote == "\"" || quote == "'" else { return value }
        let inner = value.dropFirst().dropLast()
        if quote == "'" { return inner.replacingOccurrences(of: "''", with: "'") }
        var out = "", escaped = false
        for c in inner {
            if escaped || c != "\\" { out.append(c); escaped = false } else { escaped = true }
        }
        return out
    }

    /// Undoes `escapeLeadingMarker`.
    private static func unescape(_ line: String) -> String {
        if line.hasPrefix("\\"), let next = line.dropFirst().first, "#->+*[|".contains(next) { return String(line.dropFirst()) }
        if let match = line.prefixMatch(of: /(\d+)\\[.)](\s|$)/) { return String(match.1) + line.dropFirst(match.1.count + 1) }
        return line
    }

    static func oneLine(_ text: String) -> String {
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
