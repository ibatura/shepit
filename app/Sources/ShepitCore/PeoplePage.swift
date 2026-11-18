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
    }

    /// You first, then by the last meeting, newest first. `meetings` newest first, as the store gives them; a presence in
    /// a meeting not among them is left out. `you`: the author's name.
    public static func people(_ presences: [MeetingStore.Presence], meetings: [MeetingStore.Meeting], you: String, now: Date,
                              calendar: Calendar = .current) -> [Person] {
        let byMeeting = Dictionary(grouping: presences, by: \.meeting)
        var order: [Int] = []
        var found: [Int: (presence: MeetingStore.Presence, meetings: [MeetingStore.Meeting], voice: Int)] = [:]
        for meeting in meetings {
            for presence in (byMeeting[meeting.id] ?? []).sorted(by: { $0.person < $1.person }) {
                if found[presence.person] == nil { order.append(presence.person) }
                found[presence.person, default: (presence, [], 0)].meetings.append(meeting)
                if presence.samples > 0 { found[presence.person]?.voice += 1 }
            }
        }
        let thisYear = DateFormatter.english("d MMM", calendar), otherYear = DateFormatter.english("d MMM yyyy", calendar)
        let when = DateFormatter.english("d MMM yyyy, HH:mm", calendar)
        let people = order.compactMap { id -> Person? in
            guard let (presence, meetings, voice) = found[id], let last = meetings.first?.start else { return nil }
            let name = presence.you ? you : presence.name ?? ""
            let date = (calendar.isDate(last, equalTo: now, toGranularity: .year) ? thisYear : otherYear).string(from: last)
            let detail = [presence.you ? "you" : nil, count(meetings.count, "meeting"), "last \(date)"].compactMap { $0 }
            return Person(id: id, name: name, initials: MeetingPage.initials(name), isYou: presence.you,
                          detail: detail.joined(separator: " · "), voiceMeetings: voice,
                          voice: voice == 0 ? "No voice saved" : "Saved from \(count(voice, "meeting"))",
                          meetings: meetings.map { MeetingRow(id: $0.id, title: MeetingPage.title($0.title, $0.app), date: when.string(from: $0.start)) })
        }
        return people.filter(\.isYou) + people.filter { !$0.isYou }
    }

    private static func count(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }
}
