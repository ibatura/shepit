import Foundation
import Testing
@testable import ShepitCore

private let turbo = EngineChoice(engine: .whispercpp, model: "large-v3-turbo")

private func view(_ change: (inout AppSnapshot) -> Void = { _ in }) -> AppSnapshot {
    var v = AppSnapshot()
    v.downloaded = [turbo]
    change(&v)
    return v
}

private func find(_ items: [MenuItem], _ title: String) -> MenuItem? {
    items.first { $0.title == title }
}

private func at(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

private func entry(_ text: String, _ time: Date) -> DictationStore.Entry {
    .init(id: 0, time: time, appName: "Slack", appBundleID: nil, text: text, words: 1)
}

// Ported from tests/test_menubar.lua, with the native menu changes from 03-dictation.md §7.
struct MenuModelTests {
    // Icon and name design §6: the rhombus's mark, in the cases the emoji title had.
    @Test func iconReflectsStateAndProblems() {
        #expect(MenuModel.icon(view()) == MenuIcon(mark: .ready, meeting: false))
        #expect(MenuModel.icon(view { $0.load = .failed("x") }) == MenuIcon(mark: .problem, meeting: false))
        #expect(MenuModel.icon(view { $0.hotkeyProblem = "Hotkey taken" }) == MenuIcon(mark: .problem, meeting: false))
        #expect(MenuModel.icon(view { $0.state = .recording }) == MenuIcon(mark: .recording, meeting: false))
        #expect(MenuModel.icon(view { $0.state = .recording; $0.hotkeyProblem = "Hotkey taken" }) == MenuIcon(mark: .recording, meeting: false))
        #expect(MenuModel.icon(view { $0.state = .transcribing; $0.load = .loading }) == MenuIcon(mark: .transcribing, meeting: false))
    }

    // The tooltip and VoiceOver say what the icon's dots show, as the emoji title did.
    @Test func iconLabelSaysWhatTheDotsShow() {
        #expect(MenuModel.iconLabel(view()) == "Shepit: Ready — whisper.cpp large-v3-turbo")
        #expect(MenuModel.iconLabel(view { $0.hotkeyProblem = "Hotkey taken" }) == "Shepit: Ready — whisper.cpp large-v3-turbo · Hotkey taken")
        #expect(MenuModel.iconLabel(view { $0.state = .recording; $0.hotkeyProblem = "Hotkey taken" }) == "Shepit: Recording… (Esc to cancel)")
        let recording = MeetingState.recording(elapsed: 5, waiting: 0)
        #expect(MenuModel.iconLabel(view { $0.meeting = .init(state: recording, title: "Weekly sync") })
                == "Shepit: Ready — whisper.cpp large-v3-turbo · Meeting transcript running")
        #expect(MenuModel.iconLabel(view { $0.meeting = .init(state: .done(speakers: 2)) }) == "Shepit: Ready — whisper.cpp large-v3-turbo")
    }

    @Test func onlyReadyAndTranscribingWithoutAMeetingArePlain() {
        #expect(Set(MenuIcon.allCases).count == 8)
        for icon in MenuIcon.allCases {
            #expect(icon.isPlain == (!icon.meeting && [.ready, .transcribing].contains(icon.mark)), "\(icon)")
        }
    }

    @Test func statusLineForEachSituation() {
        #expect(view().statusLine == "Ready — whisper.cpp large-v3-turbo")
        #expect(view { $0.load = .loading }.statusLine == "Loading whisper.cpp large-v3-turbo…")
        #expect(view { $0.load = .failed("Missing file: x") }.statusLine == "Error: Missing file: x")
        #expect(view { $0.load = .unloaded }.statusLine == "Model unloaded — loads on next use")
        #expect(view { $0.state = .recording }.statusLine == "Recording… (Esc to cancel)")
        #expect(view { $0.state = .transcribing }.statusLine == "Transcribing…")
    }

    @Test func longErrorDetailsAreShortened() {
        #expect(view { $0.load = .failed(String(repeating: "x", count: 200)) }.statusLine.count <= 90)
    }

    // Settings review design §6: four groups, each led by its state.
    @Test func theMenuInFourGroups() {
        let items = MenuModel.build(view())
        #expect(items.map(\.title) == [
            "Start meeting transcript", "Meeting language", "-",
            "Dictation: Ready — whisper.cpp large-v3-turbo", "Copy last dictation", "Recent dictations", "Add word to dictionary…", "Dictation language", "-",
            "Open Shepit", "Settings…", "About Shepit", "Quit Shepit",
        ])
        #expect(find(items, "Dictation: Ready — whisper.cpp large-v3-turbo")?.enabled == false)
        #expect(find(items, "Open Shepit")?.keyEquivalent == "o")
        #expect(find(items, "Open Shepit")?.action == .openWindow)
        #expect(find(items, "Settings…")?.keyEquivalent == ",")
        #expect(find(items, "Quit Shepit")?.keyEquivalent == "q")
        for gone in ["Mode", "Language", "Dictation engine"] { #expect(find(items, gone) == nil, "\(gone)") }
    }

    @Test func eachLanguageSetsItsOwnSetting() {
        let items = MenuModel.build(view { $0.settings.language = "uk"; $0.settings.meetingLanguage = "en" })
        let dictation = find(items, "Dictation language")?.submenu ?? []
        #expect(dictation.map(\.title) == ["Ukrainian", "English", "Auto-detect"])
        #expect(dictation.map(\.checked) == [true, false, false])
        #expect(dictation[2].action == .setLanguage("auto"))
        let meeting = find(items, "Meeting language")?.submenu ?? []
        #expect(meeting.map(\.checked) == [false, true, false])
        #expect(meeting[0].action == .setMeetingLanguage("uk"))
    }

    @Test func aLanguageWaitsForItsOwnJob() {
        let dictating = MenuModel.build(view { $0.state = .recording })
        #expect(find(dictating, "Dictation language")?.enabled == false)
        #expect(find(dictating, "Meeting language")?.enabled == true)
        let meeting = MenuModel.build(view { $0.meeting = .init(state: .finishing(left: 1)) })
        #expect(find(meeting, "Meeting language")?.enabled == false)
        #expect(find(meeting, "Dictation language")?.enabled == true)
        #expect(find(MenuModel.build(view { $0.meeting = .init(state: .done(speakers: 2)) }), "Meeting language")?.enabled == true)
    }

    @Test func problemsComeFirstInAGroupOfTheirOwn() {
        let items = MenuModel.build(view { $0.configErrors = [#"settings.json: "mode" bad"#]; $0.hotkeyProblem = "Hotkey taken" })
        #expect(items[0].title == #"⚠ settings.json: "mode" bad"#)
        #expect(items[1].title == "⚠ Hotkey taken")
        #expect(!items[0].enabled && !items[1].enabled)
        #expect(items[2] == .separator && items[3].title == "Start meeting transcript")
    }

    @Test func missingPermissionsAreClickable() {
        let items = MenuModel.build(view { $0.accessibilityGranted = false; $0.microphoneDenied = true })
        #expect(items[0].action == .grantAccessibility)
        #expect(items[1].action == .grantMicrophone)
    }

    @Test func actionItemsCarryTheirActions() {
        let items = MenuModel.build(view())
        #expect(find(items, "Quit Shepit")?.action == .quit)
        #expect(find(items, "About Shepit")?.action == .about)
        #expect(find(items, "Add word to dictionary…")?.action == .addToDictionary)
        #expect(find(items, "Settings…")?.action == .openSettings)
    }

    @Test func copyLastDictationCopiesTheNewestEntryWhateverRecentShows() {
        #expect(find(MenuModel.build(view()), "Copy last dictation")?.enabled == false)
        let items = MenuModel.build(view {
            $0.settings.historyMenuItems = 0
            $0.history = [entry("new", at(6, 14, 32)), entry("old", at(6, 14, 28))]
        })
        #expect(find(items, "Copy last dictation")?.enabled == true)
        #expect(find(items, "Copy last dictation")?.action == .copyText("new"))
    }

    @Test func theMenuKeepsItsItemsDuringAMeeting() {
        let items = MenuModel.build(view { $0.meeting = .init(state: .recording(elapsed: 5, waiting: 0)) })
        for title in ["Add word to dictionary…", "Dictation language", "Recent dictations"] { #expect(find(items, title)?.enabled == true) }
    }

    @Test func recentSubmenuListsEntriesAndCopiesTheFullText() {
        let v = view {
            $0.now = at(6, 18, 0)
            $0.history = [entry("Треба задеплоїти цей pull request", at(6, 14, 32)), entry("Вчора", at(5, 9, 1))]
        }
        let recent = find(MenuModel.build(v), "Recent dictations")?.submenu ?? []
        #expect(recent.map(\.title) == ["14:32 · Треба задеплоїти цей pull request", "05.10 09:01 · Вчора"])
        #expect(recent[0].tooltip == "Треба задеплоїти цей pull request")
        #expect(recent[0].action == .copyText("Треба задеплоїти цей pull request"))
    }

    @Test func recentShortensLongText() {
        let long = String(repeating: "слово ", count: 20)
        let title = find(MenuModel.build(view { $0.now = at(6, 18, 0); $0.history = [entry(long, at(6, 14, 32))] }), "Recent dictations")?.submenu?.first?.title
        #expect(title?.hasPrefix("14:32 · слово") == true)
        #expect(title?.hasSuffix("слово…") == true)
        #expect((title?.count ?? 0) < long.count)
    }

    @Test func recentKeepsALabelOnOneLineAndCopiesTheLineBreaks() {
        let item = find(MenuModel.build(view { $0.now = at(6, 18, 0); $0.history = [entry("Перший рядок\n\nдругий", at(6, 14, 32))] }), "Recent dictations")?.submenu?.first
        #expect(item?.title == "14:32 · Перший рядок другий")
        #expect(item?.action == .copyText("Перший рядок\n\nдругий"))
    }

    @Test func recentSubmenuShowsAPlaceholderWhenHistoryIsEmpty() {
        #expect(find(MenuModel.build(view()), "Recent dictations")?.submenu == [MenuItem(title: "No dictations yet", enabled: false)])
    }

    @Test func recentSubmenuIsHiddenWhenTheSettingIsZero() {
        #expect(find(MenuModel.build(view { $0.settings.historyMenuItems = 0 }), "Recent dictations") == nil)
    }

    @Test func recentSubmenuListsAsManyAsTheSettingSays() {
        let history = (0..<12).map { entry("\($0)", at(6, 14, 10 + $0)) }
        let recent = find(MenuModel.build(view { $0.settings.historyMenuItems = 3; $0.history = history }), "Recent dictations")?.submenu ?? []
        #expect(recent.map(\.tooltip) == ["0", "1", "2"])
    }

    // Meetings (spec §5.6)

    @Test func meetingDotWhileASessionRuns() {
        for state: MeetingState in [.recording(elapsed: 5, waiting: 0), .finishing(left: 1), .detectingSpeakers] {
            #expect(MenuModel.icon(view { $0.meeting = .init(state: state) }) == MenuIcon(mark: .ready, meeting: true), "\(state)")
        }
        for state: MeetingState in [.idle, .done(speakers: 2), .interrupted] {
            #expect(MenuModel.icon(view { $0.meeting = .init(state: state) }) == MenuIcon(mark: .ready, meeting: false), "\(state)")
        }
        let recording = MeetingState.recording(elapsed: 5, waiting: 0)
        #expect(MenuModel.icon(view { $0.meeting = .init(state: recording); $0.state = .recording }) == MenuIcon(mark: .recording, meeting: true))
        #expect(MenuModel.icon(view { $0.meeting = .init(state: recording); $0.hotkeyProblem = "Hotkey taken" }) == MenuIcon(mark: .problem, meeting: true))
    }

    @Test func meetingStatusLines() {
        #expect(MenuModel.meetingLine(.recording(elapsed: 754, waiting: 2), title: "Weekly sync") == "⏺ Recording · Weekly sync · 12:34 · 2 phrases waiting")
        #expect(MenuModel.meetingLine(.recording(elapsed: 3_725, waiting: 1)) == "⏺ Recording · 1:02:05 · 1 phrase waiting")
        #expect(MenuModel.meetingLine(.recording(elapsed: 9, waiting: 0), title: "Weekly sync") == "⏺ Recording · Weekly sync · 0:09")
        #expect(MenuModel.meetingLine(.finishing(left: 3)) == "Meeting: finishing (3 left)")
        #expect(MenuModel.meetingLine(.detectingSpeakers) == "Meeting: detecting speakers…")
        #expect(MenuModel.meetingLine(.idle) == nil)
        let long = MenuModel.meetingLine(.recording(elapsed: 9, waiting: 0), title: String(repeating: "Quarterly planning ", count: 6)) ?? ""
        #expect(long.count < 70 && long.hasSuffix("… · 0:09"))
        let items = MenuModel.build(view { $0.meeting = .init(state: .finishing(left: 1)) })
        #expect(items[0].title == "Meeting: finishing (1 left)" && !items[0].enabled)
        let named = MenuModel.build(view { $0.meeting = .init(state: .recording(elapsed: 9, waiting: 0)); $0.meeting?.title = "Weekly sync" })
        #expect(named[0].title == "⏺ Recording · Weekly sync · 0:09")
        #expect(named[1].title == "Stop meeting transcript")
    }

    @Test func meetingStartAndStopItems() {
        let idle = MenuModel.build(view())
        #expect(find(idle, "Start meeting transcript")?.action == .startMeeting)
        for gone in ["Copy last meeting transcript", "Rename speakers…", "Rename speakers in another note…", "Open meetings folder"] {
            #expect(find(idle, gone) == nil, "\(gone)") // in the window's Meetings section now
        }
        #expect(find(MenuModel.build(view { $0.meeting = .init(state: .recording(elapsed: 1, waiting: 0)) }), "Stop meeting transcript")?.action == .stopMeeting)
        let finishing = find(MenuModel.build(view { $0.meeting = .init(state: .finishing(left: 2)) }), "Start meeting transcript")
        #expect(finishing?.enabled == false)
        let missing = MenuModel.build(view { $0.meetingModels = [.diarization] }) // no voice detection
        #expect(find(missing, "Start meeting transcript (download the model in Settings)")?.enabled == false)
        #expect(find(MenuModel.build(view { $0.meeting = .init(state: .done(speakers: 1)) }), "Start meeting transcript")?.enabled == true)
    }
}
