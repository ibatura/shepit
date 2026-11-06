import Testing
@testable import ShepitCore

private let turbo = EngineChoice(engine: .whispercpp, model: "large-v3-turbo")
private let kit = EngineChoice(engine: .whisperkit, model: "large-v3")

private func view(_ change: (inout MenuView) -> Void = { _ in }) -> MenuView {
    var v = MenuView()
    v.downloaded = [turbo]
    v.microphones = ["MacBook Pro Microphone", "MOMENTUM 4"]
    change(&v)
    return v
}

private func find(_ items: [MenuItem], _ title: String) -> MenuItem? {
    items.first { $0.title == title }
}

// Ported from tests/test_menubar.lua, with the native menu changes from 03-dictation.md §7.
struct MenuModelTests {
    @Test func titleReflectsStateAndProblems() {
        #expect(MenuModel.title(view()) == "🎙")
        #expect(MenuModel.title(view { $0.load = .failed("x") }) == "🎙⚠")
        #expect(MenuModel.title(view { $0.hotkeyProblem = "Hotkey taken" }) == "🎙⚠")
        #expect(MenuModel.title(view { $0.state = .recording }) == "🔴")
        #expect(MenuModel.title(view { $0.state = .transcribing; $0.load = .loading }) == "⏳")
    }

    @Test func statusLineForEachSituation() {
        #expect(MenuModel.statusLine(view()) == "Ready — whisper.cpp large-v3-turbo")
        #expect(MenuModel.statusLine(view { $0.load = .loading }) == "Loading whisper.cpp large-v3-turbo…")
        #expect(MenuModel.statusLine(view { $0.load = .failed("Missing file: x") }) == "Error: Missing file: x")
        #expect(MenuModel.statusLine(view { $0.load = .unloaded }) == "Model unloaded — loads on next use")
        #expect(MenuModel.statusLine(view { $0.state = .recording }) == "Recording… (Esc to cancel)")
        #expect(MenuModel.statusLine(view { $0.state = .transcribing }) == "Transcribing…")
    }

    @Test func longErrorDetailsAreShortened() {
        #expect(MenuModel.statusLine(view { $0.load = .failed(String(repeating: "x", count: 200)) }).count <= 90)
    }

