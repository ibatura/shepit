import Foundation

/// Names from a transcript Teams or Zoom saved of the same call (import names design §5): the file lined up with the
/// meeting by time, and each person matched to the speaker the file names at the times they speak.
public enum NameImport {
    /// One line of the meeting: its person now, its start in seconds from the meeting's start, and its length.
    public struct Line: Equatable, Sendable {
        public var person: String
        public var start: TimeInterval
        public var length: TimeInterval

        public init(person: String, start: TimeInterval, length: TimeInterval) {
            self.person = person
            self.start = start
            self.length = length
        }
    }

    public struct Match: Equatable, Sendable {
        public var speaker: String
        /// Of all the seconds the person shares with any speaker.
        public var share: Double
        public var seconds: Int
    }

    public struct Alignment: Equatable, Sendable {
        /// The meeting second at which the file's 00:00 falls; negative when the file started first.
        public var shift: Int
        /// The people with a clear match.
        public var matches: [String: Match]
        /// The file's speakers, in the order of their first cue.
        public var speakers: [String]
    }

    // Settled on the author's meetings (spec §11): the best shift a minute away scored 62–63% of the best on the right
    // meeting, 95–100% on others.
    static let away = 60, lineUp = 0.9
    static let matchShare = 0.5, matchSeconds = 5
    static let maxFileSeconds = 6 * 3600

    /// Where the file sits in the meeting and who is who; nil when it doesn't line up with this meeting. In whole seconds:
    /// every shift at which they overlap, scored by the seconds each person shares with the speaker they share most with.
    public static func align(_ lines: [Line], _ cues: [SpeakerTranscript.Cue]) -> Alignment? {
        let people = firsts(lines.map(\.person)), speakers = firsts(cues.map(\.speaker))
        let who = owners(lines.map { ($0.start, $0.start + $0.length, people.firstIndex(of: $0.person)!) })
        let said = owners(cues.map { ($0.start, $0.end, speakers.firstIndex(of: $0.speaker)!) })
        // The search grows with the file's last second: a cue with a broken time far out would take minutes.
        guard !who.isEmpty, !said.isEmpty, said.count <= maxFileSeconds else { return nil }
        let width = speakers.count
        /// The seconds person p shares with speaker s, at `p * width + s`.
        func shared(_ shift: Int) -> [Int] {
            var counts = [Int](repeating: 0, count: people.count * width)
            for second in max(0, -shift)..<min(said.count, who.count - shift) {
                let speaker = said[second], person = who[second + shift]
                if speaker >= 0, person >= 0 { counts[person * width + speaker] += 1 }
            }
            return counts
        }
        func score(_ counts: [Int]) -> Int { people.indices.reduce(0) { $0 + counts[$1 * width..<($1 + 1) * width].max()! } }
        let scores = (1 - said.count..<who.count).map { (shift: $0, score: score(shared($0))) }
        guard let best = scores.max(by: { ($0.score, -abs($0.shift)) < ($1.score, -abs($1.shift)) }), best.score > 0,
              scores.allSatisfy({ abs($0.shift - best.shift) <= away || Double($0.score) < lineUp * Double(best.score) })
        else { return nil }
        let counts = shared(best.shift)
        var matches: [String: Match] = [:]
        for (index, person) in people.enumerated() {
            let row = Array(counts[index * width..<(index + 1) * width]), total = row.reduce(0, +)
            guard total > 0, let top = row.indices.max(by: { row[$0] < row[$1] }) else { continue }
            let share = Double(row[top]) / Double(total)
            if share >= matchShare, row[top] >= matchSeconds { matches[person] = Match(speaker: speakers[top], share: share, seconds: row[top]) }
        }
        return Alignment(shift: best.shift, matches: matches, speakers: speakers)
    }

    /// Each value once, in order of first appearance.
    private static func firsts(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    /// Who owns each second from 0: the index of the span that covers it, the later span where two do; -1 for nobody.
    private static func owners(_ spans: [(start: TimeInterval, end: TimeInterval, owner: Int)]) -> [Int] {
        var owners = [Int](repeating: -1, count: Int((spans.map(\.end).max() ?? 0).rounded(.up)))
        for span in spans where span.end > max(span.start, 0) {
            for second in max(0, Int(span.start))..<Int(span.end.rounded(.up)) { owners[second] = span.owner }
        }
        return owners
    }
}
