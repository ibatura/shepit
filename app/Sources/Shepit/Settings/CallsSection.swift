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
                Hinted(hint: mode.about(autoStartSeconds: settings.callAutoStartSeconds) + (app == .meet ? " · in Chrome, Edge, Brave or Arc" : "")) {
                    LabeledContent(app.title) { // on the right, as every other control
                        Picker(app.title, selection: Binding(get: { mode }, set: { model.setCallMode(app, $0) })) {
                            ForEach(CallMode.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
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
            let rules = settings.callRules
            ForEach(Array(rules.enumerated()), id: \.offset) { index, rule in
                // The draft is kept for this rule in this place: the hash stands for the rule while Shepit runs.
                RuleRow(rule: rule, drafts: model.drafts, keep: "callRules.\(index).\(rule.hashValue)", ignored: settings.callMode(for: rule.app) == .off,
                        first: index == 0, last: index == rules.count - 1) { changed in
                    // The rules as they are now, not as this row was drawn.
                    var rules = model.settings.callRules
                    guard rules.indices.contains(index) else { return }
                    if let changed { rules[index] = changed } else { rules.remove(at: index) }
                    model.setCallRules(rules)
                } move: { by in
                    var rules = model.settings.callRules
                    guard rules.indices.contains(index), rules.indices.contains(index + by) else { return }
                    rules.swapAt(index, index + by)
                    model.setCallRules(rules)
                }
                // A row is kept by its place: when another rule comes to it (one above removed, or moved), its drafts must go.
                .id(rule)
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
            Text("The first rule that matches the call's name decides; a call that matches none gets its app's choice. The arrows move a rule up or down.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Delays") {
            NumberMenu(title: "Auto: start after", values: [3, 5, 10, 15, 30, 60],
                       selection: model.binding("callAutoStartSeconds", \.callAutoStartSeconds), text: StatusText.seconds)
            Hinted(hint: "Never keeps it until you press a button") {
                NumberMenu(title: "Offer: hide the panel after", values: [0, 10, 15, 30, 60, 120],
                           selection: model.binding("callOfferSeconds", \.callOfferSeconds)) { $0 == 0 ? "Never" : StatusText.seconds($0) }
            }
            Hinted(hint: "A transcript of a call stops by itself unless you press Keep recording") {
                NumberMenu(title: "When the call ends, stop after", values: [5, 10, 15, 30, 60, 120],
                           selection: model.binding("callAutoStopSeconds", \.callAutoStopSeconds), text: StatusText.seconds)
            }
        }
    }
}

/// A rule: app, contains or is, the text (saved with Save or Enter), the choice, and the arrows that move it.
private struct RuleRow: View {
    let rule: CallRule
    let drafts: SettingDrafts
    /// Where its text's draft is kept, typed and not saved.
    let keep: String
    /// Its app is set to Off.
    let ignored: Bool
    let first: Bool
    let last: Bool
    /// nil: remove the rule.
    let change: (CallRule?) -> Void
    /// -1 up, 1 down.
    let move: (Int) -> Void

    var body: some View {
        let row = HStack {
            Picker("App", selection: field(\.app)) { ForEach(CallApp.allCases, id: \.self) { Text($0.title).tag($0) } }
                .labelsHidden().fixedSize()
            Picker("Match", selection: field(\.match)) { ForEach(CallRule.Match.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .labelsHidden().fixedSize()
            SettingField(saved: rule.text, drafts: drafts, keep: keep, prompt: "Meeting name") {
                var changed = rule
                changed.text = $0
                change(changed)
            }
            Text("then").foregroundStyle(.secondary)
            Picker("Then", selection: field(\.then)) { ForEach(CallMode.allCases, id: \.self) { Text($0.title).tag($0) } }
                .labelsHidden().fixedSize()
            Group {
                Button { move(-1) } label: { Image(systemName: "chevron.up") }
                    .disabled(first).help("Move up: checked earlier")
                Button { move(1) } label: { Image(systemName: "chevron.down") }
                    .disabled(last).help("Move down: checked later")
                Button { change(nil) } label: { Image(systemName: "minus.circle") }
                    .help("Remove this rule")
            }
            .buttonStyle(.borderless)
        }
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
            changed.text = drafts.draft(keep, saved: rule.text) ?? rule.text // a choice made before Save keeps the text typed
            change(changed)
        })
    }
}

extension SettingsModel {
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
