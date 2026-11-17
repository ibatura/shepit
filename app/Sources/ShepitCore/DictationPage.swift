import Foundation

/// What the Dictations section shows (Dictations and Dictionary design §5), built from store entries.
public enum DictationPage {
    public struct Row: Equatable, Sendable {
        public var entry: DictationStore.Entry
        /// "14:02 · Slack · 7 words".
        public var detail: String
    }

    /// A line of the list: a day's title, then that day's dictations. One flat list, so SwiftUI builds only the lines
    /// on screen (sections of different lengths make it build every row to count them).
    public enum Line: Identifiable, Equatable, Sendable {
        case day(String)
        case entry(Row)

        public enum ID: Hashable, Sendable {
            case day(String), entry(Int)
        }

        public var id: ID {
            switch self {
            case .day(let title): .day(title)
            case .entry(let row): .entry(row.entry.id)
            }
        }
    }

    /// `entries` newest first, as the store's pages give them: each day's title ("Today", "Yesterday", "13 November",
    /// "31 December 2025") before its first entry.
    public static func lines(_ entries: [DictationStore.Entry], now: Date, calendar: Calendar = .current) -> [Line] {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let time = DateFormatter.english("HH:mm", calendar), day = DateFormatter.english("d MMMM", calendar)
        let dayAndYear = DateFormatter.english("d MMMM yyyy", calendar)
        var lines: [Line] = []
        var lastTitle: String?
        for entry in entries {
            let title = calendar.isDate(entry.time, inSameDayAs: now) ? "Today"
                : calendar.isDate(entry.time, inSameDayAs: yesterday) ? "Yesterday"
                : calendar.isDate(entry.time, equalTo: now, toGranularity: .year) ? day.string(from: entry.time)
                : dayAndYear.string(from: entry.time)
            if title != lastTitle { lines.append(.day(title)) }
            lastTitle = title
            let words = entry.words == 1 ? "1 word" : "\(entry.words) words"
            lines.append(.entry(Row(entry: entry, detail: [time.string(from: entry.time), entry.appName, words].compactMap { $0 }
                .joined(separator: " · "))))
        }
        return lines
    }

    /// "14:02" today, "05.11 14:02" before: Home's list and the menu's Recent.
    public static func when(_ time: Date, now: Date, calendar: Calendar = .current) -> String {
        DateFormatter.english(calendar.isDate(time, inSameDayAs: now) ? "HH:mm" : "dd.MM HH:mm", calendar).string(from: time)
    }

    /// The bottom bar's text for `historyDays`.
    public static func kept(days: Int) -> String {
        switch days {
        case 0: "Kept forever"
        case 1: "Kept for 1 day"
        default: "Kept for \(days) days"
        }
    }
}
