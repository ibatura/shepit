import SwiftUI
import ShepitCore

/// The period's title as a menu, on the right of Dictations', Statistics' and People's bars (settings review design
/// §9): the presets and, below a separator, Custom… with its popover.
struct PeriodMenu: View {
    @Binding var period: StatsPeriod
    @State private var custom = false

    var body: some View {
        Menu(period.title()) {
            Picker("Period", selection: Binding<Period?>(
                get: { if case .preset(let preset) = period { preset } else { nil } },
                set: { $0.map { period = .preset($0) } })) {
                ForEach(Period.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            Divider()
            Button("Custom…") { custom = true }
        }
        .fixedSize()
        .popover(isPresented: $custom, arrowEdge: .bottom) {
            let days = period.days(now: Date())
            CustomRange(from: days.from, through: days.through) { from, through in
                period = .custom(from: from, through: through)
                custom = false
            }
        }
    }
}

/// Whole days, both included: the start in one calendar and the end in another, as macOS has no range picker
/// (statistics design §11). The end can't be before the start or after today.
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

extension UserDefaults {
    /// A section's remembered period: "<section>Period" holds a preset's name or "custom", with the custom days in
    /// "<section>From" and "<section>Through". Last month by default.
    func period(section: String) -> StatsPeriod {
        let saved = string(forKey: section + "Period")
        if saved == "custom", let from = object(forKey: section + "From") as? Date, let through = object(forKey: section + "Through") as? Date {
            return .custom(from: from, through: through)
        }
        return .preset(saved.flatMap(Period.init) ?? .month)
    }

    func set(_ period: StatsPeriod, section: String) {
        switch period {
        case .preset(let preset):
            set(preset.rawValue, forKey: section + "Period")
        case .custom(let from, let through):
            set("custom", forKey: section + "Period")
            set(from, forKey: section + "From")
            set(through, forKey: section + "Through")
        }
    }
}
