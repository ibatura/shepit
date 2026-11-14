import Foundation

/// What the Meetings section shows (Meetings design §5–8), built from the store and the note as it is now.
public enum MeetingPage {
    public typealias Line = MeetingStore.Line
    public typealias Person = MeetingStore.Person

    // MARK: Pairing (§8)

    /// The stored line each note entry is: the k-th header with timestamp T is the k-th line with T. A second whose
    /// counts differ (entries added or deleted in Obsidian) is left unpaired, and so are ⚠ lines.
    public static func pair(_ entries: [MeetingNote.Entry], _ lines: [Line]) -> [Line?] {
        let stored = Dictionary(grouping: lines, by: \.timestamp)
        let written = Dictionary(grouping: entries.filter { $0.label != nil }, by: \.timestamp).mapValues(\.count)
        var seen: [String: Int] = [:]
        return entries.map { entry in
            guard entry.label != nil else { return nil }
            let k = seen[entry.timestamp, default: 0]
            seen[entry.timestamp] = k + 1
            guard let same = stored[entry.timestamp], same.count == written[entry.timestamp] else { return nil }
            return same.first { $0.order == k }
        }
    }

    // MARK: One meeting (§6)

    public struct PersonRow: Equatable, Sendable {
        public var key: String
        /// The name given, or the label.
        public var name: String
        /// The name is a real one (given in the window, or "you"), not a "Person N" label.
        public var named: Bool
        public var initials: String
        public var isYou: Bool
        /// Share of the meeting's words, 0...1.
        public var share: Double
        /// The people this one can be merged into.
        public var mergeTargets: [String]
    }

    public struct Row: Equatable, Sendable {
        /// nil for a ⚠ line of its own.
        public var name: String?
        /// "10:00:19"; empty for a ⚠ line.
        public var time: String
        public var text: String
        /// nil: not paired with the store, so it can't be given.
        public var place: MeetingStore.Place?
        /// The stored person it belongs to now.
        public var person: String?

        public init(name: String?, time: String, text: String, place: MeetingStore.Place?, person: String?) {
            self.name = name
            self.time = time
            self.text = text
            self.place = place
            self.person = person
        }
    }

    public struct Page: Equatable, Sendable {
        public var people: [PersonRow]
        public var rows: [Row]
        public var canReset: Bool
    }

    public static func page(people: [Person], lines: [Line], you: String?, entries: [MeetingNote.Entry]) -> Page {
        let names = shownNames(people)
        let paired = pair(entries, lines)
        var words: [String: Int] = [:]
        for (entry, line) in zip(entries, paired) where entry.text != MeetingQueue.failedText {
            if let line { words[line.current, default: 0] += entry.text.split(whereSeparator: \.isWhitespace).count }
        }
        let total = max(1, words.values.reduce(0, +))
        var order: [String] = []
        for line in lines where !order.contains(line.current) { order.append(line.current) }
        let rows = order.map { key in
            let name = people.first { $0.key == key }?.name
            return PersonRow(key: key, name: names[key] ?? key, named: name != nil || key == you, initials: initials(names[key] ?? key),
                             isYou: key == you, share: Double(words[key] ?? 0) / Double(total),
                             mergeTargets: key == you ? [] : order.filter { $0 != key })
        }
        let transcript = zip(entries, paired).map { entry, line in
            Row(name: line.map { names[$0.current] ?? $0.current } ?? entry.label, time: String(entry.timestamp.suffix(8)),
                text: entry.text, place: line?.place, person: line?.current)
        }
        return Page(people: rows, rows: transcript, canReset: lines.contains { $0.original != $0.current })
    }

    // MARK: Changes (§8)

    /// The note with the headers of the lines whose shown name differs between `before` and `after` set to the new name.
    /// Only those headers change; a line that is not paired with the note is left alone.
    public static func relabelled(_ note: String, before: (people: [Person], lines: [Line]), after: (people: [Person], lines: [Line])) -> String {
        let old = shownNames(before.people), new = shownNames(after.people)
        let was = Dictionary(uniqueKeysWithValues: before.lines.map { ($0.place, old[$0.current] ?? $0.current) })
        let entries = MeetingNote.parse(note).entries
        var labels: [Int: String] = [:]
        for (entry, line) in zip(entries, pair(entries, after.lines)) {
            guard let line else { continue }
            let name = new[line.current] ?? line.current
            if was[line.place] != name { labels[entry.line] = name }
        }
        return labels.isEmpty ? note : Speakers.setLabels(note, labels)
    }

