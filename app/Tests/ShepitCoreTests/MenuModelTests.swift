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
            "Ready — whisper.cpp large-v3-turbo", "-", "Open Shepit", "-",
            "Start meeting transcript", "Copy last meeting transcript", "Rename speakers…", "Rename speakers in another note…",
            "Open meetings folder", "-",
            "Copy last dictation", "Recent", "Add word…", "-",
            "Mode", "Language", "Dictation engine", "-", "Settings…", "Quit Shepit",
        ])
        #expect(!items[0].enabled)
        #expect(find(items, "Settings…")?.keyEquivalent == ",")
        #expect(find(items, "Open Shepit")?.keyEquivalent == "o")
        #expect(find(items, "Open Shepit")?.action == .openWindow)
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
        let one = find(MenuModel.build(view()), "Dictation engine")?.submenu ?? []
        #expect(one.map(\.title) == ["whisper.cpp large-v3-turbo"])
        #expect(one[0].checked)
        let two = find(MenuModel.build(view { $0.downloaded = [turbo, kit] }), "Dictation engine")?.submenu ?? []
        #expect(two.count == 2)
        #expect(two[1].action == .setEngine(kit))
    }

    @Test func configuredButMissingEngineIsShownDisabled() {
        let engine = find(MenuModel.build(view { $0.downloaded = [] }), "Dictation engine")?.submenu ?? []
        #expect(engine.map(\.title) == ["whisper.cpp large-v3-turbo (not downloaded)"])
        #expect(engine.first?.enabled == false)
    }

    @Test func settingsSubmenusAreDisabledWhileRecordingOrTranscribing() {
        let items = MenuModel.build(view { $0.state = .recording })
        for title in ["Mode", "Dictation engine", "Language"] {
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
        #expect(find(items, "Quit Shepit")?.action == .quit)
        #expect(find(items, "Add word…")?.action == .addToDictionary)
        #expect(find(items, "Settings…")?.action == .openSettings)
    }

    @Test func copyLastDictationCopiesTheNewestEntryWhateverRecentShows() {
        #expect(find(MenuModel.build(view()), "Copy last dictation")?.enabled == false)
        let items = MenuModel.build(view {
            $0.recent = nil
            $0.history = [History.Entry(time: "2026-10-06 14:32:05", text: "new"), History.Entry(time: "2026-10-06 14:28:00", text: "old")]
        })
        #expect(find(items, "Copy last dictation")?.enabled == true)
        #expect(find(items, "Copy last dictation")?.action == .copyText("new"))
    }

    @Test func theMenuKeepsItsItemsDuringAMeeting() {
        let items = MenuModel.build(view { $0.meeting = .recording(elapsed: 5, waiting: 0) })
        for title in ["Add word…", "Mode", "Language", "Dictation engine"] { #expect(find(items, title)?.enabled == true) }
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

    // Meetings (spec §5.6)

    @Test func meetingMarkInTheTitleWhileASessionRuns() {
        #expect(MenuModel.title(view { $0.meeting = .recording(elapsed: 5, waiting: 0) }) == "⏺🎙")
        #expect(MenuModel.title(view { $0.meeting = .recording(elapsed: 5, waiting: 0); $0.state = .recording }) == "⏺🔴")
        #expect(MenuModel.title(view { $0.meeting = .detectingSpeakers }) == "⏺🎙")
        #expect(MenuModel.title(view { $0.meeting = .done(speakers: 2) }) == "🎙")
    }

    @Test func meetingStatusLines() {
        #expect(MenuModel.meetingLine(.recording(elapsed: 754, waiting: 2), title: "Weekly sync") == "⏺ Recording · Weekly sync · 12:34 · 2 phrases waiting")
        #expect(MenuModel.meetingLine(.recording(elapsed: 3_725, waiting: 1)) == "⏺ Recording · 1:02:05 · 1 phrase waiting")
        #expect(MenuModel.meetingLine(.recording(elapsed: 9, waiting: 0), title: "Weekly sync") == "⏺ Recording · Weekly sync · 0:09")
        #expect(MenuModel.meetingLine(.finishing(left: 3)) == "Meeting: finishing (3 left)")
        #expect(MenuModel.meetingLine(.detectingSpeakers) == "Meeting: detecting speakers…")
        #expect(MenuModel.meetingLine(.idle) == nil)
        let items = MenuModel.build(view { $0.meeting = .finishing(left: 1) })
        #expect(items[1].title == "Meeting: finishing (1 left)" && !items[1].enabled)
        let named = MenuModel.build(view { $0.meeting = .recording(elapsed: 9, waiting: 0); $0.meetingTitle = "Weekly sync" })
        #expect(named[1].title == "⏺ Recording · Weekly sync · 0:09")
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
}
