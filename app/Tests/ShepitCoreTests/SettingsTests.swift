import Foundation
import Testing
@testable import ShepitCore

struct SettingsTests {
    @Test func defaultsWhenRawIsEmpty() {
        let (settings, errors) = validateSettings([:])

        #expect(errors.isEmpty)
        #expect(settings?.mode == "toggle")
        #expect(settings?.hotkey == Hotkey(mods: ["alt"], key: "space"))
        #expect(settings?.cancelKey == "escape")
        #expect(settings?.model == "large-v3")
        #expect(settings?.language == "uk")
        #expect(settings?.serverPort == 8178)
        #expect(settings?.maxRecordingSeconds == 300)
        #expect(settings?.idleUnloadMinutes == 0)
        #expect(settings?.refocusOriginalApp == true)
        #expect(settings?.restoreClipboard == true)
        #expect(settings?.sounds == true)
        #expect(settings?.stylePrompt.contains("pull request") == true)
        #expect(settings?.engines[.dictation] == EngineChoice(engine: .whispercpp, model: "large-v3-turbo"))
        #expect(settings?.engines[.preview] == EngineChoice(engine: .whispercpp, model: "large-v3-turbo"))
        #expect(settings?.engines[.meetings] == EngineChoice(engine: .whispercpp, model: "large-v3-turbo"))
        #expect(settings?.launchAtLogin == true)
        #expect(settings?.typingSpeedWpm == 40)
        #expect(settings?.collectStats == true)
    }

    @Test func userValuesOverrideDefaultsAndUnknownKeysAreIgnored() {
        let (settings, errors) = validateSettings(["mode": "hold", "language": "auto", "extra": 1])

        #expect(errors.isEmpty)
        #expect(settings?.mode == "hold")
        #expect(settings?.language == "auto")
    }

    @Test func defaultsAreNotMutatedByValidation() {
        let (settings, _) = validateSettings(["hotkey": ["mods": ["cmd"], "key": "x"]])

        #expect(settings?.hotkey.mods == ["cmd"])
        #expect(Settings.defaults.hotkey.mods == ["alt"])
        #expect(Settings.defaults.overlayStyle.opacity == 0.88)
    }

    @Test func rejectsIntegerOutsideIntRangeWithoutTrapping() {
        let (settings, errors) = validateSettings(["maxRecordingSeconds": 9.223372036854776e18])

        #expect(settings == nil)
        #expect(errors == [#"settings.json: "maxRecordingSeconds" must be a whole number from 5 to 3600"#])
    }

    @Test func rejectsInvalidSettingsAndSortsErrors() {
        let (settings, errors) = validateSettings([
            "mode": "push",
            "model": 3,
            "serverPort": 80,
            "maxRecordingSeconds": 0,
            "sounds": "yes",
            "stylePrompt": false,
            "idleUnloadMinutes": -1
        ])

        #expect(settings == nil)
        #expect(errors == errors.sorted())
        #expect(errors.count == 6)
        #expect(errors.contains(#"settings.json: "mode" must be one of: toggle, hold"#))
    }

    @Test func rejectsBadHotkeyDefinitions() {
        let (_, badMods) = validateSettings(["hotkey": ["mods": ["super"], "key": "space"]])
        let (_, missingKey) = validateSettings(["hotkey": ["mods": ["alt"]]])
        let (_, wrongShape) = validateSettings(["hotkey": "alt+space"])

        #expect(badMods.contains(#"settings.json: "hotkey.mods" must be a list of: cmd, alt, ctrl, shift"#))
        #expect(missingKey.contains(#"settings.json: "hotkey.key" must be a key name like "space" or "d""#))
        #expect(wrongShape.contains(#"settings.json: "hotkey" must be an object like {"mods": ["alt"], "key": "space"}"#))
    }

    @Test func overlayDefaultsAndOverridesAreValidated() {
        let (defaults, errors) = validateSettings([:])
        #expect(errors.isEmpty)
        #expect(defaults?.overlay == true)
        #expect(defaults?.livePreview == true)
        #expect(defaults?.previewModel == "large-v3-turbo")
        #expect(defaults?.overlayStyle == .defaults)

        let (custom, customErrors) = validateSettings(["overlayStyle": ["opacity": 0.6, "meterColor": "#AABBCC", "bars": 16, "listeningText": "Ready"]])
        #expect(customErrors.isEmpty)
        #expect(custom?.overlayStyle.opacity == 0.6)
        #expect(custom?.overlayStyle.meterColor == "#AABBCC")
        #expect(custom?.overlayStyle.bars == 16)
        #expect(custom?.overlayStyle.listeningText == "Ready")

        let (badColor, colorErrors) = validateSettings(["overlayStyle": ["backgroundColor": "#00000080"]])
        #expect(colorErrors.isEmpty)
        #expect(badColor?.overlayStyle.backgroundColor == "#00000080")
    }

