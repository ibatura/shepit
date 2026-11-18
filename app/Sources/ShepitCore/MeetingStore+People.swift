import Foundation

/// People across meetings (voices design §6, §7): the People section's reads, a person's rename and merge, and the words
/// of each line.
extension MeetingStore {
    /// A person's talk in one meeting where they have lines now (voices design §6).
    public struct Presence: Equatable, Sendable {
        public var meeting: Int
        /// Their words; nil while the meeting's words aren't known (listed before they were kept).
        public var words: Int? = nil
        /// Their talk time; nil when none of their lines has one (Add notes…, meetings before talk time was kept).
        public var seconds: Double? = nil
        /// The words of the whole meeting, everyone's.
        public var meetingWords: Int? = nil
    }

    /// `person`'s meetings started `since` (all of them for nil) where they have lines now, once each.
    public func presences(of person: Int, since: Date? = nil) throws -> [Presence] {
        try sqlite.rows("""
            SELECT people.meeting, sum(lines.words), sum(lines.seconds),
              (SELECT sum(words) FROM lines AS everyone WHERE everyone.meeting = people.meeting)
            FROM people JOIN meetings ON meetings.id = people.meeting
            JOIN lines ON lines.meeting = people.meeting AND lines.current = people.key
            WHERE people.person = ? AND meetings.start >= ?
            GROUP BY people.meeting
            """, [person, (since ?? .distantPast).timeIntervalSince1970]) { row in
            Presence(meeting: row.int(0), words: row.isNull(1) ? nil : row.int(1), seconds: row.isNull(2) ? nil : row.double(2),
                     meetingWords: row.isNull(3) ? nil : row.int(3))
        }
    }

    /// A person as People's list shows them: how many listed meetings they have lines in now, the last one's start, and
    /// in how many of them a line of theirs keeps a voice sample.
    public struct Summary: Equatable, Sendable {
        public var person: Int
        /// nil for You, who has no name of their own.
        public var name: String?
        public var you: Bool
        public var meetings: Int
        public var last: Date
        public var voiceMeetings: Int
        /// Samples of their lines, counted up to `Voices.enough`: fewer, and their print isn't compared yet.
        public var voiceSamples: Int
    }

    /// A row per person, without reading every line: each meeting stops at its first line of theirs, and at their first
    /// `Voices.enough` samples.
    public func summaries() throws -> [Summary] {
        try sqlite.rows("""
            SELECT id, name, you, count(DISTINCT meeting), max(start), count(DISTINCT CASE WHEN voiced > 0 THEN meeting END),
              min(sum(voiced), ?)
            FROM (
              SELECT persons.id, persons.name, persons.you, people.meeting, meetings.start,
                (SELECT count(*) FROM (SELECT 1 FROM line_voices
                  WHERE line_voices.meeting = people.meeting AND line_voices.key = people.key LIMIT ?)) AS voiced
              FROM people JOIN persons ON persons.id = people.person JOIN meetings ON meetings.id = people.meeting
              WHERE EXISTS (SELECT 1 FROM lines WHERE lines.meeting = people.meeting AND lines.current = people.key))
            GROUP BY id
            """, [Voices.enough, Voices.enough]) { row in
            Summary(person: row.int(0), name: row.text(1), you: row.int(2) == 1, meetings: row.int(3),
                    last: Date(timeIntervalSince1970: row.double(4)), voiceMeetings: row.int(5), voiceSamples: row.int(6))
        }
    }

    /// Rename (voices design §6): the person's one name, in every meeting and in the headers of their notes.
    public func rename(person: Int, to name: String) throws {
        try change(try meetings(of: person)) {
            try sqlite.run("UPDATE persons SET name = ? WHERE id = ? AND you = 0", [name, person])
        }
    }

    /// Merge into… (voices design §6): every meeting of `person` moves to `other`, and `person` is deleted. In a meeting
    /// with both, `person`'s lines go to the other, as a merge in one meeting does. Into You, a meeting without "you"
    /// gets this person as its "you", named `myName`.
    public func merge(person: Int, into other: Int, myName: String) throws {
        let meetings = try meetings(of: person)
        let you = try youID()
        try change(meetings) {
            for meeting in meetings {
                var target = other == you ? meeting.you : try keys(of: other, in: meeting.id).first
                for key in try keys(of: person, in: meeting.id) {
                    if let target {
                        try merge(meeting.id, person: key, into: target)
                        try link(meeting.id, key: key, to: nil)
                        continue
                    }
                    if other == you {
                        try sqlite.run("UPDATE meetings SET you = ? WHERE id = ?", [key, meeting.id])
                        try sqlite.run("UPDATE people SET name = ? WHERE meeting = ? AND key = ?", [myName, meeting.id, key])
                    }
                    try sqlite.run("UPDATE people SET person = ? WHERE meeting = ? AND key = ?", [other, meeting.id, key])
                    target = key
                }
            }
            try sqlite.run("UPDATE OR IGNORE declined SET person = ? WHERE person = ?", [other, person])
            try sqlite.run("DELETE FROM declined WHERE person = ?", [person])
            try dropUnlistedPersons()
        }
    }

    /// The meetings a person is in, newest first.
    public func meetings(of person: Int) throws -> [Meeting] {
        try meetings("WHERE id IN (SELECT meeting FROM people WHERE person = ?) ORDER BY start DESC, id DESC", [person])
    }

    private func keys(of person: Int, in meeting: Int) throws -> [String] {
        try sqlite.rows("SELECT key FROM people WHERE meeting = ? AND person = ? ORDER BY rowid", [meeting, person]) { $0.text(0) ?? "" }
    }

    /// Another person (not You) with `name`, ignoring case, accents and script, also one with no lines left: their name
    /// is taken although People doesn't list them.
    public func person(named name: String, except person: Int) throws -> (id: Int, name: String)? {
        guard let key = Names.key(name) else { return nil }
        return try sqlite.rows("SELECT id, name FROM persons WHERE you = 0 AND id != ? AND name_key(name) = ? ORDER BY id LIMIT 1",
                               [person, key]) { (id: $0.int(0), name: $0.text(1) ?? "") }.first
    }

    /// Meetings listed before words were kept (voices design §7): some lines have none.
    public func meetingsWithoutWords() throws -> [Meeting] {
        try meetings("WHERE id IN (SELECT meeting FROM lines WHERE words IS NULL) ORDER BY start DESC, id DESC")
    }

    /// The words of a meeting listed before they were kept, from its note's `entries`; only lines that have none.
    public func fillWords(_ meeting: Int, entries: [MeetingNote.Entry]) throws {
        guard try !sqlite.rows("SELECT 1 FROM lines WHERE meeting = ? AND words IS NULL LIMIT 1", [meeting]) { $0.int(0) }.isEmpty else { return }
        let lines = try lines(meeting)
        try transaction {
            for (entry, line) in zip(entries, MeetingPage.pair(entries, lines)) {
                guard let line else { continue }
                try sqlite.run("UPDATE lines SET words = ? WHERE meeting = ? AND timestamp = ? AND ord = ? AND words IS NULL",
                               [Self.words(entry.text), meeting, line.place.timestamp, line.place.order])
            }
        }
    }
}
