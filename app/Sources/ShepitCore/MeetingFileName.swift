import Foundation

/// The meeting note's path inside `meetingsFolder`, from the `meetingFileName` template (spec §5.4, §5.9).
public enum MeetingFileName {
    public static let placeholders = ["date", "time", "year", "month", "day", "hour", "minute", "weekday", "title", "app"]
    static let forbidden = Set(#"\:*?"<>|#^[]"#)
    private static let separators = Set(" -–—_·,.")
    private static let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private static var placeholderPattern: Regex<(Substring, Substring)> { /\{([a-z]+)\}/ }

    /// nil when valid, else the problem in the settings-error style ("must …").
    public static func validate(_ template: String) -> String? {
        guard (1...200).contains(template.count) else { return "must have 1 to 200 characters" }
        for match in template.matches(of: placeholderPattern) where !placeholders.contains(String(match.1)) {
            return "has unknown placeholder {\(match.1)}; allowed: " + placeholders.map { "{\($0)}" }.joined(separator: " ")
        }
        let outside = template.replacing(placeholderPattern, with: "")
        if outside.contains(where: { $0 == "{" || $0 == "}" }) { return "has a { or } that is not part of a placeholder" }
        if outside.contains(where: forbidden.contains) {
            return #"must not contain any of \ : * ? " < > | # ^ [ ] outside placeholders"#
        }
        if template.hasPrefix("/") { return "must not start with /" }
        let parts = template.split(separator: "/", omittingEmptySubsequences: false)
        if parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) { return "must not have empty, . or .. folder parts" }
        return nil
    }

    /// Filled-in path relative to the meetings folder, ending in `.md`. Assumes a valid template.
    public static func relativePath(_ template: String, start: Date, title: String?, app: String?, calendar: Calendar = .current) -> String {
        let parts = clean(fill(template, start: start, title: title, app: app, calendar: calendar))
        let path = parts.isEmpty ? clean(fill("{date} {time}", start: start, title: nil, app: nil, calendar: calendar)) : parts
        let joined = path.joined(separator: "/")
        return joined.lowercased().hasSuffix(".md") ? joined : joined + ".md"
    }

    /// `name.md`, or `name (2).md`, `name (3).md`, … when taken.
    public static func unique(_ relative: String, in folder: URL, exists: (URL) -> Bool) -> URL {
        let first = folder.appending(path: relative)
        guard exists(first) else { return first }
        let base = String(relative.dropLast(3))
        var number = 2
        while true {
            let candidate = folder.appending(path: "\(base) (\(number)).md")
            if !exists(candidate) { return candidate }
            number += 1
        }
    }

    private static func fill(_ template: String, start: Date, title: String?, app: String?, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: start)
        func two(_ value: Int?) -> String { String(format: "%02d", value ?? 0) }
        let values: [String: String] = [
            "year": String(format: "%04d", c.year ?? 0), "month": two(c.month), "day": two(c.day),
            "hour": two(c.hour), "minute": two(c.minute),
            "date": "\(String(format: "%04d", c.year ?? 0))-\(two(c.month))-\(two(c.day))",
            "time": "\(two(c.hour))-\(two(c.minute))",
            "weekday": weekdays[((c.weekday ?? 1) - 1) % 7],
            "title": safe(title), "app": safe(app),
        ]
        return template.replacing(placeholderPattern) { values[String($0.1)] ?? "" }
    }

    /// Characters Obsidian forbids or uses for links, `/` and control characters → spaces; at most 80 characters.
    private static func safe(_ value: String?) -> String {
        let replaced = String((value ?? "").map { forbidden.contains($0) || $0 == "/" || $0.unicodeScalars.contains { $0.properties.generalCategory == .control } ? " " : $0 })
        return String(collapse(replaced).prefix(80))
    }

    /// Per folder/file part: repeated spaces collapsed, spaces and separators trimmed at both ends, empty parts dropped.
    private static func clean(_ path: String) -> [String] {
        path.split(separator: "/").map { part in
            var s = Substring(collapse(String(part)))
            while let first = s.first, separators.contains(first) { s = s.dropFirst() }
            while let last = s.last, separators.contains(last) { s = s.dropLast() }
            return String(s)
        }.filter { !$0.isEmpty }
    }

    private static func collapse(_ s: String) -> String {
        s.replacing(/\ {2,}/, with: " ")
    }
}
