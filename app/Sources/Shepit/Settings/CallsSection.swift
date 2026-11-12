import AppKit
import SwiftUI
import ShepitCore

/// Settings → Calls (call offer design §5.6, visual style §5.7): the offer panel, automatic start and stop,
/// and which apps get an offer.
struct CallsSection: View {
    let model: SettingsModel

    var body: some View {
        let settings = model.settings
        Section("Offer") {
            Hinted(hint: "A small panel with the call's name and a Start button") {
                Toggle("Offer a transcript when a call starts", isOn: model.binding("callOffer", \.callOffer))
            }
            Hinted(hint: "0 keeps it until you press a button (0, or 5–120)") {
                Stepper {
                    Text(settings.callOfferSeconds == 0 ? "Hide the panel after: never" : "Hide the panel after: \(settings.callOfferSeconds) s")
                } onIncrement: {
                    model.set("callOfferSeconds", SettingsModel.offerSeconds(after: settings.callOfferSeconds, up: true))
                } onDecrement: {
                    model.set("callOfferSeconds", SettingsModel.offerSeconds(after: settings.callOfferSeconds, up: false))
                }
            }
            .disabled(!settings.callOffer || settings.callAutoStart)
        }
        Section("Automatic start and stop") {
            Hinted(hint: "The panel counts down and the transcript starts unless you press Don't record. Off: nothing is recorded without your click") {
                Toggle("Start automatically", isOn: model.binding("callAutoStart", \.callAutoStart))
            }
            .disabled(!settings.callOffer)
            Stepper(value: model.binding("callAutoStartSeconds", \.callAutoStartSeconds), in: 3...60) {
                Text("Start after: \(settings.callAutoStartSeconds) s")
            }
            .disabled(!settings.callOffer || !settings.callAutoStart)
            Hinted(hint: "A transcript of a call stops by itself unless you press Keep recording (3–120)") {
                Stepper(value: model.binding("callAutoStopSeconds", \.callAutoStopSeconds), in: 3...120) {
                    Text("When the call ends, stop after: \(settings.callAutoStopSeconds) s")
                }
            }
        }
        Section {
            ForEach(CallApp.allCases, id: \.self) { app in
                Toggle(Self.titles[app] ?? app.rawValue, isOn: Binding(
                    get: { settings.callApps.contains(app.rawValue) },
                    set: { model.set("callApps", SettingsModel.callApps(settings.callApps, app, on: $0)) }))
            }
        } header: {
            Text("Apps")
        } footer: {
            if !AXIsProcessTrusted() {
                Text("⚠ Google Meet calls are found by the browser's tab titles: turn on Shepit in System Settings → Privacy & Security → Accessibility.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private static let titles: [CallApp: String] = [.teams: "Microsoft Teams", .zoom: "Zoom", .meet: "Google Meet (Chrome, Edge, Brave, Arc)"]
}

extension SettingsModel {
    /// `callOfferSeconds` one step up or down: 0 (never hides), then 5–120 in steps of 5.
    static func offerSeconds(after value: Int, up: Bool) -> Int {
        if up { return value == 0 ? 5 : min(120, value + 5) }
        return value <= 5 ? 0 : max(5, value - 5)
    }

    /// `callApps` with one app turned on or off, in the order of `CallApp`.
    static func callApps(_ apps: [String], _ app: CallApp, on: Bool) -> [String] {
        CallApp.allCases.map(\.rawValue).filter { $0 == app.rawValue ? on : apps.contains($0) }
    }
}
