import AppKit
import SwiftUI
import ShepitCore

/// The Calls part of Settings → Meetings (settings review design §7.3): Auto, Offer or Off per app, rules by meeting
/// name, and the delays.
struct CallsSection: View {
    let model: SettingsModel

    var body: some View {
        let settings = model.settings
        Section {
            ForEach(CallApp.allCases, id: \.self) { app in
                let mode = settings.callMode(for: app)
                Hinted(hint: hint(mode, settings) + (app == .meet ? " · in Chrome, Edge, Brave or Arc" : "")) {
                    Picker(app.title, selection: Binding(get: { mode }, set: { model.setCallMode(app, $0) })) {
                        ForEach(CallMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }
        } header: {
            Text("Calls")
        } footer: {
            if settings.callMode(for: .meet) != .off, !AXIsProcessTrusted() {
                Text("⚠ Google Meet calls are found by the browser's tab titles: turn on Shepit in System Settings → Privacy & Security → Accessibility.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        Section {
            ForEach(Array(settings.callRules.enumerated()), id: \.offset) { index, rule in
                RuleRow(rule: rule, ignored: settings.callMode(for: rule.app) == .off) { changed in
                    // The rules as they are now: a field that loses focus as its row goes must not bring back the old list.
                    var rules = model.settings.callRules
                    guard rules.indices.contains(index) else { return }
                    if let changed { rules[index] = changed } else { rules.remove(at: index) }
                    model.setCallRules(rules)
                }
            }
            .onMove { from, to in
                var rules = settings.callRules
                rules.move(fromOffsets: from, toOffset: to)
                model.setCallRules(rules)
            }
            Button {
                let app = CallApp.allCases.first { settings.callMode(for: $0) != .off } ?? .teams
                model.setCallRules(settings.callRules + [CallRule(app: app, match: .contains, text: "", then: .off)])
            } label: {
                Label("Add rule", systemImage: "plus")
            }
            .buttonStyle(.borderless)
        } header: {
            Text("Rules by meeting name")
        } footer: {
            Text("The first rule that matches the call's name decides; a call that matches none gets its app's choice. Drag a rule to move it.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Delays") {
            Stepper(value: model.binding("callAutoStartSeconds", \.callAutoStartSeconds), in: 3...60) {
                Text("Auto: start after \(settings.callAutoStartSeconds) s")
            }
            Hinted(hint: "Never keeps it until you press a button (0, or 5–120)") {
                Stepper {
                    Text(settings.callOfferSeconds == 0 ? "Offer: hide the panel after: never" : "Offer: hide the panel after \(settings.callOfferSeconds) s")
                } onIncrement: {
                    model.set("callOfferSeconds", SettingsModel.offerSeconds(after: settings.callOfferSeconds, up: true))
                } onDecrement: {
                    model.set("callOfferSeconds", SettingsModel.offerSeconds(after: settings.callOfferSeconds, up: false))
                }
            }
            Hinted(hint: "A transcript of a call stops by itself unless you press Keep recording (3–120)") {
                Stepper(value: model.binding("callAutoStopSeconds", \.callAutoStopSeconds), in: 3...120) {
                    Text("When the call ends, stop after \(settings.callAutoStopSeconds) s")
                }
            }
        }
    }

    private func hint(_ mode: CallMode, _ settings: ShepitCore.Settings) -> String {
        switch mode {
        case .auto: "Starts a transcript on its own after \(settings.callAutoStartSeconds) s"
        case .offer: "Shows a panel with the call's name and a Start button"
        case .off: "Does nothing"
        }
    }
}

/// A rule: app, contains or is, the text, and the choice. The text is saved on Enter or when the field loses focus.
private struct RuleRow: View {
    let rule: CallRule
    /// Its app is set to Off.
    let ignored: Bool
    /// nil: remove the rule.
    let change: (CallRule?) -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        let row = HStack {
            Picker("App", selection: field(\.app)) { ForEach(CallApp.allCases, id: \.self) { Text($0.title).tag($0) } }
                .labelsHidden().fixedSize()
            Picker("Match", selection: field(\.match)) { ForEach(CallRule.Match.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .labelsHidden().fixedSize()
            TextField("Meeting name", text: $draft, prompt: Text("Meeting name"))
                .labelsHidden()
                .focused($focused)
                .onSubmit(save)
                .onChange(of: focused) { if !$1 { save() } }
            Text("then").foregroundStyle(.secondary)
            Picker("Then", selection: field(\.then)) { ForEach(CallMode.allCases, id: \.self) { Text($0.title).tag($0) } }
                .labelsHidden().fixedSize()
            Button { change(nil) } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .help("Remove this rule")
        }
        .onAppear { draft = rule.text }
        .onChange(of: rule.text) { draft = $1 }
        if ignored {
            Hinted(hint: "Ignored: \(rule.app.title) is Off") { row.opacity(0.55) }
        } else {
            row
        }
    }

    private func field<Value>(_ path: WritableKeyPath<CallRule, Value>) -> Binding<Value> {
        Binding(get: { rule[keyPath: path] }, set: {
            var changed = rule
            changed[keyPath: path] = $0
            changed.text = draft // a choice made while the text is being typed keeps it
            change(changed)
        })
    }

    private func save() {
        guard draft != rule.text else { return }
        var changed = rule
        changed.text = draft
        change(changed)
    }
}

private extension CallMode {
    var title: String {
        switch self {
        case .auto: "Auto"
        case .offer: "Offer"
        case .off: "Off"
        }
    }
}

extension SettingsModel {
    /// `callOfferSeconds` one step up or down: 0 (never hides), then 5–120 in steps of 5.
    static func offerSeconds(after value: Int, up: Bool) -> Int {
        if up { return value == 0 ? 5 : min(120, value + 5) }
        return value <= 5 ? 0 : max(5, value - 5)
    }

    /// One app's choice; writes every app's, so the first write turns the old keys into `callModes` (the store drops them).
    func setCallMode(_ app: CallApp, _ mode: CallMode) {
        set("callModes", Dictionary(uniqueKeysWithValues: CallApp.allCases.map {
            ($0.rawValue, ($0 == app ? mode : settings.callMode(for: $0)).rawValue)
        }))
    }

    func setCallRules(_ rules: [CallRule]) {
        set("callRules", rules.map { ["app": $0.app.rawValue, "match": $0.match.rawValue, "text": $0.text, "then": $0.then.rawValue] })
    }
}
