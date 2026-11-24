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
        func modes(_ raw: [String: Any]) -> [CallMode]? { validateSettings(raw).0.map { CallApp.allCases.map($0.callMode) } }
        #expect(modes([:]) == [.offer, .offer, .offer])
        #expect(modes(["callAutoStart": true]) == [.auto, .auto, .auto])
        #expect(modes(["callApps": ["Teams"]]) == [.offer, .off, .off])
        // An old file gave a call no panel with offers off, Start automatically or not.
        #expect(modes(["callOffer": false]) == [.off, .off, .off])
        #expect(modes(["callOffer": false, "callAutoStart": true]) == [.off, .off, .off])
    }

    @Test func callModesWinOverTheOldKeysAndAMissingAppIsOff() {
        let modes = validateSettings(["callModes": ["Teams": "auto", "Zoom": "offer"], "callOffer": false]).0
        #expect(modes.map { CallApp.allCases.map($0.callMode) } == [.auto, .offer, .off])
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
