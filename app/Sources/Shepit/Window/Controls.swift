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

/// A small caption over a block, as in the mockups ("People", "Transcript (read only)").
struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary).padding(.top, 6)
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
