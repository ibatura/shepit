import Foundation

/// What the People section shows (voices design §6), built from the store's presences and meetings.
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
        /// "Saved from 6 meetings", "No voice saved".
        public var voice: String
        /// Newest first.
        public var meetings: [MeetingRow]
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

    /// You first, then by the last meeting, newest first. `meetings` newest first, as the store gives them; a presence in
    /// a meeting not among them is left out. `you`: the author's name.
    public static func people(_ presences: [MeetingStore.Presence], meetings: [MeetingStore.Meeting], you: String, now: Date,
                              calendar: Calendar = .current) -> [Person] {
        var order: [Int] = []
        var found: [Int: [(meeting: MeetingStore.Meeting, presence: MeetingStore.Presence)]] = [:]
        for (meeting, presence) in listed(presences, meetings) {
            if found[presence.person] == nil { order.append(presence.person) }
            found[presence.person, default: []].append((meeting, presence))
        }
        let thisYear = DateFormatter.english("d MMM", calendar), otherYear = DateFormatter.english("d MMM yyyy", calendar)
        let describe = describing(calendar)
        let people = order.compactMap { id -> Person? in
            guard let seen = found[id], let (last, presence) = seen.first else { return nil }
            let name = presence.you ? you : presence.name ?? ""
            let date = (calendar.isDate(last.start, equalTo: now, toGranularity: .year) ? thisYear : otherYear).string(from: last.start)
            let detail = [presence.you ? "you" : nil, count(seen.count, "meeting"), "last \(date)"].compactMap { $0 }
            let voice = seen.filter { $0.presence.samples > 0 }.count
            return Person(id: id, name: name, initials: MeetingPage.initials(name), isYou: presence.you,
                          detail: detail.joined(separator: " · "), voiceMeetings: voice,
                          voice: voice == 0 ? "No voice saved" : "Saved from \(count(voice, "meeting"))",
                          meetings: seen.map { meeting, presence in
                              let (title, date) = describe(meeting)
                              let talk = presence.words.map { [presence.seconds.map(StatisticsPage.duration) ?? "–", "\($0.formatted()) words"] }
                                  ?? presence.seconds.map { [StatisticsPage.duration($0)] } ?? ["–"]
                              return MeetingRow(id: meeting.id, title: title, date: date, talk: talk.joined(separator: " · "))
                          })
        }
        return people.filter(\.isYou) + people.filter { !$0.isYou }
    }

    /// Who talked how much (voices design §6): `person`'s meetings in `period`, their talk time and words, and their share
    /// of all the words of those meetings. Talk time and words count the meetings that know them; "–" when none does.
    public static func talk(_ person: Int, _ presences: [MeetingStore.Presence], meetings: [MeetingStore.Meeting], period: Period,
                            now: Date, calendar: Calendar = .current) -> [StatisticsPage.Tile] {
        let since = period.since(now, calendar: calendar) ?? .distantPast
        let theirs = listed(presences, meetings).filter { $0.presence.person == person && $0.meeting.start >= since }.map(\.presence)
        let seconds = theirs.compactMap(\.seconds), counted = theirs.filter { $0.words != nil }
        let words = counted.compactMap(\.words).reduce(0, +), all = counted.compactMap(\.meetingWords).reduce(0, +)
        return [
            .init(title: "Meetings", value: "\(theirs.count)"),
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

    /// Each presence with its meeting, in the order of `meetings`; presences in meetings not among them left out.
    private static func listed(_ presences: [MeetingStore.Presence], _ meetings: [MeetingStore.Meeting])
        -> [(meeting: MeetingStore.Meeting, presence: MeetingStore.Presence)] {
        let byMeeting = Dictionary(grouping: presences, by: \.meeting)
        return meetings.flatMap { meeting in (byMeeting[meeting.id] ?? []).sorted { $0.person < $1.person }.map { (meeting, $0) } }
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