    /// Another person of the meeting (with lines) that already shows `name`, ignoring case; nil when none.
    public static func clash(people: [Person], lines: [Line], person: String, name: String) -> String? {
        guard let name = self.name(name) else { return nil }
        let names = shownNames(people)
        return Set(lines.map(\.current)).sorted().first { $0 != person && (names[$0] ?? $0).caseInsensitiveCompare(name) == .orderedSame }
    }

    /// A typed name as it is stored: one line, trimmed; nil when empty.
    public static func name(_ typed: String) -> String? {
        let name = MeetingNote.oneLine(typed)
        return name.isEmpty ? nil : name
    }

    private static func shownNames(_ people: [Person]) -> [String: String] {
        Dictionary(people.map { ($0.key, $0.name ?? $0.key) }, uniquingKeysWith: { first, _ in first })
    }

    /// "P2" for Person 2, else the first letters of the first two words.
    private static func initials(_ name: String) -> String {
        if let match = name.wholeMatch(of: /Person (\d+)/) { return "P\(match.1)" }
        return String(name.split(whereSeparator: \.isWhitespace).prefix(2).compactMap(\.first)).uppercased()
    }

    // MARK: The list (§5)

    public struct ListRow: Equatable, Sendable {
        /// nil for the transcript being recorded.
        public var id: Int?
        public var title: String
        public var detail: String

        public init(id: Int?, title: String, detail: String) {
            self.id = id
            self.title = title
            self.detail = detail
        }
    }

    public struct ListGroup: Equatable, Sendable {
        /// Empty for the running transcript's group.
        public var title: String
        public var rows: [ListRow]
    }

    public struct Running: Equatable, Sendable {
        public var state: MeetingState
        public var title: String?
        public var app: String?

        public init(state: MeetingState, title: String?, app: String?) {
            self.state = state
            self.title = title
            self.app = app
        }
    }

    static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    static let fullMonths = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
                             "November", "December"]

    /// `meetings` newest first, as the store gives them; `missing`: ids whose note is not found.
    public static func list(_ meetings: [MeetingStore.Meeting], missing: Set<Int>, running: Running?, now: Date,
                            calendar: Calendar = .current) -> [ListGroup] {
        var groups: [ListGroup] = []
        if let running, let detail = detail(running) {
            groups.append(ListGroup(title: "", rows: [ListRow(id: nil, title: title(running.title, running.app), detail: detail)]))
        }
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let lastWeek = calendar.date(byAdding: .day, value: -7, to: thisWeek) ?? thisWeek
        for meeting in meetings {
            let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: meeting.start)
            let clock = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
            let group: String, when: String
            if meeting.start >= lastWeek {
                group = meeting.start >= thisWeek ? "This week" : "Last week"
                when = "\(MeetingFileName.weekdays[((c.weekday ?? 1) - 1) % 7]) \(clock)"
            } else {
                group = "\(fullMonths[(c.month ?? 1) - 1]) \(c.year ?? 0)"
                when = "\(c.day ?? 0) \(months[(c.month ?? 1) - 1]), \(clock)"
            }
            let parts = missing.contains(meeting.id) ? [when, "note not found"]
                : [when, meeting.duration.map { "\(max(1, Int(($0 / 60).rounded()))) min" }, meeting.app].compactMap { $0 }
            let row = ListRow(id: meeting.id, title: title(meeting.title, meeting.app), detail: parts.joined(separator: " · "))
            if groups.last?.title == group { groups[groups.count - 1].rows.append(row) } else { groups.append(ListGroup(title: group, rows: [row])) }
        }
        return groups
    }

    /// The name, or "Teams call", or "Meeting".
    public static func title(_ title: String?, _ app: String?) -> String {
        title ?? app.map { "\($0) call" } ?? "Meeting"
    }

    private static func detail(_ running: Running) -> String? {
        switch running.state {
        case .recording(let elapsed, _): ["Recording", StatusText.clock(elapsed), running.app].compactMap { $0 }.joined(separator: " · ")
        case .finishing(let left): "Finishing (\(left) left)"
        case .detectingSpeakers: "Detecting speakers…"
        case .idle, .done, .interrupted: nil
        }
    }
}
