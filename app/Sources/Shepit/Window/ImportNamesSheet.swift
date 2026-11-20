import AppKit
import SwiftUI
import ShepitCore

/// Import names (import names design §6): each person with the file's name, ticked when they have none; merges of two
/// people of one voice; the speakers nobody matched. The sheet is what the author edits; nothing changes before Apply names.
struct ImportNamesSheet: View {
    @State var sheet: NameImport.Sheet
    /// The meeting's people as the page shows them, for their colours and initials.
    let people: [MeetingPage.PersonRow]
    let suggestions: [String]
    let apply: (NameImport.Sheet) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let clashes = sheet.clashes
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Import names").font(.headline)
                Text(sheet.subtitle).font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(spacing: 0) {
                        ForEach($sheet.rows, id: \.key) { $row in
                            if row.key != sheet.rows.first?.key { Divider().padding(.leading, 46) }
                            personRow($row, clash: clashes.contains(row.key))
                        }
                    }
                    .boxed()
                    ForEach($sheet.merges, id: \.person) { $merge in
                        Toggle(merge.text, isOn: $merge.ticked).toggleStyle(.checkbox)
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
                    apply(sheet)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!sheet.canApply)
            }
        }
        .padding(20)
        .frame(width: 600)
    }

    private func personRow(_ row: Binding<NameImport.Row>, clash: Bool) -> some View {
        let index = people.firstIndex { $0.key == row.wrappedValue.key }
        return HStack(spacing: 10) {
            Avatar(initials: index.map { people[$0].initials } ?? "", color: Avatar.color(index ?? 0))
            Text(row.wrappedValue.label).lineLimit(1).frame(width: 130, alignment: .leading)
            if row.wrappedValue.alreadyNamed {
                Text("already named").foregroundStyle(.secondary)
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    let edit = { (typed: String) in row.wrappedValue.name = typed }
                    NameField(text: row.wrappedValue.name, placeholder: "Name", suggestions: suggestions, cancels: 0, commit: edit, changed: edit)
                    if clash { Text("Another person here is called \(row.wrappedValue.name).").font(.caption).foregroundStyle(.red) }
                }
                .frame(width: 200)
                Spacer()
                if let share = row.wrappedValue.share {
                    Text("\(Int((share * 100).rounded()))% of their time").foregroundStyle(.secondary).monospacedDigit().fixedSize()
                }
                Toggle("", isOn: row.ticked).toggleStyle(.checkbox).labelsHidden()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}
