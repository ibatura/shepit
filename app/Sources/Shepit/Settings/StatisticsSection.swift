import Charts
import SwiftUI
import ShepitCore

/// Settings → Statistics (`05-statistics.md` §2). All numbers come from the pure `Stats` functions.
struct StatisticsSection: View {
    let model: SettingsModel
    let actions: SettingsActions
    @Binding var section: SettingsModel.Section?
    @State private var period = StatsPeriod.week
    @State private var hovered: Date?

    var body: some View {
        let now = Date()
        let range = Stats.range(period, now: now)
        let rows = actions.statistics(range)
        let previousRange = range.flatMap { Stats.previous($0, period) }
        let previous = previousRange.map(actions.statistics)
        let meetings = actions.meetingStatistics(range)
        let previousMeetings = previousRange.map(actions.meetingStatistics)
        let wpm = model.settings.typingSpeedWpm

        Section {
            Picker("Period", selection: $period) {
                Text("Day").tag(StatsPeriod.day)
                Text("Week").tag(StatsPeriod.week)
                Text("Month").tag(StatsPeriod.month)
                Text("Year").tag(StatsPeriod.year)
                Text("All").tag(StatsPeriod.all)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            HStack(alignment: .top, spacing: 12) {
                Tile(title: "Dictations", value: "\(Stats.dictations(rows))",
                     change: previous.map { change(Double(Stats.dictations(rows)), Double(Stats.dictations($0))) } ?? nil)
                Tile(title: "Words dictated", value: "\(Stats.words(rows))",
                     change: previous.map { change(Double(Stats.words(rows)), Double(Stats.words($0))) } ?? nil)
                Tile(title: "Time saved", value: duration(Stats.timeSaved(rows, wpm: wpm)),
                     change: previous.map { change(Stats.timeSaved(rows, wpm: wpm), Stats.timeSaved($0, wpm: wpm)) } ?? nil)
                Tile(title: "Meetings · hours", value: "\(Stats.meetingCount(meetings)) · \(hours(Stats.meetingHours(meetings)))",
                     change: previousMeetings.map { change(Stats.meetingHours(meetings), Stats.meetingHours($0)) } ?? nil)
            }
            HStack(spacing: 4) {
                Text("Time saved = words ÷ your typing speed − (speaking + waiting), never below zero per dictation.")
                Button("Typing speed: \(wpm) wpm") { section = .historyPrivacy }.buttonStyle(.link)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        if !meetings.isEmpty || Stats.dictations(rows) > 0 {
            wordsChart(rows, meetings)
        }
        if Stats.dictations(rows) == 0 {
            Section { Text("No dictations in this period yet.").foregroundStyle(.secondary) }
        } else {
            speedTable(rows)
            appsChart(rows)
            heatmap(rows)
            quality(rows)
        }
    }

    // MARK: charts

    /// Stacked bars, dictation below and meetings on top, with a 2 pt gap between the segments.
    private func wordsChart(_ rows: [DictationRow], _ meetings: [MeetingRecord]) -> some View {
        let unit = Stats.bucketUnit(period)
        let buckets = Stats.wordsPerBucket(rows, meetings: meetings, period: period)
        return Section("Words per \(unitName(unit))") {
            Chart {
                ForEach(buckets, id: \.start) { bucket in
                    if bucket.dictation > 0 {
                        BarMark(x: .value("Time", bucket.start, unit: unit), yStart: .value("Words", 0), yEnd: .value("Words", bucket.dictation))
                            .foregroundStyle(by: .value("Source", Self.dictationSeries))
                            .clipShape(UnevenRoundedRectangle(topLeadingRadius: bucket.meetings > 0 ? 0 : 4,
                                                              topTrailingRadius: bucket.meetings > 0 ? 0 : 4))
                    }
                    if bucket.meetings > 0 {
                        BarMark(x: .value("Time", bucket.start, unit: unit), yStart: .value("Words", bucket.dictation),
                                yEnd: .value("Words", bucket.dictation + bucket.meetings))
                            .foregroundStyle(by: .value("Source", Self.meetingSeries))
                            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
                            .offset(yStart: bucket.dictation > 0 ? -2 : 0) // 2 pt gap between the segments
                    }
                }
                if let hovered, let bucket = buckets.first(where: { Calendar.current.isDate($0.start, equalTo: hovered, toGranularity: unit) }) {
                    RuleMark(x: .value("Time", bucket.start, unit: unit))
                        .foregroundStyle(.secondary.opacity(0.3))
                        // Beside the rule, inside the plot: above it the Form section clipped the tooltip.
                        .annotation(position: .trailing, alignment: .top, spacing: 6,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bucket.start.formatted(dateFormat(unit))).foregroundStyle(.secondary)
                                if bucket.dictation > 0 { Text("Dictation: \(bucket.dictation) words") }
                                if bucket.meetings > 0 { Text("Meetings: \(bucket.meetings) words") }
                            }
                            .font(.caption).padding(6)
                            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                        }
                }
            }
            .chartForegroundStyleScale([Self.dictationSeries: Self.dictationColor, Self.meetingSeries: Self.meetingColor])
            .chartLegend(position: .top, alignment: .leading)
            .chartXSelection(value: $hovered)
            .chartYAxis { AxisMarks { AxisGridLine().foregroundStyle(.quaternary); AxisValueLabel() } }
            .frame(height: 180)
        }
    }

    private static let dictationSeries = "Dictation"
    private static let meetingSeries = "Meetings"
    // Categorical slots 1 and 2 (blue, orange), each stepped for its mode; checked with the dataviz validator.
    private static let dictationColor = Color(nsColor: NSColor(name: nil) { $0.isDark ? NSColor(hex: 0x3987E5) : NSColor(hex: 0x2A78D6) })
    private static let meetingColor = Color(nsColor: NSColor(name: nil) { $0.isDark ? NSColor(hex: 0xD95926) : NSColor(hex: 0xEB6834) })

    /// Two measures on different scales, so a table rather than a dual-axis chart.
    private func speedTable(_ rows: [DictationRow]) -> some View {
        Section("Speed by engine") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Engine")
                    Text("Median wait after stop")
                    Text("Per 10 s of audio")
                }
                .font(.caption).foregroundStyle(.secondary)
                ForEach(Stats.speedByEngine(rows), id: \.self) { speed in
                    GridRow {
                        Text(MenuModel.engineTitle(EngineChoice(engine: EngineID(rawValue: speed.engine) ?? .whispercpp, model: speed.model)))
                        Text(String(format: "%.1f s", speed.medianWait)).monospacedDigit()
                        Text(String(format: "%.2f s", speed.medianWaitPer10s)).monospacedDigit()
                    }
                }
            }
        }
    }

    private func appsChart(_ rows: [DictationRow]) -> some View {
        let apps = Stats.topApps(rows)
        let top = Double(max(apps.map(\.count).max() ?? 1, 1))
        return Section("Pasted into") {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                ForEach(apps, id: \.name) { app in
                    GridRow {
                        Text(app.name).lineLimit(1).frame(width: 150, alignment: .leading)
                        GeometryReader { geometry in
                            HStack(spacing: 6) {
                                UnevenRoundedRectangle(bottomTrailingRadius: 4, topTrailingRadius: 4)
                                    .fill(Color.accentColor)
                                    .frame(width: max(2, (geometry.size.width - 40) * Double(app.count) / top))
                                Text("\(app.count)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                        .frame(height: 14)
                    }
                }
            }
        }
    }

    private func heatmap(_ rows: [DictationRow]) -> some View {
        let grid = Stats.heatmap(rows)
        let top = Double(max(grid.joined().max() ?? 1, 1))
        let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        return Section("When you dictate") {
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                ForEach(0..<7, id: \.self) { day in
                    GridRow {
                        Text(days[day]).font(.caption).foregroundStyle(.secondary).frame(width: 32, alignment: .leading)
                        ForEach(0..<24, id: \.self) { hour in
                            let count = grid[day][hour]
                            RoundedRectangle(cornerRadius: 2)
                                .fill(count == 0 ? Color.secondary.opacity(0.1) : Color.accentColor.opacity(0.2 + 0.8 * Double(count) / top))
                                .frame(height: 16)
                                .help("\(days[day]) \(hour):00 — \(count) dictation\(count == 1 ? "" : "s")")
                        }
                    }
                }
                GridRow {
                    Text("")
                    ForEach(0..<24, id: \.self) { hour in
                        Text(hour % 6 == 0 ? "\(hour)" : "").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Text("Darker = more dictations at that hour, in your local time when you dictated. Hover a cell for the count.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func quality(_ rows: [DictationRow]) -> some View {
        let q = Stats.quality(rows)
        return Section("Quality signals") {
            LabeledContent("Cancelled", value: percent(q.cancelledShare))
            LabeledContent("Failed", value: percent(q.failedShare))
            LabeledContent("Nothing recognized", value: percent(q.emptyShare))
            LabeledContent("Languages detected", value: q.detectedLanguages.isEmpty ? "—"
                : q.detectedLanguages.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
            LabeledContent("Dictionary fixes", value: "\(q.fixes)")
            if !q.topTerms.isEmpty {
                LabeledContent("Most corrected", value: q.topTerms.map { "\($0.term) ×\($0.count)" }.joined(separator: ", "))
            }
        }
    }

    // MARK: formatting

    private func change(_ current: Double, _ previous: Double) -> String? {
        Stats.delta(current: current, previous: previous).map { ($0 >= 0 ? "▲ " : "▼ ") + percent(abs($0)) + " vs previous" }
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    private func hours(_ value: Double) -> String {
        value == 0 ? "0 h" : value < 10 ? String(format: "%.1f h", value) : "\(Int(value.rounded())) h"
    }

    private func duration(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        if minutes >= 60 { return "\(minutes / 60) h \(minutes % 60) min" }
        return minutes > 0 ? "\(minutes) min" : "\(Int(seconds)) s"
    }

    private func unitName(_ unit: Calendar.Component) -> String {
        switch unit {
        case .hour: "hour"
        case .day: "day"
        default: "month"
        }
    }

    private func dateFormat(_ unit: Calendar.Component) -> Date.FormatStyle {
        switch unit {
        case .hour: .dateTime.hour()
        case .day: .dateTime.day().month(.abbreviated)
        default: .dateTime.month(.abbreviated).year()
        }
    }
}

/// A headline number with its change against the previous period (text ink, not status colors).
private struct Tile: View {
    let title: String
    let value: String
    let change: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
            Text(change ?? " ").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