    @Test func overlayStyleRejectsBadValuesAndWrongShape() {
        let (_, errors) = validateSettings(["overlayStyle": [
            "opacity": 2,
            "meterColor": "red",
            "position": "left",
            "bars": 1,
            "fontSize": 40,
            "width": 100,
            "listeningText": 5,
            "showTimer": "no",
            "doneSeconds": -1
        ]])

        #expect(errors.count == 9)
        #expect(errors.contains(#"settings.json: "overlayStyle.opacity" must be a number from 0.2 to 1"#))
        #expect(errors.contains(##"settings.json: "overlayStyle.meterColor" must be a color like "#FF4D4D" (or "#RRGGBBAA")"##))
        #expect(errors.contains(#"settings.json: "overlayStyle.position" must be one of: bottom, top, center"#))

        let (_, wrongShape) = validateSettings(["overlayStyle": "dark"])
        #expect(wrongShape == [#"settings.json: "overlayStyle" must be an object"#])
    }

    @Test func addWordHotkeyAndMicrophoneDefaultsAndValidation() {
        let (defaults, _) = validateSettings([:])
        #expect(defaults?.addWordHotkey == Hotkey(mods: ["ctrl", "alt"], key: "d"))
        #expect(defaults?.microphone == "")

        let (valid, validErrors) = validateSettings(["addWordHotkey": ["mods": ["cmd", "shift"], "key": "w"]])
        #expect(validErrors.isEmpty)
        #expect(valid?.addWordHotkey.mods == ["cmd", "shift"])

        let (_, invalid) = validateSettings(["addWordHotkey": ["mods": ["meta"], "key": "d"]])
        #expect(invalid.contains { $0.contains("addWordHotkey.mods") })

        let (_, badMicrophone) = validateSettings(["microphone": 3])
        #expect(badMicrophone.contains(#"settings.json: "microphone" must be a string"#))
    }

    @Test func historySettingsDefaultsAndRanges() {
        let (defaults, _) = validateSettings([:])
        #expect(defaults?.saveHistory == true)
        #expect(defaults?.historyDays == 0)
        #expect(defaults?.failedAudioHours == 24)
        #expect(defaults?.historyMenuItems == 10)

        let (valid, validErrors) = validateSettings(["historyMenuItems": 0])
        #expect(validErrors.isEmpty)
        #expect(valid?.historyMenuItems == 0)

        let (_, invalid) = validateSettings(["saveHistory": "no", "historyDays": -1, "failedAudioHours": 1000])
        #expect(invalid.count == 3)
    }

    @Test func enginesDefaultFromLegacyKeys() {
        let (settings, errors) = validateSettings(["model": "large-v3-turbo", "previewModel": "large-v3"])

        #expect(errors.isEmpty)
        #expect(settings?.engines[.dictation] == EngineChoice(engine: .whispercpp, model: "large-v3-turbo"))
        #expect(settings?.engines[.preview] == EngineChoice(engine: .whispercpp, model: "large-v3"))
        #expect(settings?.engines[.meetings] == EngineChoice(engine: .whispercpp, model: "large-v3-turbo"))
    }

    @Test func missingEngineTasksFallBackToTheirLegacyKeys() {
        let (settings, errors) = validateSettings([
            "model": "large-v3-turbo",
            "previewModel": "large-v3",
            "engines": ["meetings": ["engine": "whisperkit", "model": "large-v3"]]
        ])

        #expect(errors.isEmpty)
        #expect(settings?.engines[.dictation] == EngineChoice(engine: .whispercpp, model: "large-v3-turbo"))
        #expect(settings?.engines[.preview] == EngineChoice(engine: .whispercpp, model: "large-v3"))
        #expect(settings?.engines[.meetings] == EngineChoice(engine: .whisperkit, model: "large-v3"))
    }

    @Test func enginesKeyWinsOverLegacy() {
        let (settings, errors) = validateSettings([
            "model": "not-a-model",
            "previewModel": "also-not-a-model",
            "engines": [
                "dictation": ["engine": "whisperkit", "model": "large-v3"],
                "preview": ["engine": "whispercpp", "model": "large-v3"]
            ]
        ])

        #expect(errors.isEmpty)
        #expect(settings?.engines[.dictation] == EngineChoice(engine: .whisperkit, model: "large-v3"))
        #expect(settings?.model == Settings.defaults.model)
        #expect(settings?.previewModel == Settings.defaults.previewModel)
    }

