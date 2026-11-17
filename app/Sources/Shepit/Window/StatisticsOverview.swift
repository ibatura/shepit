import Charts
import SwiftUI
import ShepitCore

/// Statistics → Overview (statistics design §5.1, mockup 7): four tiles with their change against the previous period,
/// and words per bucket, dictation and meetings stacked.
struct StatisticsOverview: View {
    let page: StatisticsPage.Overview
    let unit: Calendar.Component
    /// Settings → History and privacy, where the typing speed is.
    let openTypingSpeed: () -> Void

    var body: some View {
        Section { StatTiles(tiles: page.tiles, open: openTypingSpeed) }
        Section {
            if page.words.isEmpty {
                Text("No dictations or meetings in this period").foregroundStyle(.secondary)
            } else {
                WordsChart(buckets: page.words, unit: unit)
            }
        } header: {
            Text("Words per \(page.bucket)")
        } footer: {
            StatCaption("Time saved = words ÷ your typing speed − (speaking + waiting), never below zero per dictation.")
        }
    }
}

/// Words per bucket as stacked bars, dictation below and meetings on top, with the hover tooltip. Its own view, so the
/// pointer redraws the chart and not the tiles.
private struct WordsChart: View {
    let buckets: [Stats.WordsBucket]
    let unit: Calendar.Component
    @State private var hovered: Date?

    var body: some View {
        Chart {
            ForEach(buckets, id: \.start) { bucket in
                if bucket.dictation > 0 {
                    BarMark(x: .value("Time", bucket.start, unit: unit), yStart: .value("Words", 0), yEnd: .value("Words", bucket.dictation))
                        .foregroundStyle(by: .value("Source", Self.dictation))
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: bucket.meetings > 0 ? 0 : 4,
                                                          topTrailingRadius: bucket.meetings > 0 ? 0 : 4))
                }
                if bucket.meetings > 0 {
                    BarMark(x: .value("Time", bucket.start, unit: unit), yStart: .value("Words", bucket.dictation),
                            yEnd: .value("Words", bucket.dictation + bucket.meetings))
                        .foregroundStyle(by: .value("Source", Self.meetings))
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
                        ChartTooltip(title: StatisticsPage.title(bucket.start, unit),
                                     lines: [bucket.dictation > 0 ? "Dictation: \(bucket.dictation) words" : nil,
                                             bucket.meetings > 0 ? "Meetings: \(bucket.meetings) words" : nil].compactMap { $0 })
                    }
            }
        }
        .chartForegroundStyleScale([Self.dictation: StatsPalette.series[0], Self.meetings: StatsPalette.series[1]])
        .chartLegend(position: .top, alignment: .leading)
        .chartXSelection(value: $hovered)
        .chartYAxis { AxisMarks { AxisGridLine().foregroundStyle(.quaternary); AxisValueLabel() } }
        .frame(height: 200)
    }

    private static let dictation = "Dictation"
    private static let meetings = "Meetings"
}
