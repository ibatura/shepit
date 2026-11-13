import SwiftUI
import ShepitCore

/// Settings → Appearance (window shell design §6.1).
struct AppearanceSection: View {
    let model: SettingsModel
    let actions: SettingsActions

    var body: some View {
        Section {
            Picker("Theme", selection: model.binding("theme", \.theme)) {
                Text("Same as macOS").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            // macOS reads an app's accent colour when the app starts.
            Hinted(hint: Settings.accentColorCode(model.settings.accentColor) == actions.accentAtLaunch
                ? "The first dot follows macOS" : "Restart Shepit to apply the colour") {
                LabeledContent("Accent colour") {
                    HStack(spacing: 8) {
                        ForEach(Settings.accentColors, id: \.self) { name in
                            Button { model.set("accentColor", name) } label: {
                                Circle().fill(Self.fill(name)).frame(width: 18, height: 18)
                                    .overlay(Circle().strokeBorder(.primary, lineWidth: name == model.settings.accentColor ? 2 : 0).padding(-3))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(name == "system" ? "Same as macOS" : name.capitalized)
                        }
                    }
                }
            }
        }
    }

    private static func fill(_ name: String) -> AnyShapeStyle {
        let colors: [String: Color] = ["blue": .blue, "purple": .purple, "pink": .pink, "red": .red, "orange": .orange,
                                       "yellow": .yellow, "green": .green, "graphite": .gray]
        return colors[name].map(AnyShapeStyle.init)
            ?? AnyShapeStyle(AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red], center: .center))
    }
}