    @Test func engineChoicesValidateIDsModelsAndTaskNames() {
        let (_, badEngine) = validateSettings(["engines": ["dictation": ["engine": "foo"]]])
        #expect(badEngine == [#"settings.json: "engines.dictation.engine" must be one of: whisperkit, whispercpp, parakeet, apple"#])

        let (_, badModel) = validateSettings(["engines": ["dictation": ["engine": "parakeet", "model": "large-v3"]]])
        #expect(badModel == [#"settings.json: "engines.dictation.model" must be one of: parakeet-tdt-0.6b-v3"#])

        let (apple, appleErrors) = validateSettings(["engines": ["dictation": ["engine": "apple"]]])
        #expect(appleErrors.isEmpty)
        #expect(apple?.engines[.dictation] == EngineChoice(engine: .apple, model: ""))
        let (_, malformedAppleModel) = validateSettings(["engines": ["dictation": ["engine": "apple", "model": true]]])
        #expect(malformedAppleModel == [#"settings.json: "engines.dictation.model" must be one of: "#])

        let (_, unknownTask) = validateSettings(["engines": ["foo": ["engine": "whispercpp", "model": "large-v3"]]])
        #expect(unknownTask == [#"settings.json: "engines" has unknown task "foo"; allowed: dictation, preview, meetings"#])
    }

    @Test func newKeysValidateRangesAndJSONBooleansNotNumbers() {
        for speed in [9, 201] {
            let (_, errors) = validateSettings(["typingSpeedWpm": speed])
            #expect(errors.contains(#"settings.json: "typingSpeedWpm" must be a whole number from 10 to 200"#))
        }
        let (_, badLogin) = validateSettings(["launchAtLogin": 1])
        let (_, badStats) = validateSettings(["collectStats": 0])
        #expect(badLogin.contains(#"settings.json: "launchAtLogin" must be a boolean"#))
        #expect(badStats.contains(#"settings.json: "collectStats" must be a boolean"#))

        let (valid, errors) = validateSettings(["launchAtLogin": false, "collectStats": false, "typingSpeedWpm": 200])
        #expect(errors.isEmpty)
        #expect(valid?.launchAtLogin == false)
        #expect(valid?.collectStats == false)
        #expect(valid?.typingSpeedWpm == 200)
    }

    @Test func meetingDefaults() {
        let settings = validateSettings([:]).0
        #expect(settings?.meetingsFolder == "~/.local/share/dictation/meetings")
        #expect(settings?.meetingFileName == "{date} {time} {title}")
        #expect(settings?.meetingAskTitle == true)
        #expect(settings?.meetingMyName == "")
        #expect(settings?.meetingLanguage == "auto")
        #expect(settings?.meetingBlocksDictation == false)
    }

    @Test func meetingValuesAreAccepted() {
        let (settings, errors) = validateSettings([
            "meetingsFolder": "/Users/me/Vault/Meetings", "meetingFileName": "{year}/{date} {title}",
            "meetingAskTitle": false, "meetingMyName": "Ivan Batura", "meetingLanguage": "uk",
            "meetingBlocksDictation": true,
        ])
        #expect(errors.isEmpty)
        #expect(settings?.meetingsFolder == "/Users/me/Vault/Meetings")
        #expect(settings?.meetingFileName == "{year}/{date} {title}")
        #expect(settings?.meetingAskTitle == false)
        #expect(settings?.meetingMyName == "Ivan Batura")
        #expect(settings?.meetingLanguage == "uk")
        #expect(settings?.meetingBlocksDictation == true)
        #expect(validateSettings(["meetingsFolder": "~/Notes"]).1.isEmpty)
    }

