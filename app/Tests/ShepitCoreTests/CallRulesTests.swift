import Testing
@testable import ShepitCore

private func settings(_ change: (inout Settings) -> Void) -> Settings {
    var settings = Settings.defaults
    change(&settings)
    return settings
}

// Settings review design §7.1–7.2.
struct CallRulesTests {
    @Test func withoutCallModesEachAppsChoiceComesFromTheOldKeys() {
        #expect(CallApp.allCases.map(Settings.defaults.callMode) == [.offer, .offer, .offer])
        #expect(settings { $0.callAutoStart = true }.callMode(for: .zoom) == .auto)
        #expect(settings { $0.callApps = ["Teams"] }.callMode(for: .zoom) == .off)
        // Today a call gets no panel with offers off, Start automatically or not.
        #expect(settings { $0.callOffer = false }.callMode(for: .teams) == .off)
        #expect(settings { $0.callOffer = false; $0.callAutoStart = true }.callMode(for: .teams) == .off)
    }

    @Test func callModesWinOverTheOldKeysAndAMissingAppIsOff() {
        let modes = settings { $0.callModes = [.teams: .auto, .zoom: .offer]; $0.callOffer = false }
        #expect(CallApp.allCases.map(modes.callMode) == [.auto, .offer, .off])
    }

    @Test func theFirstMatchingRuleOfTheAppDecides() {
        let rules = settings {
            $0.callModes = [.teams: .offer, .zoom: .offer, .meet: .off]
            $0.callRules = [CallRule(app: .zoom, match: .contains, text: "scrum", then: .off),
                            CallRule(app: .teams, match: .contains, text: "Daily", then: .auto),
                            CallRule(app: .teams, match: .is, text: "daily scrum", then: .off),
                            CallRule(app: .teams, match: .contains, text: "", then: .off),
                            CallRule(app: .meet, match: .contains, text: "Sync", then: .auto)]
        }
        #expect(rules.callChoice(app: .teams, name: "Weekly sync") == .offer)
        #expect(rules.callChoice(app: .teams, name: "Team DAILY scrum") == .auto)
        #expect(rules.callChoice(app: .teams, name: nil) == .offer)
        #expect(rules.callChoice(app: .zoom, name: "Daily Scrum") == .off)
        #expect(rules.callChoice(app: .meet, name: "Sync") == .off) // Off ignores the app's rules
        let exact = settings { $0.callRules = [CallRule(app: .teams, match: .is, text: "Daily scrum", then: .auto)] }
        #expect(exact.callChoice(app: .teams, name: " daily SCRUM ") == .auto)
        #expect(exact.callChoice(app: .teams, name: "Daily scrum 2") == .offer)
        let cyrillic = settings { $0.callRules = [CallRule(app: .teams, match: .contains, text: "щоденний", then: .off)] }
        #expect(cyrillic.callChoice(app: .teams, name: "Щоденний скрам") == .off)
    }
}
