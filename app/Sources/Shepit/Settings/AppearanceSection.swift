import SwiftUI
import ShepitCore

/// Settings → Appearance (window shell design §6.1).
struct AppearanceSection: View {
    let model: SettingsModel

    var body: some View {
        Section {
            ChoicePicker(title: "Theme", choices: ShepitCore.Settings.themes, selection: model.binding("theme", \.theme))
            Hinted(hint: "The first dot follows macOS. If a colour doesn't show, restart Shepit") {
                LabeledContent("Accent colour") {
                    HStack(spacing: 8) {
                        ForEach(AccentColor.allCases, id: \.self) { color in
                            Button { model.set("accentColor", color.rawValue) } label: {
                                Circle().fill(Self.fill(color)).frame(width: 18, height: 18)
                                    .overlay(Circle().strokeBorder(.primary, lineWidth: color == model.settings.accentColor ? 2 : 0).padding(-3))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(color == .system ? "Same as macOS" : color.rawValue.capitalized)
                        }
                    }
                }
            }
        }
    }

    private static func fill(_ color: AccentColor) -> AnyShapeStyle {
        let plain: Color? = switch color {
        case .system: nil
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .graphite: .gray
        }
        return plain.map(AnyShapeStyle.init)
            ?? AnyShapeStyle(AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red], center: .center))
    }
}