    @Test func meetingValuesAreRejected() {
        let (settings, errors) = validateSettings([
            "meetingsFolder": "Notes/Meetings", "meetingFileName": "{date}: {room}",
            "meetingAskTitle": "yes", "meetingMyName": 3, "meetingLanguage": "de",
            "meetingBlocksDictation": 1,
        ])
        #expect(settings == nil)
        #expect(errors == [
            #"settings.json: "meetingAskTitle" must be a boolean"#,
            #"settings.json: "meetingBlocksDictation" must be a boolean"#,
            #"settings.json: "meetingFileName" has unknown placeholder {room}; allowed: {date} {time} {year} {month} {day} {hour} {minute} {weekday} {title} {app}"#,
            #"settings.json: "meetingLanguage" must be one of: uk, en, auto"#,
            #"settings.json: "meetingMyName" must be a string"#,
            #"settings.json: "meetingsFolder" must be an absolute path or start with ~/"#,
        ])
        #expect(validateSettings(["meetingsFolder": ""]).1 == [#"settings.json: "meetingsFolder" must be an absolute path or start with ~/"#])
        #expect(validateSettings(["meetingsFolder": "~"]).1.count == 1)
    }

    @Test func callDefaults() {
        let settings = validateSettings([:]).0
        #expect(settings?.callOffer == true)
        #expect(settings?.callOfferSeconds == 15)
        #expect(settings?.callAutoStart == false)
        #expect(settings?.callAutoStartSeconds == 5)
        #expect(settings?.callAutoStopSeconds == 10)
        #expect(settings?.callApps == ["Teams", "Zoom", "Meet"])
    }

    @Test func callValuesAreAccepted() {
        let (settings, errors) = validateSettings([
            "callOffer": false, "callOfferSeconds": 0, "callAutoStart": true,
            "callAutoStartSeconds": 3, "callAutoStopSeconds": 120, "callApps": ["Zoom"],
        ])
        #expect(errors.isEmpty)
        #expect(settings?.callOffer == false)
        #expect(settings?.callOfferSeconds == 0)
        #expect(settings?.callAutoStart == true)
        #expect(settings?.callAutoStartSeconds == 3)
        #expect(settings?.callAutoStopSeconds == 120)
        #expect(settings?.callApps == ["Zoom"])
        #expect(validateSettings(["callOfferSeconds": 5]).0?.callOfferSeconds == 5)
        #expect(validateSettings(["callOfferSeconds": 120]).0?.callOfferSeconds == 120)
        #expect(validateSettings(["callApps": [String]()]).0?.callApps == [])
    }

    @Test func callValuesAreRejected() {
        let offer = #"settings.json: "callOfferSeconds" must be 0 or a whole number from 5 to 120"#
        for bad in [1, 4, 121, -1] { #expect(validateSettings(["callOfferSeconds": bad]).1 == [offer]) }
        let apps = #"settings.json: "callApps" must be a list of: Teams, Zoom, Meet, each at most once"#
        let badApps: [Any] = [["Slack"], ["Zoom", "Zoom"], "Zoom", [1]]
        for bad in badApps { #expect(validateSettings(["callApps": bad]).1 == [apps]) }
        #expect(validateSettings(["callOffer": 1, "callAutoStart": "yes", "callAutoStartSeconds": 2, "callAutoStopSeconds": 121]).1 == [
            #"settings.json: "callAutoStart" must be a boolean"#,
            #"settings.json: "callAutoStartSeconds" must be a whole number from 3 to 60"#,
            #"settings.json: "callAutoStopSeconds" must be a whole number from 3 to 120"#,
            #"settings.json: "callOffer" must be a boolean"#,
        ])
    }

    @Test func meetingsFolderExpandsTildeAndMyNameFallsBackToTheAccountName() {
        var settings = Settings.defaults
        let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)
        #expect(settings.meetingsFolderURL(home: home).path == "/Users/me/.local/share/dictation/meetings")
        settings.meetingsFolder = "/Volumes/Notes/Meetings"
        #expect(settings.meetingsFolderURL(home: home).path == "/Volumes/Notes/Meetings")
        #expect(settings.myName(fullName: "Ivan Batura") == "Ivan Batura")
        settings.meetingMyName = "  Іван  "
        #expect(settings.myName(fullName: "Ivan Batura") == "Іван")
        settings.meetingMyName = " "
        #expect(settings.myName(fullName: "") == "Я")
    }

    @Test func serverPortIsIgnoredEvenWhenOutsideLegacyRange() {
        let (settings, errors) = validateSettings(["serverPort": 99999])

        #expect(errors.isEmpty)
        #expect(settings?.serverPort == Settings.defaults.serverPort)
    }

    @Test func realUserSettingsFileLoadsAndUnknownKeysAreIgnored() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let exampleURL = repoRoot.appending(path: "examples/settings.json")
        var raw = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: exampleURL)) as? [String: Any])
        raw["foo"] = 1

        #expect(raw["launchAtLogin"] as? Bool == true)
        #expect(raw["typingSpeedWpm"] as? Int == 40)
        #expect(raw["collectStats"] as? Bool == true)
        #expect((raw["engines"] as? [String: [String: String]])?["dictation"] == ["engine": "whispercpp", "model": "large-v3-turbo"])
        #expect((raw["engines"] as? [String: [String: String]])?["preview"] == ["engine": "whispercpp", "model": "large-v3-turbo"])
        #expect((raw["engines"] as? [String: [String: String]])?["meetings"] == ["engine": "whispercpp", "model": "large-v3-turbo"])

        let (settings, errors) = validateSettings(raw)
        #expect(errors.isEmpty)
        #expect(settings?.overlayStyle.bars == 10)
        #expect(settings?.engines[.dictation] == EngineChoice(engine: .whispercpp, model: "large-v3-turbo"))
        #expect(settings?.engines[.preview] == EngineChoice(engine: .whispercpp, model: "large-v3-turbo"))
        #expect(settings?.engines[.meetings] == EngineChoice(engine: .whispercpp, model: "large-v3-turbo"))
        #expect(settings?.launchAtLogin == true)
        #expect(settings?.typingSpeedWpm == 40)
        #expect(settings?.collectStats == true)
    }
}
