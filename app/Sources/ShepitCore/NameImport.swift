import Foundation

/// Names from a transcript Teams or Zoom saved of the same call (import names design §5): the file lined up with the
/// meeting by time, and each person matched to the speaker the file names at the times they speak.
public enum NameImport {
    /// One line of the meeting: its person now, its start in seconds from the meeting's start, and its length.
    struct Line: Equatable, Sendable {
        var person: String
        var start: TimeInterval
        var length: TimeInterval
    }

    public struct Match: Equatable, Sendable {
        public var speaker: String
        /// Of all the seconds the person shares with any speaker.
        public var share: Double
        public var seconds: Int
    }

    public struct NotLinedUp: LocalizedError {
        public init() {}
        public var errorDescription: String? { "This transcript doesn't line up with this meeting." }
    }

    public struct Alignment: Equatable, Sendable {
        /// The meeting second at which the file's 00:00 falls; negative when the file started first.
        public var shift: Int
        /// The people with lines, in the order of their first line.
        public var people: [String]
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

    /// Where the file sits in the meeting that started at `start`, and who is who.
    public static func align(_ lines: [MeetingStore.Line], start: Date, _ cues: [SpeakerTranscript.Cue]) throws -> Alignment {
        try align(timed(lines, start: start), cues)
    }

    /// The lines as the import times them: from their timestamp, for their `seconds`, or half a second per word for lines
    /// listed before Voices; at least half a second. Lines with no speaker are left out.
    static func timed(_ lines: [MeetingStore.Line], start: Date) -> [Line] {
        lines.compactMap { line in
            guard line.current != MeetingNote.callLabel, let time = MeetingNote.date(line.place.timestamp) else { return nil }
            return Line(person: line.current, start: time.timeIntervalSince(start), length: max(line.seconds ?? Double(line.words ?? 0) / 2, 0.5))
        }
    }

    /// In whole seconds: every shift at which file and meeting overlap, scored by the seconds each person shares with the
    /// speaker they share most with.
    static func align(_ lines: [Line], _ cues: [SpeakerTranscript.Cue]) throws -> Alignment {
        let people = firsts(lines.map(\.person)), speakers = firsts(cues.map(\.speaker))
        let who = owners(lines.map { ($0.start, $0.start + $0.length, people.firstIndex(of: $0.person)!) })
        let said = owners(cues.map { ($0.start, $0.end, speakers.firstIndex(of: $0.speaker)!) })
        // The search grows with the file's last second: a cue with a broken time far out would take minutes.
        guard !who.isEmpty, !said.isEmpty, said.count <= maxFileSeconds else { throw NotLinedUp() }
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
        else { throw NotLinedUp() }
        let counts = shared(best.shift)
        var matches: [String: Match] = [:]
        for (index, person) in people.enumerated() {
            let row = Array(counts[index * width..<(index + 1) * width]), total = row.reduce(0, +)
            guard total > 0, let top = row.indices.max(by: { row[$0] < row[$1] }) else { continue }
            let share = Double(row[top]) / Double(total)
            if share >= matchShare, row[top] >= matchSeconds { matches[person] = Match(speaker: speakers[top], share: share, seconds: row[top]) }
        }
        return Alignment(shift: best.shift, people: people, matches: matches, speakers: speakers)
    }

    // MARK: The sheet (§6) and Apply names (§7)

    /// A person with lines, except You.
    public struct Row: Equatable, Sendable {
        public var key: String
        /// Their name now, or their label.
        public var label: String
        /// The name field: the file's name at first, empty for none. Typing a name ticks the row, emptying it unticks it.
        public var name: String {
            didSet { if name != oldValue { ticked = MeetingPage.name(name) != nil } }
        }
        /// Of the seconds they share with the file's speakers; nil with no clear match.
        public var share: Double?
        public var alreadyNamed: Bool
        public var ticked: Bool
    }

    public struct Merge: Equatable, Sendable {
        public var person: String
        public var into: String
        public var text: String
        public var ticked = true

        public init(person: String, into: String, text: String) {
            self.person = person
            self.into = into
            self.text = text
        }
    }

    /// What the sheet shows, and what the author ticks and types in it.
    public struct Sheet: Equatable, Sendable {
        public var subtitle: String
        public var rows: [Row]
        public var merges: [Merge]
        /// The speakers nobody holds ("Also in the file:").
        public var others: [String]
        /// The name each person with lines has now, You included; people with no name are left out.
        var names: [String: String]

        /// The ticked rows' names, one line and trimmed; none for an empty field or someone a ticked merge takes away.
        private var typed: [String: String] {
            let gone = Set(merges.filter(\.ticked).map(\.person))
            return Dictionary(uniqueKeysWithValues: rows.filter { $0.ticked && !gone.contains($0.key) }
                .compactMap { row in MeetingPage.name(row.name).map { (row.key, $0) } })
        }

        /// The ticked rows whose name another person of the meeting will also have.
        public var clashes: Set<String> {
            let typed = typed, after = names.merging(typed) { $1 }
            let byName = Dictionary(grouping: after.keys) { Names.fold(after[$0]!) }
            return Set(byName.values.filter { $0.count > 1 }.joined().filter { typed[$0] != nil })
        }

        public var canApply: Bool { (rows.contains(where: \.ticked) || merges.contains(where: \.ticked)) && clashes.isEmpty }

        /// What Apply names does: the ticked merges first, then the names.
        public var changes: (merges: [Merge], names: [String: String]) { (merges.filter(\.ticked), typed) }
    }

    /// A speaker matched by several people is held by the one who shares most seconds with it: they get the name, and the
    /// others with no name are offered as a merge into them.
    public static func sheet(file: String, alignment: Alignment, people: [MeetingStore.Person], you: String?) -> Sheet {
        let order = alignment.people
        let named = Dictionary(people.compactMap { person in person.name.map { (person.key, $0) } }, uniquingKeysWith: { first, _ in first })
        var holders: [String: String] = [:] // speaker: person
        for key in order {
            guard let match = alignment.matches[key] else { continue }
            if let holder = holders[match.speaker], alignment.matches[holder]!.seconds >= match.seconds { continue }
            holders[match.speaker] = key
        }
        var rows: [Row] = [], merges: [Merge] = []
        for key in order where key != you {
            let now = named[key], match = alignment.matches[key]
            var row = Row(key: key, label: now ?? key, name: "", share: nil, alreadyNamed: false, ticked: false)
            if let match, holders[match.speaker] == key {
                row.share = match.share
                if let now, Names.fold(now) == Names.fold(match.speaker) { row.alreadyNamed = true }
                else {
                    row.name = match.speaker
                    row.ticked = now == nil // the file's name beside another is offered unticked
                }
            } else if let match, now == nil, let holder = holders[match.speaker] {
                merges.append(Merge(person: key, into: holder, text: holder == you ? "Merge \(key) into you: that's you in the file"
                                    : "Merge \(key) into \(named[holder] ?? holder): both are \(match.speaker) in the file"))
            }
            rows.append(row)
        }
        let start = "\(clock(abs(alignment.shift))) \(alignment.shift < 0 ? "before" : "into") the meeting"
        var names = named.filter { order.contains($0.key) }
        if let you { names[you] = named[you] ?? you }
        return Sheet(subtitle: "From \(file) · the file starts \(start)", rows: rows, merges: merges,
                     others: alignment.speakers.filter { holders[$0] == nil }, names: names)
    }

    /// 12:04, or 1:02:04 from an hour.
    private static func clock(_ seconds: Int) -> String {
        let (hours, minutes, rest) = (seconds / 3600, seconds / 60 % 60, seconds % 60)
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
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
