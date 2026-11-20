import AppKit
import SwiftUI
import ShepitCore

/// Import names (import names design §6): each person with the file's name, ticked when they have none; merges of two
/// people of one voice; the speakers nobody matched. Nothing changes before Apply names.
struct ImportNamesSheet: View {
    let sheet: NameImport.Sheet
    /// The meeting's people as the page shows them, for their colours and initials.
    let people: [MeetingPage.PersonRow]
    let suggestions: [String]
    let apply: (_ merges: [NameImport.Merge], _ typed: [String: String]) -> Void
    @State private var names: [String: String]
    @State private var ticked: Set<String>
    @State private var merging: Set<String>
    @Environment(\.dismiss) private var dismiss

    init(sheet: NameImport.Sheet, people: [MeetingPage.PersonRow], suggestions: [String],
         apply: @escaping ([NameImport.Merge], [String: String]) -> Void) {
        self.sheet = sheet
        self.people = people
        self.suggestions = suggestions
        self.apply = apply
        _names = State(initialValue: Dictionary(uniqueKeysWithValues: sheet.rows.map { ($0.key, $0.name) }))
        _ticked = State(initialValue: Set(sheet.rows.filter(\.ticked).map(\.key)))
        _merging = State(initialValue: Set(sheet.merges.map(\.person)))
    }

    private var chosen: [String: String] { names.filter { ticked.contains($0.key) } }

    var body: some View {
        let clashes = sheet.clashes(chosen)
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Import names").font(.headline)
                Text(sheet.subtitle).font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(spacing: 0) {
                        ForEach(Array(sheet.rows.enumerated()), id: \.element.key) { index, row in
                            if index > 0 { Divider().padding(.leading, 46) }
                            personRow(row, clash: clashes.contains(row.key))
                        }
                    }
                    .boxed()
                    ForEach(sheet.merges, id: \.person) { merge in
                        Toggle(merge.text, isOn: toggle(merge.person, in: $merging)).toggleStyle(.checkbox)
                    }
                    if !sheet.others.isEmpty {
                        Text("Also in the file: \(sheet.others.joined(separator: ", "))").font(.callout).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 420)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Apply names") {
                    // A name typed just before the click is saved when its field loses focus: after that, on the next turn.
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    DispatchQueue.main.async {
                        guard sheet.clashes(chosen).isEmpty else { return }
                        apply(sheet.merges.filter { merging.contains($0.person) }, chosen)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled((ticked.isEmpty && merging.isEmpty) || !clashes.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 600)
    }

    private func personRow(_ row: NameImport.Row, clash: Bool) -> some View {
        let index = people.firstIndex { $0.key == row.key }
        return HStack(spacing: 10) {
            Avatar(initials: index.map { people[$0].initials } ?? "", color: Avatar.color(index ?? 0))
            Text(row.label).lineLimit(1).frame(width: 130, alignment: .leading)
            if row.alreadyNamed {
                Text("already named").foregroundStyle(.secondary)
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    NameField(text: names[row.key] ?? "", placeholder: "Name", suggestions: suggestions, cancels: 0) { typed in
                        names[row.key] = typed
                        if MeetingPage.name(typed) == nil { ticked.remove(row.key) } else { ticked.insert(row.key) }
                    }
                    if clash, let name = names[row.key] {
                        Text("Another person here is called \(name).").font(.caption).foregroundStyle(.red)
                    }
                }
                .frame(width: 200)
                Spacer()
                if let share = row.share {
                    Text("\(Int((share * 100).rounded()))% of their time").foregroundStyle(.secondary).monospacedDigit().fixedSize()
                }
                Toggle("", isOn: toggle(row.key, in: $ticked)).toggleStyle(.checkbox).labelsHidden()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func toggle(_ key: String, in set: Binding<Set<String>>) -> Binding<Bool> {
        Binding(get: { set.wrappedValue.contains(key) },
                set: { if $0 { set.wrappedValue.insert(key) } else { set.wrappedValue.remove(key) } })
    }
}
