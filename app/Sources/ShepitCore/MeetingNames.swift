import Foundation

/// Meeting names given at Start, kept locally (`~/.local/share/dictation/meeting-names.json`) so the name
/// dialog can offer them again: a list of recent names, and the name of a repeating meeting prefilled when
/// one ran at this time before. Zoom and quick Google Meet calls show no name anywhere (2026-11-06).
public enum MeetingNames {
    public struct Entry: Codable, Equatable, Sendable {
        public var title: String
        public var app: String?
        public var start: Date
        public init(title: String, app: String?, start: Date) {
            self.title = title
            self.app = app
            self.start = start
        }
    }

    public static let fileName = "meeting-names.json"
    static let kept = 300
    /// How far back a repeat is looked for, and how close in time of day it must start.
    static let lookBack: TimeInterval = 36 * 24 * 3600
    static let closeMinutes = 15

    public static func load(_ file: URL) -> [Entry] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Entry].self, from: data)) ?? []
    }

    public static func save(_ entries: [Entry], to file: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(entries).write(to: file, options: .atomic)
    }

    /// `entries` with this meeting added; the oldest dropped past `kept`.
    public static func adding(_ entries: [Entry], title: String, app: String?, start: Date) -> [Entry] {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return entries }
        return Array((entries + [Entry(title: title, app: app, start: start)]).suffix(kept))
    }

    /// Distinct names, newest first.
    public static func recent(_ entries: [Entry], limit: Int = 12) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for entry in entries.sorted(by: { $0.start > $1.start }) where seen.insert(entry.title.lowercased()).inserted {
            names.append(entry.title)
            if names.count == limit { break }
        }
        return names
    }

    /// The name of a meeting that repeats at this time: started within 15 minutes of this time of day
    /// in the last 5 weeks, on the same weekday (weekly) or on 2 or more other days (daily). The newest
    /// weekly one wins, then the most frequent daily one. An entry from another known app doesn't count.
    public static func repeating(_ entries: [Entry], at start: Date, app: String?, calendar: Calendar = .current) -> String? {
        let minute = { (date: Date) -> Int in
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
        let now = minute(start)
        let today = calendar.startOfDay(for: start)
        let candidates = entries.filter { entry in
            entry.start < today && start.timeIntervalSince(entry.start) <= lookBack
                && abs(minute(entry.start) - now) <= closeMinutes
                && (app == nil || entry.app == nil || entry.app == app)
        }
        let weekday = calendar.component(.weekday, from: start)
        if let weekly = candidates.filter({ calendar.component(.weekday, from: $0.start) == weekday }).max(by: { $0.start < $1.start }) {
            return weekly.title
        }
        var days: [String: Set<Date>] = [:]
        var shown: [String: String] = [:]
        for entry in candidates {
            days[entry.title.lowercased(), default: []].insert(calendar.startOfDay(for: entry.start))
            shown[entry.title.lowercased()] = entry.title
        }
        let daily = days.filter { $0.value.count >= 2 }
        guard let best = daily.max(by: { ($0.value.count, $0.value.max()!) < ($1.value.count, $1.value.max()!) }) else { return nil }
        return shown[best.key]
    }
}
