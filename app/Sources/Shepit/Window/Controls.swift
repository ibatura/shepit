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
