import Foundation

/// Voice samples, prints and recognition in the store (voices design §4, §5).
extension MeetingStore {
    /// Each kept sample with the line it belongs to now: its meeting, place and label (`key`), and that label's person
    /// (nil: nobody named). A print is the samples of the lines a person has now (voices design §5); every read and
    /// deletion of voices goes through this one definition. Temporary: made on every open, so changing it needs no upgrade.
    static let lineVoices = """
        CREATE TEMP VIEW IF NOT EXISTS line_voices AS
          SELECT lines.meeting, lines.timestamp, lines.ord, samples.vector, lines.current AS key, people.person
          FROM lines JOIN people ON people.meeting = lines.meeting AND people.key = lines.current
          JOIN samples USING (meeting, timestamp, ord)
        """

    /// Every sample of a line that belongs to a person now, for prints; `except` leaves one meeting out.
    public func voiceRows(except meeting: Int? = nil) throws -> [Voices.Row] {
        try sqlite.rows("SELECT person, meeting, vector FROM line_voices WHERE person IS NOT NULL AND meeting IS NOT ?", [meeting]) { row in
            VoiceSample(blob: row.blob(2)).map { Voices.Row(person: row.int(0), meeting: row.int(1), sample: $0) }
        }
    }

    /// The samples of each person of `meeting` that has no person yet, by key.
    public func unnamedVoices(_ meeting: Int) throws -> [String: [VoiceSample]] {
        let rows = try sqlite.rows("SELECT key, vector FROM line_voices WHERE meeting = ? AND person IS NULL", [meeting]) { row in
            VoiceSample(blob: row.blob(1)).map { (key: row.text(0) ?? "", sample: $0) }
        }
        return Dictionary(grouping: rows, by: \.key).mapValues { $0.map(\.sample) }
    }

    /// Names the people of `meeting` a print recognises, as the window names them (the note's headers and the store
    /// together), marked as recognised; a match with You merges that person into "you". Returns how many.
    public func recognise(_ meeting: Meeting) throws -> Int {
        let links = Voices.recognise(try unnamedVoices(meeting.id), prints: Voices.prints(try voiceRows(except: meeting.id)))
        let you = try youID()
        let applied = links.filter { $0.value != you || meeting.you != nil }
        guard !applied.isEmpty else { return 0 }
        try change([meeting]) {
            for (key, person) in applied {
                if person == you, let label = meeting.you {
                    try merge(meeting.id, person: key, into: label)
                } else {
                    try link(meeting.id, key: key, to: person)
                    try sqlite.run("UPDATE people SET recognised = 1 WHERE meeting = ? AND key = ?", [meeting.id, key])
                }
            }
        }
        return applied.count
    }

    /// May also be in (voices design §6): the samples of each unnamed person (by key) of each meeting `person` isn't in,
    /// leaving out the ones declined for `person`.
    public func suggestedVoices(for person: Int) throws -> [Int: [String: [VoiceSample]]] {
        let rows = try sqlite.rows("""
            SELECT meeting, key, vector FROM line_voices
            WHERE person IS NULL AND meeting NOT IN (SELECT meeting FROM people WHERE person = ?)
              AND NOT EXISTS (SELECT 1 FROM declined
                WHERE declined.meeting = line_voices.meeting AND declined.key = line_voices.key AND declined.person = ?)
            """, [person, person]) { row in
            VoiceSample(blob: row.blob(2)).map { (meeting: row.int(0), key: row.text(1) ?? "", sample: $0) }
        }
        return Dictionary(grouping: rows, by: \.meeting).mapValues { Dictionary(grouping: $0, by: \.key).mapValues { $0.map(\.sample) } }
    }

    /// Name them (voices design §6): the suggested people (key by meeting) become `person`, in the notes too, unless they
    /// were named meanwhile; the `declined` ones aren't suggested for `person` again.
    public func nameSuggested(_ person: Int, named: [Int: String], declined: [Int: String]) throws {
        try change(try meetings().filter { named[$0.id] != nil }) {
            for (meeting, key) in named {
                try sqlite.run("UPDATE people SET person = ?, name = NULL, recognised = 0 WHERE meeting = ? AND key = ? AND person IS NULL",
                               [person, meeting, key])
            }
            for (meeting, key) in declined {
                try sqlite.run("INSERT OR IGNORE INTO declined (meeting, key, person) VALUES (?, ?, ?)", [meeting, key, person])
            }
        }
    }

    /// The samples of lines that belong to nobody named, in meetings started before `date` (voices design §4: 30 days).
    public func forgetUnnamedVoices(before date: Date) throws {
        try sqlite.runIfExists("""
            DELETE FROM samples WHERE meeting IN (SELECT id FROM meetings WHERE start < ?) AND NOT EXISTS (
              SELECT 1 FROM line_voices AS named WHERE named.meeting = samples.meeting AND named.timestamp = samples.timestamp
                AND named.ord = samples.ord AND named.person IS NOT NULL)
            """, [date.timeIntervalSince1970])
    }

    /// Delete voice…: the samples of the lines that are `person`'s now. The person and their names stay.
    public func deleteVoice(_ person: Int) throws {
        try sqlite.runIfExists("""
            DELETE FROM samples WHERE (meeting, timestamp, ord) IN (SELECT meeting, timestamp, ord FROM line_voices WHERE person = ?)
            """, [person])
    }

    /// Delete all voices…: every sample, named or not.
    public func deleteAllVoices() throws {
        try sqlite.runIfExists("DELETE FROM samples")
    }
}
