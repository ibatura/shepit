import Foundation

/// What the People section shows (voices design §6), built from the store's summaries, one person's presences and the
/// meetings.
public enum PeoplePage {
    public struct Person: Equatable, Sendable, Identifiable {
        public var id: Int
        public var name: String
        public var initials: String
        public var isYou: Bool
        /// "6 meetings · last 10 Nov".
        public var detail: String
        /// How many of their meetings keep samples of their lines; 0: no voice saved.
        public var voiceMeetings: Int
        /// "Saved from 6 meetings", "No voice saved"; yours says where it comes from.
        public var voice: String
    }

    public struct MeetingRow: Equatable, Sendable, Identifiable {
        public var id: Int
        public var title: String
        public var date: String
        /// Their talk time and words: "12 min · 1,240 words", "– · 30 words"; "–" while neither is known.
        public var talk: String
    }

    /// May also be in: a meeting and its Person N whose voice is like the person's.
    public struct Suggestion: Equatable, Sendable, Identifiable {
        public var id: Int
        public var title: String
        public var date: String
        public var key: String
    }

    /// You first, then by the last meeting, newest first. `you`: the author's name.
    public static func people(_ summaries: [MeetingStore.Summary], you: String, now: Date, calendar: Calendar = .current) -> [Person] {
        let thisYear = DateFormatter.english("d MMM", calendar), otherYear = DateFormatter.english("d MMM yyyy", calendar)
        return summaries.sorted { ($0.you ? 0 : 1, -$0.last.timeIntervalSince1970, $0.person) < ($1.you ? 0 : 1, -$1.last.timeIntervalSince1970, $1.person) }
            .map { summary in
                let name = summary.you ? you : summary.name ?? ""
                let date = (calendar.isDate(summary.last, equalTo: now, toGranularity: .year) ? thisYear : otherYear).string(from: summary.last)
                let detail = [summary.you ? "you" : nil, count(summary.meetings, "meeting"), "last \(date)"].compactMap { $0 }
                let voice = summary.voiceMeetings
                return Person(id: summary.person, name: name, initials: MeetingPage.initials(name), isYou: summary.you,
                              detail: detail.joined(separator: " · "), voiceMeetings: voice,
                              voice: voice == 0 ? "No voice saved"
                                  : "Saved from \(count(voice, "meeting"))" + (summary.you ? ": your microphone and the lines given to you" : ""))
            }
    }

    /// A person People doesn't list (no lines left in any meeting) whose name is taken, for the question about it.
    public static func unlisted(_ id: Int, name: String) -> Person {
        Person(id: id, name: name, initials: MeetingPage.initials(name), isYou: false, detail: "no lines in any meeting",
               voiceMeetings: 0, voice: "No voice saved")
    }

    /// A person's meetings (their `presences`, as the store gives them for a period), newest first as `meetings` are.
    public static func meetings(_ presences: [MeetingStore.Presence], meetings: [MeetingStore.Meeting],
                                calendar: Calendar = .current) -> [MeetingRow] {
        let byMeeting = Dictionary(presences.map { ($0.meeting, $0) }, uniquingKeysWith: { first, _ in first })
        let describe = describing(calendar)
        return meetings.compactMap { meeting in
            byMeeting[meeting.id].map { presence in
                let (title, date) = describe(meeting)
                let talk = presence.words.map { [presence.seconds.map(StatisticsPage.duration) ?? "–", "\($0.formatted()) words"] }
                    ?? presence.seconds.map { [StatisticsPage.duration($0)] } ?? ["–"]
                return MeetingRow(id: meeting.id, title: title, date: date, talk: talk.joined(separator: " · "))
            }
        }
    }

    /// Who talked how much (voices design §6): a person's meetings (their `presences` in a period), talk time and words,
    /// and their share of all the words of those meetings. Talk time and words count the meetings that know them; "–"
    /// when none does.
    public static func talk(_ presences: [MeetingStore.Presence]) -> [StatisticsPage.Tile] {
        let seconds = presences.compactMap(\.seconds), counted = presences.filter { $0.words != nil }
        let words = counted.compactMap(\.words).reduce(0, +), all = counted.compactMap(\.meetingWords).reduce(0, +)
        return [
            .init(title: "Meetings", value: "\(presences.count)"),
            .init(title: "Talk time", value: seconds.isEmpty ? "–" : StatisticsPage.duration(seconds.reduce(0, +))),
            .init(title: "Words", value: counted.isEmpty ? "–" : words.formatted()),
            .init(title: "Share of words", value: all == 0 ? "–" : "\(Int((Double(words) / Double(all) * 100).rounded()))%"),
        ]
    }

    /// May also be in: the meetings of `found` (key by meeting), in the order of `meetings` (newest first, as the store
    /// gives them).
    public static func suggestions(_ found: [Int: String], meetings: [MeetingStore.Meeting], calendar: Calendar = .current) -> [Suggestion] {
        let describe = describing(calendar)
        return meetings.compactMap { meeting in
            found[meeting.id].map { key in
                let (title, date) = describe(meeting)
                return Suggestion(id: meeting.id, title: title, date: date, key: key)
            }
        }
    }

    /// A meeting's title and "10 Nov 2026, 10:00".
    private static func describing(_ calendar: Calendar) -> (MeetingStore.Meeting) -> (title: String, date: String) {
        let when = DateFormatter.english("d MMM yyyy, HH:mm", calendar)
        return { (MeetingPage.title($0.title, $0.app), when.string(from: $0.start)) }
    }

    /// "May also be in 3 meetings".
    public static func mayAlsoBeIn(_ suggestions: [Suggestion]) -> String {
        "May also be in \(count(suggestions.count, "meeting"))"
    }

    private static func count(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }
}
