import AppKit
import SwiftUI
import ShepitCore

/// Dictation's panel parts (settings review design §4): the floating panel shown while you dictate. They were the
/// Overlay page until the settings review.
struct DictationPanelSections: View {
    let model: SettingsModel
    let actions: WindowActions

    var body: some View {
        Section("Panel") {
            Hinted(hint: "Show the floating panel while you dictate: recording, transcribing, the live draft. With this off, short notices are shown instead") {
                Toggle("Show panel", isOn: model.binding("overlay", \.overlay))
            }
            Hinted(hint: "Show draft text while you speak. Needs the draft engine downloaded; uses extra memory") {
                Toggle("Live draft", isOn: model.binding("livePreview", \.livePreview))
            }
            Button("Preview", action: actions.previewOverlay)
        }
        Section("Panel look") {
            Hinted(hint: "Where on the screen with the active window") {
                Picker("Position", selection: model.styleBinding("position", \.position)) {
                    Text("Bottom").tag("bottom")
                    Text("Top").tag("top")
                    Text("Center").tag("center")
                }
                .pickerStyle(.segmented)
            }
            Hinted(hint: "Panel width in points. The text area never gets narrower than 200 pt — with many bars the panel grows instead") {
                slider("Width", "width", value: Double(style.width), in: 360...1600, step: 10) { Int($0) }
            }
            Hinted(hint: "Background opacity (1 = solid)") {
                slider("Opacity", "opacity", value: style.opacity, in: 0.2...1, step: 0.02) { ($0 * 100).rounded() / 100 }
            }
            Hinted(hint: "Text size; the panel height follows") {
                Stepper(value: model.styleBinding("fontSize", \.fontSize), in: 10...28) { Text("Font size: \(style.fontSize)") }
            }
            color("Background", "backgroundColor", \.backgroundColor, alpha: false)
            color("Text", "textColor", \.textColor, alpha: false)
            Hinted(hint: "Show the frequency meter (low pitch on the left, high on the right)") {
                Toggle("Meter", isOn: model.styleBinding("showMeter", \.showMeter))
            }
            Stepper(value: model.styleBinding("bars", \.bars), in: 3...24) { Text("Bars: \(style.bars)") }
            color("Meter color", "meterColor", \.meterColor, alpha: true)
        }
        Section("Panel texts and timing") {
            field("Title while recording", "listeningText", \.listeningText)
            field("Title while transcribing", "transcribingText", \.transcribingText)
            field("Title next to the final text", "doneText", \.doneText)
            Hinted(hint: "Show the recording time next to the title") {
                Toggle("Timer", isOn: model.styleBinding("showTimer", \.showTimer))
            }
            Hinted(hint: "How long the final text stays visible (0 = hide at once)") {
                slider("Final text", "doneSeconds", value: style.doneSeconds, in: 0...10, step: 0.5) { $0 }
            }
            Hinted(hint: "How long notices like “Cancelled” stay visible") {
                slider("Notices", "messageSeconds", value: style.messageSeconds, in: 0.5...10, step: 0.5) { $0 }
            }
        }
    }

    private var style: OverlayStyle { model.settings.overlayStyle }

    /// Writes on release, not on every drag step.
    private func slider(_ title: String, _ key: String, value: Double, in range: ClosedRange<Double>, step: Double,
                        stored: @escaping (Double) -> Any) -> some View {
        LabeledContent(title) {
            DeferredSlider(value: value, range: range, step: step) { model.setStyle(key, stored($0)) }
        }
    }

    private func field(_ title: String, _ key: String, _ path: KeyPath<OverlayStyle, String>) -> some View {
        LabeledContent(title) {
            SettingField(saved: style[keyPath: path]) { model.setStyle(key, $0) }
        }
    }

    private func color(_ title: String, _ key: String, _ path: KeyPath<OverlayStyle, String>, alpha: Bool) -> some View {
        ColorPicker(title, selection: Binding(
            get: { Color(hex: style[keyPath: path]) },
            set: { model.setStyle(key, $0.hex(alpha: alpha)) }), supportsOpacity: alpha)
    }
}

private struct DeferredSlider: View {
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let commit: (Double) -> Void
    @State private var dragging: Double?

    var body: some View {
        HStack {
            Slider(value: Binding(get: { dragging ?? value }, set: { dragging = $0 }), in: range, step: step) { editing in
                if !editing, let dragging {
                    commit(dragging)
                    self.dragging = nil
                }
            }
            Text(String(format: step < 1 ? "%.2f" : "%.0f", dragging ?? value)).monospacedDigit().frame(width: 44, alignment: .trailing)
        }
    }
}

extension Color {
    init(hex: String) {
        let c = OverlayLayout.color(hex)
        self.init(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
    }

    /// `#RRGGBB`, or `#RRGGBBAA` when alpha is wanted.
    func hex(alpha: Bool) -> String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let parts = [c.redComponent, c.greenComponent, c.blueComponent] + (alpha ? [c.alphaComponent] : [])
        return "#" + parts.map { String(format: "%02X", Int(($0 * 255).rounded())) }.joined()
    }
}
