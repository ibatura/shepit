import Foundation

/// How far back Dictations lists and Statistics counts: the choices of both sections' period menus (the author,
/// 2026-11-16): a long list scrolls badly, and all history is rarely wanted.
public enum Period: String, CaseIterable, Sendable {
    case today, week, month, months3, months6, months9, year, all

    public var title: String {
        switch self {
        case .today: "Today"
        case .week: "Last 7 days"
        case .month: "Last month"
        case .months3: "Last 3 months"
        case .months6: "Last 6 months"
        case .months9: "Last 9 months"
        case .year: "Last year"
        case .all: "All history"
        }
    }

    /// The oldest time listed, at the start of a day; nil for all history.
    public func since(_ now: Date, calendar: Calendar = .current) -> Date? {
        let today = calendar.startOfDay(for: now)
        let back: (Calendar.Component, Int)? = switch self {
        case .today: (.day, 0)
        case .week: (.day, -6)
        case .month: (.month, -1)
        case .months3: (.month, -3)
        case .months6: (.month, -6)
        case .months9: (.month, -9)
        case .year: (.year, -1)
        case .all: nil
        }
        return back.flatMap { calendar.date(byAdding: $0.0, value: $0.1, to: today) }
    }
}

/// What Statistics counts, Dictations lists and People tallies (statistics design §4, settings review design §9): one of
/// the menu's periods, or whole days picked in Custom….
public enum StatsPeriod: Hashable, Sendable {
    case preset(Period)
    /// Both days included; any time within a day stands for the whole day.
    case custom(from: Date, through: Date)

    /// From the start of the first day to now, or to the end of a custom range's last day; nil for all history.
    public func range(now: Date, calendar: Calendar = .current) -> DateInterval? {
        bounds(now: now, calendar: calendar).map { DateInterval(start: $0.start, end: $0.end) }
    }

    /// As many days right before the range, its last day up to the same time: today against yesterday until now,
    /// Last 7 days against the 7 days before, a custom range against as many days before it. Counted in calendar
    /// days, so a day with a clock change lines up. Nil for all history.
    public func previous(now: Date, calendar: Calendar = .current) -> DateInterval? {
        guard let (start, end, lastDay) = bounds(now: now, calendar: calendar) else { return nil }
        let days = (calendar.dateComponents([.day], from: start, to: lastDay).day ?? 0) + 1
        func back(_ date: Date) -> Date { calendar.date(byAdding: .day, value: -days, to: date) ?? date }
        return DateInterval(start: back(start), end: back(end))
    }

    /// The bars of charts over time: by hour for one day, by day up to a month (Last month included), by week up to
    /// six months, by month beyond.
    public func bucket(now: Date, calendar: Calendar = .current) -> Calendar.Component {
        guard let (start, _, lastDay) = bounds(now: now, calendar: calendar) else { return .month }
        func monthsBack(_ months: Int) -> Date { calendar.date(byAdding: .month, value: -months, to: lastDay) ?? lastDay }
        return start >= lastDay ? .hour : start >= monthsBack(1) ? .day : start >= monthsBack(6) ? .weekOfYear : .month
    }

    /// The days Custom… opens with: the custom range, or the period's first day to now (today alone for All history).
    public func days(now: Date, calendar: Calendar = .current) -> (from: Date, through: Date) {
        if case .custom(let from, let through) = self { return (from, through) }
        return (range(now: now, calendar: calendar)?.start ?? calendar.startOfDay(for: now), now)
    }

    /// The menu's text: the period's title, or "12 Nov – 16 Nov 2026" ("16 Nov 2026" for one day).
    public func title(calendar: Calendar = .current) -> String {
        switch self {
        case .preset(let period):
            return period.title
        case .custom(let from, let through):
            let day = DateFormatter.english("d MMM", calendar), dayAndYear = DateFormatter.english("d MMM yyyy", calendar)
            if calendar.isDate(from, inSameDayAs: through) { return dayAndYear.string(from: through) }
            let first = calendar.isDate(from, equalTo: through, toGranularity: .year) ? day : dayAndYear
            return "\(first.string(from: from)) – \(dayAndYear.string(from: through))"
        }
    }

    /// The first moment, the last moment and the start of the last day; nil for all history.
    private func bounds(now: Date, calendar: Calendar) -> (start: Date, end: Date, lastDay: Date)? {
        switch self {
        case .preset(let period):
            return period.since(now, calendar: calendar).map { ($0, now, calendar.startOfDay(for: now)) }
        case .custom(let from, let through):
            let start = calendar.startOfDay(for: from), lastDay = calendar.startOfDay(for: through)
            let end = min(calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay, now)
            return (start, max(start, end), lastDay)
        }
    }
}
