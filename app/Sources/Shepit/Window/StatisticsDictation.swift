import Charts
import SwiftUI
import ShepitCore

/// Statistics → Dictation (statistics design §5.2): speed and speed over time, the apps text went to, when you dictate,
/// languages, the dictionary and failures.
struct StatisticsDictation: View {
    let page: StatisticsPage.Dictation
    /// The bars of Speed over time.
    let unit: Calendar.Component

    var body: some View {
        if page.dictations > 0 {
            speed
            speedOverTime
            Section("Pasted into") { StatBars(bars: page.apps, color: StatsPalette.series[0]) }
            heatmap
            Section {
                if page.languages.isEmpty { Text("No engine reported a language in this period").foregroundStyle(.secondary) }
                lines(page.languages)
            } header: {
                Text("Languages")
            } footer: {
                StatCaption("With Ukrainian or English chosen, that language counts; Auto-detect counts what it heard.")
            }
            Section("Dictionary") { lines(page.fixes) }
        }
        if page.attempts == 0 {
            Section { Text("No dictations in this period").foregroundStyle(.secondary) }
        } else {
            // Also when nothing in the period worked.
            Section { lines(page.failures) } header: { Text("Failures") } footer: { StatCaption(page.attemptsNote) }
        }
    }

    private func lines(_ lines: [StatisticsPage.Line]) -> some View {
        ForEach(lines, id: \.name) { LabeledContent($0.name, value: $0.value) }
    }

    /// Two measures on different scales, so a table rather than a dual-axis chart.
    private var speed: some View {
        Section("Speed") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Engine")
                    Text("Median wait after stop")
                    Text("Per 10 s of audio")
                }
                .font(.caption).foregroundStyle(.secondary)
                ForEach(page.speed, id: \.engine) { speed in
                    GridRow {
                        Text(speed.engine)
                        Text(speed.wait).monospacedDigit()
                        Text(speed.per10s).monospacedDigit()
                    }
                }
            }
        }
    }

    private var speedOverTime: some View {
        Section {
            if page.points.isEmpty {
                Text("Not enough dictations: a point needs 3 of one engine in a \(page.bucket).").foregroundStyle(.secondary)
            } else {
                SpeedChart(lines: page.lines, points: page.points, unit: unit)
            }
        } header: {
            Text("Speed over time")
        } footer: {
            StatCaption("The median wait per 10 s of audio, per \(page.bucket). A point needs 3 dictations of that engine; the 4 engines used most get a line.")
        }
    }

    private var heatmap: some View {
        let grid = page.heatmap
        let top = Double(max(grid.joined().max() ?? 1, 1))
        let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        return Section {
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                ForEach(0..<7, id: \.self) { day in
                    GridRow {
                        Text(days[day]).font(.caption).foregroundStyle(.secondary).frame(width: 32, alignment: .leading)
                        ForEach(0..<24, id: \.self) { hour in
                            let count = grid[day][hour]
                            RoundedRectangle(cornerRadius: 2)
                                .fill(count == 0 ? Color.secondary.opacity(0.1) : StatsPalette.series[0].opacity(0.2 + 0.8 * Double(count) / top))
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
        } header: {
            Text("When you dictate")
        } footer: {
            StatCaption("Stronger colour = more dictations at that hour, in your local time when you dictated. Hover a cell for the count.")
        }
    }
}

/// A line per engine and model, with a point per bucket and the values of a bucket on hover.
private struct SpeedChart: View {
    let lines: [String]
    let points: [StatisticsPage.SpeedPoint]
    let unit: Calendar.Component
    @State private var hovered: Date?

    var body: some View {
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("Time", point.start, unit: unit), y: .value("Seconds", point.seconds))
                    .foregroundStyle(by: .value("Engine", point.line))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                PointMark(x: .value("Time", point.start, unit: unit), y: .value("Seconds", point.seconds))
                    .foregroundStyle(by: .value("Engine", point.line))
                    .symbol(by: .value("Engine", point.line)) // a shape as well as a colour for each line
                    .symbolSize(64)
            }
            if let hovered, let start = points.first(where: { Calendar.current.isDate($0.start, equalTo: hovered, toGranularity: unit) })?.start {
                RuleMark(x: .value("Time", start, unit: unit))
                    .foregroundStyle(.secondary.opacity(0.3))
                    .annotation(position: .trailing, alignment: .top, spacing: 6,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        ChartTooltip(title: StatisticsPage.title(start, unit),
                                     lines: points.filter { $0.start == start }.map { "\($0.line): \($0.label)" })
                    }
            }
        }
        // In the page's order (engine, then model), so a period with the same engines keeps their colours.
        .chartForegroundStyleScale(domain: lines, range: Array(StatsPalette.series.prefix(lines.count)))
        .chartLegend(position: .top, alignment: .leading)
        .chartXSelection(value: $hovered)
        .chartYAxis { AxisMarks { value in
            AxisGridLine().foregroundStyle(.quaternary)
            AxisValueLabel { if let seconds = value.as(Double.self) { Text(String(format: "%g s", seconds)) } }
        } }
        .frame(height: 180)
    }
}
