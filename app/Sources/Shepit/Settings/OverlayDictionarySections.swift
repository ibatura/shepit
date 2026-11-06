import AppKit
import SwiftUI
import ShepitCore

struct OverlaySection: View {
    let model: SettingsModel
    let actions: SettingsActions

    var body: some View {
        Section {
            Hinted(hint: "Show the floating panel. With this off, short notices are shown instead") {
                Toggle("Show panel", isOn: model.binding("overlay", \.overlay))
            }
            Hinted(hint: "Show draft text while you speak. Needs the draft engine downloaded; uses extra memory") {
                Toggle("Live draft", isOn: model.binding("livePreview", \.livePreview))
            }
            Button("Preview", action: actions.previewOverlay)
        }
        Section("Look") {
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
        }
        Section("Texts") {
            field("Title while recording", "listeningText", \.listeningText)
            field("Title while transcribing", "transcribingText", \.transcribingText)
            field("Title next to the final text", "doneText", \.doneText)
            Hinted(hint: "Show the recording time next to the title") {
                Toggle("Timer", isOn: model.styleBinding("showTimer", \.showTimer))
            }
        }
        Section("Meter") {
            Hinted(hint: "Show the frequency meter (low pitch on the left, high on the right)") {
                Toggle("Meter", isOn: model.styleBinding("showMeter", \.showMeter))
            }
            Stepper(value: model.styleBinding("bars", \.bars), in: 3...24) { Text("Bars: \(style.bars)") }
            color("Meter color", "meterColor", \.meterColor, alpha: true)
        }
        Section("Timing") {
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
        TextField(title, text: model.styleBinding(key, path))
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

struct DictionarySection: View {
    let model: SettingsModel
    @State private var newTerm = ""
    @State private var wrong = ""
    @State private var right = ""
    @State private var editing: String?
    @State private var newPhrase = ""

    var body: some View {
        Section {
            List {
                ForEach(model.dictionary.terms, id: \.self) { term in
                    HStack {
                        Text(term)
                        Spacer()
                        Button(role: .destructive) { model.setTerms(model.dictionary.terms.filter { $0 != term }) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }
                .onMove { from, to in
                    var terms = model.dictionary.terms
                    terms.move(fromOffsets: from, toOffset: to)
                    model.setTerms(terms)
                }
            }
            .frame(minHeight: 120)
            HStack {
                TextField("New term", text: $newTerm).onSubmit(addTerm)
                Button("Add", action: addTerm).disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Terms")
        } footer: {
            Text("""
                Before recognition: a hint. The engine reads these words with the style prompt and tries to spell them \
                this way, in any form (Kubernetes, Kubernetes-кластер). Not guaranteed, and only engines that take a prompt \
                use it (whisper.cpp, WhisperKit; not Parakeet). Only about 200 tokens are read, so drag the most important first.
                """)
                .font(.caption).foregroundStyle(.secondary)
        }
        Section {
            ForEach(model.dictionary.replace.sorted { $0.key < $1.key }, id: \.key) { rule in
                HStack {
                    Text(rule.key)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    Text(rule.value)
                    Spacer()
                    Button("Edit") { editing = rule.key; wrong = rule.key; right = rule.value }.buttonStyle(.borderless)
                    Button(role: .destructive) { model.removeRule(rule.key) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                }
            }
            HStack {
                TextField("What was heard", text: $wrong)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                TextField("Correct spelling", text: $right).onSubmit(saveRule)
                Button(editing == nil ? "Add" : "Save", action: saveRule)
                if editing != nil { Button("Cancel") { editing = nil; wrong = ""; right = "" } }
            }
        } header: {
            Text("Replace")
        } footer: {
            Text("""
                After recognition: a guaranteed fix. When the text contains exactly what was heard, it's replaced with the \
                correct spelling, with any engine. Each wrong variant needs its own rule (кубернетес, кубернетис…). \
                Ignores upper/lower case, matches whole words only, longer phrases win. Use it for what Terms didn't fix; \
                ⌃⌥D on a selected word adds both a rule and a term.
                """)
                .font(.caption).foregroundStyle(.secondary)
        }
        Section {
            ForEach(model.dictionary.dropPhrases, id: \.self) { phrase in
                HStack {
                    Text(phrase)
                    Spacer()
                    Button(role: .destructive) { model.setDropPhrases(model.dictionary.dropPhrases.filter { $0 != phrase }) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                }
            }
            HStack {
                TextField("Phrase", text: $newPhrase).onSubmit(addPhrase)
                Button("Add", action: addPhrase).disabled(newPhrase.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Drop phrases")
        } footer: {
            Text("Phrases the engine invents on silence or at the end, removed when they're the last sentence. Common ones («Дякую за перегляд!», “Thanks for watching”) are built in.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func addTerm() {
        let term = newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, !model.dictionary.terms.contains(term) else { return }
        model.setTerms(model.dictionary.terms + [term])
        newTerm = ""
    }

    private func saveRule() {
        model.setRule(wrong: wrong, right: right, replacing: editing)
        if model.lastError == nil {
            editing = nil
            wrong = ""
            right = ""
        }
    }

    private func addPhrase() {
        let phrase = newPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty, !model.dictionary.dropPhrases.contains(phrase) else { return }
        model.setDropPhrases(model.dictionary.dropPhrases + [phrase])
        newPhrase = ""
    }
}
