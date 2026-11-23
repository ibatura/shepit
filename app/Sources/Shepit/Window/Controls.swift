import SwiftUI
import ShepitCore

/// A picker over a setting with a fixed list (`Settings.modes`, `.languages`, `.themes`).
struct ChoicePicker: View {
    let title: String
    let choices: [ShepitCore.Settings.Choice]
    let selection: Binding<String>

    var body: some View {
        Picker(title, selection: selection) {
            ForEach(choices, id: \.value) { Text($0.title).tag($0.value) }
        }
    }
}

/// A number setting as a pop-up menu of set values, not a − + stepper (the author, 2026-11-23); a value from the file
/// that is none of them is among them too.
struct NumberMenu: View {
    let title: String
    let values: [Int]
    let selection: Binding<Int>
    let text: (Int) -> String

    var body: some View {
        Picker(title, selection: selection) {
            ForEach(Self.values(values, current: selection.wrappedValue), id: \.self) { Text(text($0)).tag($0) }
        }
    }

    static func values(_ values: [Int], current: Int) -> [Int] { Set(values + [current]).sorted() }
}

/// A control with the README's one-line hint under it.
struct Hinted<Content: View>: View {
    let hint: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            content
            Text(hint).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A text setting that looks editable and is saved on purpose (the author, 2026-11-23): a bordered field, with Save
/// while the text differs from the saved one. Enter saves too, Esc puts the saved text back; clicking elsewhere keeps
/// the draft and saves nothing, and so does leaving the page (`SettingDrafts`).
struct SettingField: View {
    let saved: String
    let drafts: SettingDrafts
    /// Where its draft is kept while the page is not shown.
    let keep: String
    var prompt = ""
    /// `.vertical` grows to a few lines, for a paragraph.
    var axis = Axis.horizontal
    /// A draft it refuses keeps Save greyed.
    var canSave: (String) -> Bool = { _ in true }
    /// Each edit, for a caller that shows something from the draft.
    var edited: (String) -> Void = { _ in }
    let save: (String) -> Void
    @State private var draft = ""

    var body: some View {
        HStack {
            TextField(prompt, text: $draft, prompt: Text(prompt), axis: axis)
                .lineLimit(axis == .vertical ? 3...8 : 1...1)
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .onSubmit(commit)
                .onExitCommand { draft = saved }
            if draft != saved {
                Button("Save", action: commit).disabled(!canSave(draft))
            }
        }
        .onAppear { draft = drafts.draft(keep, saved: saved) ?? saved }
        .onChange(of: saved) { draft = $1 }
        .onChange(of: draft) {
            drafts.keep(keep, saved: saved, draft: $1)
            edited($1)
        }
    }

    private func commit() {
        if draft != saved, canSave(draft) { save(draft) }
    }
}

/// Unsaved drafts of text settings while Shepit runs (`SettingsModel.drafts`): a page left and opened again shows them
/// with Save, as a draft is saved only on purpose. One comes back only while the text it was typed over is still saved.
@MainActor final class SettingDrafts {
    private var drafts: [String: (saved: String, draft: String)] = [:]

    func draft(_ key: String, saved: String) -> String? {
        drafts[key].flatMap { $0.saved == saved ? $0.draft : nil }
    }

    func keep(_ key: String, saved: String, draft: String) {
        drafts[key] = draft == saved ? nil : (saved, draft)
    }
}

/// A small caption over a block, as in the mockups ("People", "Transcript (read only)").
struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary).padding(.top, 6)
    }
}

/// A name shown as a title and renamed on purpose (a meeting, a person): a click on it or on the pencil opens a field
/// with Save and Cancel. Enter saves, Esc cancels; clicking elsewhere keeps the field open and saves nothing.
struct EditableTitle: View {
    let text: String
    /// Shown for no name (a meeting without one: "Teams call").
    var placeholder = ""
    let save: (String) -> Void
    @State private var editing = false
    @State private var typed = ""
    @FocusState private var focused: Bool

    var body: some View {
        if editing {
            HStack(spacing: 8) {
                TextField(placeholder, text: $typed)
                    .textFieldStyle(.roundedBorder).font(.title2)
                    .focused($focused)
                    .onSubmit(commit)
                    .onExitCommand { editing = false }
                    .onAppear {
                        typed = text
                        focused = true
                    }
                Button("Save", action: commit)
                Button("Cancel") { editing = false }
            }
        } else {
            HStack(spacing: 6) {
                Text(text.isEmpty ? placeholder : text).font(.title2).fontWeight(.semibold).lineLimit(2)
                    .onTapGesture { editing = true }
                Button { editing = true } label: { Image(systemName: "pencil") }
                    .buttonStyle(.borderless).help("Rename").accessibilityLabel("Rename")
            }
        }
    }

    private func commit() {
        editing = false
        if typed != text { save(typed) }
    }
}

/// A person's initials on their colour (mockups 2 and 6).
struct Avatar: View {
    let initials: String
    let color: Color

    private static let colors: [Color] = [.green, .purple, .orange, .cyan, .pink, .blue, .yellow, .indigo, .mint, .brown]

    /// The colour of the person at `index`, repeating after ten.
    static func color(_ index: Int) -> Color { colors[index % colors.count] }

    var body: some View {
        Text(initials).font(.caption2).fontWeight(.bold).foregroundStyle(.white)
            .frame(width: 26, height: 26).background(color, in: Circle())
    }
}

extension View {
    /// The rounded box a block of rows sits in (mockups 2 and 6).
    func boxed() -> some View {
        background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
    }
}