    @Test func menuHasStatusSubmenusAndActionsInOrder() {
        let items = MenuModel.build(view())
        #expect(items.map(\.title) == [
            "Ready — whisper.cpp large-v3-turbo", "-", "Mode", "Engine", "Language", "Microphone", "-",
            "Start meeting transcript", "Copy last meeting transcript", "Rename speakers…", "Rename speakers in another note…",
            "Open meetings folder", "-",
            "Add to dictionary…", "Edit dictionary…", "Settings…", "Statistics", "Reload config", "Reload models",
            "Recent", "Open history", "Clear history…", "-", "Quit",
        ])
        #expect(!items[0].enabled)
        #expect(find(items, "Settings…")?.keyEquivalent == ",")
    }

    @Test func modeSubmenuChecksCurrentModeAndSetsMode() {
        let mode = find(MenuModel.build(view()), "Mode")?.submenu ?? []
        #expect(mode.map(\.title) == ["Toggle", "Hold to talk"])
        #expect(mode.map(\.checked) == [true, false])
        #expect(mode[1].action == .setMode("hold"))
    }

    @Test func languageSubmenu() {
        let language = find(MenuModel.build(view()), "Language")?.submenu ?? []
        #expect(language.map(\.title) == ["Ukrainian", "English", "Auto-detect"])
        #expect(language[0].checked)
        #expect(language[2].action == .setLanguage("auto"))
    }

    @Test func engineSubmenuListsDownloadedEnginesOnly() {
        let one = find(MenuModel.build(view()), "Engine")?.submenu ?? []
        #expect(one.map(\.title) == ["whisper.cpp large-v3-turbo"])
        #expect(one[0].checked)
        let two = find(MenuModel.build(view { $0.downloaded = [turbo, kit] }), "Engine")?.submenu ?? []
        #expect(two.count == 2)
        #expect(two[1].action == .setEngine(kit))
    }

    @Test func configuredButMissingEngineIsShownDisabled() {
        let engine = find(MenuModel.build(view { $0.downloaded = [] }), "Engine")?.submenu ?? []
        #expect(engine.map(\.title) == ["whisper.cpp large-v3-turbo (not downloaded)"])
        #expect(engine.first?.enabled == false)
    }

    @Test func settingsSubmenusAreDisabledWhileRecordingOrTranscribing() {
        let items = MenuModel.build(view { $0.state = .recording })
        for title in ["Mode", "Engine", "Language", "Microphone", "Reload models"] {
            #expect(find(items, title)?.enabled == false)
        }
    }

    @Test func configErrorsAndHotkeyProblemsAppearUnderTheStatusLine() {
        let items = MenuModel.build(view { $0.configErrors = [#"settings.json: "mode" bad"#]; $0.hotkeyProblem = "Hotkey taken" })
        #expect(items[1].title == #"⚠ settings.json: "mode" bad"#)
        #expect(items[2].title == "⚠ Hotkey taken")
        #expect(!items[1].enabled && !items[2].enabled)
    }

    @Test func missingPermissionsAreClickable() {
        let items = MenuModel.build(view { $0.accessibilityGranted = false; $0.microphoneDenied = true })
        #expect(items[1].action == .grantAccessibility)
        #expect(items[2].action == .grantMicrophone)
    }

    @Test func actionItemsCarryTheirActions() {
        let items = MenuModel.build(view())
        #expect(find(items, "Edit dictionary…")?.action == .editDictionary)
        #expect(find(items, "Reload models")?.action == .reloadModels)
        #expect(find(items, "Quit")?.action == .quit)
        #expect(find(items, "Add to dictionary…")?.action == .addToDictionary)
        #expect(find(items, "Clear history…")?.action == .clearHistory)
        #expect(find(items, "Statistics")?.action == .openStatistics)
    }

    @Test func recentSubmenuListsEntriesAndCopiesTheFullText() {
        let v = view {
            $0.today = "2026-10-06"
            $0.recent = [
                History.Entry(time: "2026-10-06 14:32:05", text: "Треба задеплоїти цей pull request"),
                History.Entry(time: "2026-10-06 14:28:00", text: "Commit"),
            ]
        }
        let recent = find(MenuModel.build(v), "Recent")?.submenu ?? []
        #expect(recent.count == 2)
        #expect(recent[0].title == "14:32 · Треба задеплоїти цей pull request")
        #expect(recent[0].tooltip == "Треба задеплоїти цей pull request")
        #expect(recent[0].action == .copyText("Треба задеплоїти цей pull request"))
    }

    @Test func recentSubmenuShowsAPlaceholderWhenHistoryIsEmpty() {
        #expect(find(MenuModel.build(view()), "Recent")?.submenu == [MenuItem(title: "No dictations yet", enabled: false)])
    }

    @Test func recentSubmenuIsHiddenWhenTheSettingIsZero() {
        #expect(find(MenuModel.build(view { $0.recent = nil }), "Recent") == nil)
    }

    @Test func microphoneSubmenuChecksTheConfiguredDevice() {
        let mic = find(MenuModel.build(view { $0.settings.microphone = "MOMENTUM 4" }), "Microphone")?.submenu ?? []
        #expect(mic.map(\.title) == ["System default", "MacBook Pro Microphone", "MOMENTUM 4"])
        #expect(mic.map(\.checked) == [false, false, true])
        #expect(mic[1].action == .setMicrophone("MacBook Pro Microphone"))
        #expect(mic[0].action == .setMicrophone(""))
    }

    @Test func microphoneDefaultCheckedWhenUnsetAndMissingDeviceShownDisabled() {
        #expect(find(MenuModel.build(view()), "Microphone")?.submenu?.first?.checked == true)
        let mic = find(MenuModel.build(view { $0.settings.microphone = "AirPods" }), "Microphone")?.submenu ?? []
        #expect(mic.last?.title == "AirPods (not connected)")
        #expect(mic.last?.enabled == false)
        #expect(mic.first?.checked == false)
    }

    // Meetings (spec §5.6)

    @Test func meetingMarkInTheTitleWhileASessionRuns() {
        #expect(MenuModel.title(view { $0.meeting = .recording(elapsed: 5, waiting: 0) }) == "⏺🎙")
        #expect(MenuModel.title(view { $0.meeting = .recording(elapsed: 5, waiting: 0); $0.state = .recording }) == "⏺🔴")
        #expect(MenuModel.title(view { $0.meeting = .detectingSpeakers }) == "⏺🎙")
        #expect(MenuModel.title(view { $0.meeting = .done(speakers: 2) }) == "🎙")
    }

    @Test func meetingStatusLines() {
        #expect(MenuModel.meetingLine(.recording(elapsed: 754, waiting: 2)) == "Meeting: recording 12:34 · 2 phrases waiting")
        #expect(MenuModel.meetingLine(.recording(elapsed: 3_725, waiting: 1)) == "Meeting: recording 1:02:05 · 1 phrase waiting")
        #expect(MenuModel.meetingLine(.recording(elapsed: 9, waiting: 0)) == "Meeting: recording 0:09")
        #expect(MenuModel.meetingLine(.finishing(left: 3)) == "Meeting: finishing (3 left)")
        #expect(MenuModel.meetingLine(.detectingSpeakers) == "Meeting: detecting speakers…")
        #expect(MenuModel.meetingLine(.idle) == nil)
        let items = MenuModel.build(view { $0.meeting = .finishing(left: 1) })
        #expect(items[1].title == "Meeting: finishing (1 left)" && !items[1].enabled)
    }

    @Test func meetingStartAndStopItems() {
        let idle = MenuModel.build(view())
        #expect(find(idle, "Start meeting transcript")?.action == .startMeeting)
        #expect(find(idle, "Copy last meeting transcript")?.action == .copyLastMeeting)
        #expect(find(idle, "Open meetings folder")?.action == .openMeetingsFolder)
        #expect(find(MenuModel.build(view { $0.meeting = .recording(elapsed: 1, waiting: 0) }), "Stop meeting transcript")?.action == .stopMeeting)
        let finishing = find(MenuModel.build(view { $0.meeting = .finishing(left: 2) }), "Start meeting transcript")
        #expect(finishing?.enabled == false)
        let missing = MenuModel.build(view { $0.meetingMissing = "download the model in Settings" })
        #expect(find(missing, "Start meeting transcript (download the model in Settings)")?.enabled == false)
        #expect(find(MenuModel.build(view { $0.meeting = .done(speakers: 1) }), "Start meeting transcript")?.enabled == true)
    }

    @Test func renameSpeakersItemsAreOffWhileASessionRuns() {
        let idle = MenuModel.build(view { $0.meeting = .done(speakers: 2) })
        #expect(find(idle, "Rename speakers…")?.action == .renameSpeakers)
        #expect(find(idle, "Rename speakers in another note…")?.action == .renameSpeakersInNote)
        for state in [MeetingState.recording(elapsed: 1, waiting: 0), .finishing(left: 1), .detectingSpeakers] {
            let items = MenuModel.build(view { $0.meeting = state })
            #expect(find(items, "Rename speakers…")?.enabled == false)
            #expect(find(items, "Rename speakers in another note…")?.enabled == false)
        }
    }

    @Test func microphoneCantChangeDuringAMeeting() {
        #expect(find(MenuModel.build(view { $0.meeting = .recording(elapsed: 1, waiting: 0) }), "Microphone")?.enabled == false)
    }
}
