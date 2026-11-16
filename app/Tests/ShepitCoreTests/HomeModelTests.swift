import Foundation
import Testing
@testable import ShepitCore

private let turbo = EngineChoice(engine: .whispercpp, model: "large-v3-turbo")
private let kit = EngineChoice(engine: .whisperkit, model: "large-v3")

private func home(_ change: (inout AppSnapshot) -> Void = { _ in }) -> Home {
    var view = AppSnapshot()
    view.downloaded = [turbo]
    view.now = at(6, 18, 0)
    change(&view)
    return HomeModel.build(view)
}

private func at(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

private func entry(_ text: String, _ time: Date, app: String? = nil) -> DictationStore.Entry {
    .init(id: 0, time: time, appName: app, appBundleID: nil, text: text, words: 1)
}

// Window shell design §5.
struct HomeModelTests {
    @Test func statusIsTheMenusStatusLine() {
        #expect(home().status == "Ready — whisper.cpp large-v3-turbo")
        #expect(home { $0.state = .recording }.status == "Recording… (Esc to cancel)")
        #expect(home { $0.load = .failed("x") }.status == "Error: x")
    }

    @Test func controlsWaitForTheJobThatUsesThem() {
        #expect(!home().dictating && home().microphoneEnabled)
        let dictating = home { $0.state = .recording }
        #expect(dictating.dictating && !dictating.microphoneEnabled)
        let meeting = home { $0.meeting = .init(state: .recording(elapsed: 1, waiting: 0)) }
        #expect(!meeting.dictating && !meeting.microphoneEnabled)
    }

    @Test func theConfiguredMicrophoneIsListedEvenWhenNotConnected() {
        #expect(home { $0.microphones = ["Built-in"]; $0.settings.microphone = "Built-in" }.microphones == ["Built-in"])
        #expect(home { $0.microphones = ["Built-in"]; $0.settings.microphone = "AirPods" }.microphones == ["Built-in", "AirPods"])
        #expect(home { $0.microphones = ["Built-in"] }.microphones == ["Built-in"])
    }

    @Test func aWarningForEachProblem() {
        #expect(home().warnings.isEmpty)
        let warnings = home { $0.hotkeyProblem = "Hotkey taken"; $0.accessibilityGranted = false; $0.microphoneDenied = true }.warnings
        #expect(warnings == [
            Home.Warning(text: "Hotkey taken"),
            Home.Warning(text: "Accessibility not granted (needed to paste)", button: .init(title: "Allow…", action: .grantAccessibility)),
            Home.Warning(text: "Microphone access denied", button: .init(title: "Open System Settings", action: .grantMicrophone)),
        ])
    }

    @Test func oneEngineRowPerJobWithTheDownloadedPairs() {
        let rows = home { $0.downloaded = [turbo, kit]; $0.settings.engines[.meetings] = kit }.engines
        #expect(rows.map(\.task) == [.dictation, .preview, .meetings])
        #expect(rows.map(\.title) == ["Dictation", "Live draft", "Meetings"])
        #expect(rows[0].hint == "The text that gets pasted")
        #expect(rows[0].choices.map(\.title) == ["whisper.cpp · large-v3-turbo", "WhisperKit · large-v3"])
        #expect(rows[0].current == turbo && rows[2].current == kit)
        #expect(rows.map(\.enabled) == [true, true, true])
        #expect(EngineChoice(engine: .apple, model: "").pairTitle == "Apple Speech")
    }

    @Test func aConfiguredPairThatIsNotDownloadedIsStillListed() {
        let row = home { $0.settings.engines[.dictation] = kit }.engines[0]
        #expect(row.choices.map(\.title) == ["whisper.cpp · large-v3-turbo", "WhisperKit · large-v3 (not downloaded)"])
        #expect(row.current == kit)
    }

    @Test func anEnginePickerIsOffWhileItsJobRuns() {
        #expect(home { $0.state = .transcribing }.engines.map(\.enabled) == [false, false, true])
        #expect(home { $0.meeting = .init(state: .recording(elapsed: 1, waiting: 0)) }.engines.map(\.enabled) == [true, true, false])
        #expect(home { $0.meeting = .init(state: .finishing(left: 1)) }.engines.map(\.enabled) == [true, true, false])
    }

    @Test func meetingRowWithNoCall() {
        #expect(home().meeting == Home.MeetingRow(title: "No call right now", hint: "Shepit offers a transcript when a call starts",
                                                   button: .init(title: "Start transcript", action: .startMeeting)))
        #expect(home { $0.settings.callOffer = false }.meeting.hint == "Call offers are off")
        #expect(home { $0.meeting = .init(state: .done(speakers: 2)) }.meeting.button?.action == .startMeeting)
    }

    @Test func meetingRowWithADetectedCall() {
        let named = home { $0.call = CallOffer.Current(name: "Weekly sync", app: .teams) }.meeting
        #expect(named == Home.MeetingRow(title: "Weekly sync", hint: "Teams", button: .init(title: "Start transcript", action: .startCall)))
        let unnamed = home { $0.call = CallOffer.Current(name: nil, app: .zoom) }.meeting
        #expect(unnamed.title == "Zoom call" && unnamed.hint == nil && unnamed.button?.action == .startCall)
    }

    @Test func meetingRowWhileATranscriptRuns() {
        let recording = home {
            $0.meeting = .init(state: .recording(elapsed: 754, waiting: 2)); $0.meeting?.title = "Weekly sync"; $0.meeting?.app = .teams
            $0.call = CallOffer.Current(name: "Weekly sync", app: .teams)
        }.meeting
        #expect(recording == Home.MeetingRow(recording: true, title: "Weekly sync", hint: "Teams · 12:34 · 2 phrases waiting",
                                             button: .init(title: "Stop", action: .stopMeeting)))
        let bare = home { $0.meeting = .init(state: .recording(elapsed: 9, waiting: 0)) }.meeting
        #expect(bare.title == "Meeting transcript" && bare.hint == "0:09")
        #expect(home { $0.meeting = .init(state: .finishing(left: 3)) }.meeting == Home.MeetingRow(title: "Finishing the transcript (3 left)"))
        #expect(home { $0.meeting = .init(state: .detectingSpeakers) }.meeting == Home.MeetingRow(title: "Detecting speakers…"))
    }

    @Test func theSidebarCardShowsOnlyWhileATranscriptRuns() {
        #expect(home().card == nil)
        #expect(home { $0.meeting = .init(state: .done(speakers: 2)); $0.meeting?.title = "Weekly sync" }.card == nil)
        let named = home { $0.meeting = .init(state: .recording(elapsed: 754, waiting: 2)); $0.meeting?.title = "Weekly sync"; $0.meeting?.app = .teams }.card
        #expect(named == Home.Card(headline: "Recording 12:34", detail: "Weekly sync · Teams"))
        #expect(home { $0.meeting = .init(state: .finishing(left: 1)) }.card == Home.Card(headline: "Finishing", detail: ""))
        #expect(home { $0.meeting = .init(state: .detectingSpeakers) }.card?.headline == "Detecting speakers")
    }

    @Test func withoutTheModelStartIsOffButTheCallIsStillNamed() {
        let missing = "download the model in Settings"
        #expect(home { $0.meetingMissing = missing }.meeting
            == Home.MeetingRow(title: "No call right now", hint: "To start a transcript, \(missing)", button: .init(title: "Start transcript")))
        #expect(home { $0.meetingMissing = missing; $0.call = CallOffer.Current(name: nil, app: .zoom) }.meeting
            == Home.MeetingRow(title: "Zoom call", hint: "To start a transcript, \(missing)", button: .init(title: "Start transcript")))
        #expect(home { $0.meetingMissing = missing; $0.call = CallOffer.Current(name: "Weekly sync", app: .teams) }.meeting.hint
            == "Teams · To start a transcript, \(missing)")
    }

    @Test func lastDictationsWithTheirAppAndTheDateWhenNotToday() {
        let rows = home { $0.history = [entry("new", at(6, 14, 32), app: "Slack"), entry("old", at(5, 9, 1))] }.dictations
        #expect(rows == [Home.Dictation(text: "new", detail: "14:32 · Slack"), Home.Dictation(text: "old", detail: "05.10 09:01")])
    }

    @Test func homeListsTheLastTenWhateverWasRead() {
        let history = (0..<12).map { entry("\($0)", at(6, 14, 10 + $0)) }
        #expect(home { $0.history = history }.dictations.map(\.text) == (0..<10).map { "\($0)" })
    }

    @Test func theEmptyListSaysWhy() {
        #expect(home().dictations.isEmpty)
        #expect(home().noDictations == "No dictations yet")
        #expect(home { $0.settings.saveHistory = false }.noDictations == "History is off (Settings → History and privacy)")
    }
}
