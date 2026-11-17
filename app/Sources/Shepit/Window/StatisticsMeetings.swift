import SwiftUI
import ShepitCore

/// Statistics → Meetings (statistics design §5.3): tiles, meetings by app, their length, speaker detection and how the
/// call offers ended. From `stats.sqlite` only, so notes added with Add notes… don't count.
struct StatisticsMeetings: View {
    let page: StatisticsPage.Meetings

    var body: some View {
        Section { StatTiles(tiles: page.tiles) } footer: {
            StatCaption("Your share: your words of all words in the meetings. People: the voices speaker detection told apart, and you.")
        }
        if page.count == 0 {
            Section { Text("No meetings in this period").foregroundStyle(.secondary) }
        } else {
            Section("By app") { StatBars(bars: page.apps, color: StatsPalette.series[1]) }
            Section("Length") {
                ForEach(page.length, id: \.name) { LabeledContent($0.name, value: $0.value) }
                StatBars(bars: page.lengths, color: StatsPalette.series[1])
            }
            Section {
                ForEach(page.detection, id: \.name) { LabeledContent($0.name, value: $0.value) }
            } header: {
                Text("Speaker detection")
            } footer: {
                StatCaption("It runs after Stop on the call's audio. A failed chunk is a piece of audio that wasn't recognized.")
            }
        }
        if let offers = page.offers { self.offers(offers) }
    }

    /// Outcomes down, all apps and each app with offers across.
    private func offers(_ offers: StatisticsPage.Offers) -> some View {
        Section {
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 6) {
                GridRow {
                    Text("")
                    ForEach(offers.columns, id: \.self) { Text($0).gridColumnAlignment(.trailing) }
                }
                .font(.caption).foregroundStyle(.secondary)
                ForEach(offers.rows, id: \.outcome) { row in
                    GridRow {
                        Text(row.outcome)
                        ForEach(Array(row.counts.enumerated()), id: \.offset) { Text("\($0.element)").monospacedDigit() }
                    }
                }
            }
        } header: {
            Text("Call offers")
        } footer: {
            StatCaption("How the panel offering a transcript ended when a call started.")
        }
    }
}
