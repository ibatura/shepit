import Charts
import SwiftUI
import ShepitCore

/// The window's Statistics section (statistics design §5, mockup 7): Overview, Dictation and Meetings switched at the
/// top, the period menu at the right, and the chosen view under them, drawn from the model's pages.
struct StatisticsView: View {
    @Bindable var model: StatisticsModel
    let settings: SettingsModel
    /// Settings → History and privacy: collecting statistics and the typing speed.
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("View", selection: $model.tab) {
                    ForEach(StatisticsModel.Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                PeriodMenu(model: model)
            }
            .padding(8)
            Divider()
            Form {
                if !settings.settings.collectStats { off }
                let pages = model.pages
                switch model.tab {
                case .overview: StatisticsOverview(page: pages.overview, unit: pages.unit, openTypingSpeed: openSettings)
                case .dictation: StatisticsDictation(page: pages.dictation, unit: pages.unit)
                case .meetings: StatisticsMeetings(page: pages.meetings)
                }
            }
            .formStyle(.grouped)
        }
        .onAppear { model.reload() }
    }

    /// Numbers already stored are still shown under it (spec §5.4).
    private var off: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Statistics are off").fontWeight(.semibold)
                    Text("Nothing new is recorded. What was recorded before is shown below.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open History and privacy", action: openSettings)
            }
        }
    }
}

/// The period's title as a menu: Dictations' periods and, below a separator, Custom… with its popover.
private struct PeriodMenu: View {
    @Bindable var model: StatisticsModel
    @State private var custom = false

    var body: some View {
        Menu(model.period.title()) {
            Picker("Period", selection: Binding<Period?>(
                get: { if case .preset(let period) = model.period { period } else { nil } },
                set: { $0.map { model.period = .preset($0) } })) {
                ForEach(Period.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            Divider()
            Button("Custom…") { custom = true }
        }
        .fixedSize()
        .popover(isPresented: $custom, arrowEdge: .bottom) {
            CustomRange(from: model.customDays.from, through: model.customDays.through) { from, through in
                model.period = .custom(from: from, through: through)
                custom = false
            }
        }
    }
}

/// Whole days, both included: the start in one calendar and the end in another, as macOS has no range picker (spec
/// §11). The end can't be before the start or after today.
private struct CustomRange: View {
    @State var from: Date
    @State var through: Date
    let show: (Date, Date) -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            HStack(alignment: .top, spacing: 20) {
                calendar("From", $from, in: Date.distantPast...through)
                calendar("To", $through, in: from...max(from, Date()))
            }
            Button("Show") { show(from, through) }.keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    private func calendar(_ title: String, _ date: Binding<Date>, in range: ClosedRange<Date>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            DatePicker(title, selection: date, in: range, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
        }
    }
}

/// Headline numbers side by side with their change against the previous period, in text (spec §3: colour carries no
/// meaning alone). A tile's link (Time saved's "at 40 wpm") calls `open`.
struct StatTiles: View {
    let tiles: [StatisticsPage.Tile]
    var open: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { index, tile in
                if index > 0 { Divider() }
                VStack(alignment: .leading, spacing: 4) {
                    Text(tile.title).font(.caption).foregroundStyle(.secondary)
                    Text(tile.value).font(.title2.weight(.semibold)).monospacedDigit()
                    Text(tile.change ?? " ").font(.caption).foregroundStyle(.secondary)
                    if let link = tile.link { Button(link, action: open).buttonStyle(.link).font(.caption) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .fixedSize(horizontal: false, vertical: true) // the dividers as tall as the tallest tile
    }
}

/// Horizontal bars, a row each: the name at the left, the bar, and its text after it. The names are a column of their
/// own: in a grouped Form the chart's leading axis drew them under the bars. A bar is known by its row, as two can
/// share a name (an app called "Other" beside the Other bar).
struct StatBars: View {
    let bars: [StatisticsPage.Bar]
    let color: Color
    private static let row: CGFloat = 24

    var body: some View {
        let top = bars.map(\.value).max() ?? 0
        let rows = Array(bars.enumerated())
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows, id: \.offset) { Text($0.element.name).lineLimit(1).frame(height: Self.row) }
            }
            .frame(width: 150, alignment: .leading)
            Chart(rows, id: \.offset) { index, bar in
                BarMark(x: .value("Count", bar.value), y: .value("Row", String(index)), height: .fixed(14))
                    .foregroundStyle(color)
                    .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 4, topTrailingRadius: 4))
                    .annotation(position: .trailing, alignment: .leading, spacing: 6) {
                        Text(bar.label).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
            }
            .chartXScale(domain: 0...max(top * 1.25, 1)) // room for the text after the longest bar
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: CGFloat(bars.count) * Self.row)
        }
    }
}

/// The small grey text under a block.
struct StatCaption: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }
}

/// The box beside a chart's hover rule: the bucket, then a line per value.
struct ChartTooltip: View {
    let title: String
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(.secondary)
            ForEach(lines, id: \.self) { Text($0) }
        }
        .font(.caption).padding(6)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
    }
}

/// Categorical slots 1–4 of the charts (blue, orange, aqua, yellow), each stepped for its mode: dictation and meetings
/// in Words per day and the bars, the lines of Speed over time. Checked with the dataviz validator on the grouped sections' surface
/// (#f5f5f5 light, #262626 dark): all pass; in light orange, aqua and yellow are under 3:1, so each chart has a
/// legend and a tooltip, and the speed table lists the numbers.
enum StatsPalette {
    static let series = [(0x2A78D6, 0x3987E5), (0xEB6834, 0xD95926), (0x1BAF7A, 0x199E70), (0xEDA100, 0xC98500)].map { light, dark in
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light) })
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
