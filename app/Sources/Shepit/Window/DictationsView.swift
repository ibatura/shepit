import SwiftUI
import ShepitCore

/// The window's Dictations section (Dictations and Dictionary design §5, mockup 4): the history by day, read a page at a
/// time, with Copy, a click to open a long text, Delete…, and a bar with how long history is kept and Clear history….
struct DictationsView: View {
    @Bindable var model: DictationsModel
    let settings: SettingsModel
    let actions: WindowActions
    /// Settings → History and privacy.
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                PeriodMenu(period: $model.period)
            }
            .padding(8)
            Divider()
            if model.lines.isEmpty { empty } else { list }
            Divider()
            HStack {
                Button(DictationPage.kept(days: settings.settings.historyDays), action: openSettings).buttonStyle(.link)
                Spacer()
                Button("Clear history…") { actions.perform(.clearHistory) }
            }
            .padding(8)
        }
        .onAppear { model.reload() }
        .alert("Delete this dictation?", isPresented: Binding(get: { model.question != nil }, set: { if !$0 { model.question = nil } }),
               presenting: model.question) { entry in
            Button("Delete", role: .destructive) { model.delete(entry) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This cannot be undone.")
        }
        .alert("Could not delete the dictation", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK") {}
        } message: {
            Text(model.notice ?? "")
        }
    }

    @ViewBuilder private var empty: some View {
        if !settings.settings.saveHistory {
            ContentUnavailableView {
                Label("History is off", systemImage: WindowSection.dictations.symbol)
            } description: {
                Text("Turn on Save history to keep dictations here.")
            } actions: {
                Button("Open History and privacy", action: openSettings)
            }
        } else if model.period != .preset(.all) {
            ContentUnavailableView("No dictations in this period", systemImage: WindowSection.dictations.symbol,
                                   description: Text("Older ones are under a longer period above."))
        } else {
            ContentUnavailableView("No dictations yet", systemImage: WindowSection.dictations.symbol,
                                   description: Text("Every dictation is kept here, with the app it went to."))
        }
    }

    /// One flat `List` builds only the lines on screen. A grouped `Form` builds every row, so each row's `onAppear` asked
    /// for the next page and the whole history loaded at once (5000 entries: 103 s); day sections make the list build
    /// every row to count them (a page took 1 s at 5000 entries).
    private var list: some View {
        List(model.lines) { line in
            switch line {
            case .day(let title):
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.top, 8).listRowSeparator(.hidden)
            case .entry(let row):
                DictationRow(row: row, open: model.open.contains(row.entry.id), toggle: { model.toggle(row.entry.id) },
                             copy: { actions.perform(.copyText(row.entry.text)) }, delete: { model.question = row.entry })
                    .onAppear { model.appeared(row.entry.id) }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: false))
    }
}

/// The text (two lines and "…" until a click opens it), "14:02 · Slack · 7 words" and Copy.
private struct DictationRow: View {
    let row: DictationPage.Row
    let open: Bool
    let toggle: () -> Void
    let copy: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(row.entry.text)
                .lineLimit(open ? nil : 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: toggle)
            Text(row.detail).foregroundStyle(.secondary).monospacedDigit()
            Button("Copy", action: copy)
        }
        .contextMenu {
            Button("Copy", action: copy)
            Divider()
            Button("Delete…", action: delete)
        }
    }
}
