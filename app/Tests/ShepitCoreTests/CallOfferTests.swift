import Foundation
import Testing
@testable import ShepitCore

struct CallOfferTests {
    /// A state machine with a clock in seconds.
    private struct Machine {
        var offer = CallOffer()
        var settings = Settings.defaults
        var log: [CallOffer.Effect] = []

        @discardableResult mutating func send(_ event: CallOffer.Event, at seconds: Double) -> [CallOffer.Effect] {
            let effects = offer.handle(event, at: Date(timeIntervalSinceReferenceDate: seconds), settings: settings)
            log += effects
            return effects
        }

        /// Teams takes the microphone at 0 and the offer is up at 3.
        mutating func teamsCall() {
            send(.took(.app(.teams), pid: 1), at: 0)
            send(.tick, at: 3)
        }

        var panel: CallOffer.Panel? { offer.panel }
    }

    @Test func bundleIDsOfTheProbedProcesses() {
        #expect(CallSource(bundleID: "com.microsoft.teams2.modulehost") == .app(.teams))
        #expect(CallSource(bundleID: "us.zoom.xos") == .app(.zoom))
        #expect(CallSource(bundleID: "com.google.Chrome.helper") == .browser)
        #expect(CallSource(bundleID: "com.microsoft.edgemac") == .browser)
        #expect(CallSource(bundleID: "com.anthropic.claudefordesktop.helper") == nil)
        #expect(CallSource(bundleID: "dev.shepit.Shepit") == nil)
        #expect(CallSource(bundleID: "") == nil)
    }

    @Test func underThreeSecondsOfMicrophoneIsNoCall() {
        var m = Machine()
        m.send(.took(.app(.zoom), pid: 1), at: 0)
        m.send(.tick, at: 2)
        #expect(m.panel == nil)
        m.send(.released(pid: 1), at: 2.5)
        m.send(.tick, at: 6)
        #expect(m.panel == nil && m.log.isEmpty)
        #expect(!m.offer.needsTick)
    }

    @Test func teamsAndZoomGetAnOfferAtThreeSeconds() {
        var m = Machine()
        m.send(.took(.app(.zoom), pid: 1), at: 0)
        #expect(m.offer.needsTick)
        #expect(m.send(.tick, at: 3) == [.lookForName])
        #expect(m.panel == .offer(title: "Zoom call", app: .zoom, hidesIn: 15))
    }

    @Test func theNameFillsInWhenFound() {
        var m = Machine()
        m.teamsCall()
        #expect(m.panel == .offer(title: "Teams call", app: .teams, hidesIn: 15))
        m.send(.named("Weekly sync"), at: 4)
        #expect(m.panel == .offer(title: "Weekly sync", app: .teams, hidesIn: 14))
        #expect(m.send(.pressedMain, at: 5) == [.start(title: "Weekly sync", app: .teams), .record(.started, app: .teams)])
        #expect(m.panel == nil)
    }

    @Test func aBrowserNeedsAMeetTab() {
        var m = Machine()
        m.send(.took(.browser, pid: 7), at: 0)
        #expect(m.send(.tick, at: 3) == [.lookForMeet])
        #expect(m.send(.meetFound(false), at: 3.5) == [])
        #expect(m.send(.tick, at: 13) == [])
        #expect(m.send(.tick, at: 13.5) == [.lookForMeet])
        #expect(m.send(.meetFound(true), at: 14) == [.lookForName])
        #expect(m.panel == .offer(title: "Meet call", app: .meet, hidesIn: 15))
    }

    @Test func offersOffOrAppOffGivesNothing() {
        var m = Machine()
        m.settings.callOffer = false
        m.teamsCall()
        #expect(m.panel == nil && m.log.isEmpty)

        var n = Machine()
        n.settings.callApps = ["Zoom"]
        n.teamsCall()
        n.send(.took(.browser, pid: 2), at: 4)
        n.send(.tick, at: 8)
        #expect(n.panel == nil && n.log.isEmpty && !n.offer.needsTick)
    }

    @Test func theOfferHidesByTime() {
        var m = Machine()
        m.teamsCall()
        m.send(.tick, at: 10)
        #expect(m.panel == .offer(title: "Teams call", app: .teams, hidesIn: 8))
        #expect(m.send(.tick, at: 18) == [.record(.hidden, app: .teams)])
        #expect(m.panel == nil && !m.offer.needsTick)
    }

    @Test func zeroSecondsKeepsTheOfferUntilAButton() {
        var m = Machine()
        m.settings.callOfferSeconds = 0
        m.teamsCall()
        m.send(.tick, at: 600)
        #expect(m.panel == .offer(title: "Teams call", app: .teams, hidesIn: nil))
    }

    @Test func aDismissedCallGetsNoSecondOfferButTheNextCallDoes() {
        var m = Machine()
        m.teamsCall()
        #expect(m.send(.pressedOther, at: 4) == [.record(.dismissed, app: .teams)])
        m.send(.tick, at: 60)
        #expect(m.panel == nil)
        m.send(.released(pid: 1), at: 100)
        m.send(.tick, at: 103)
        m.send(.took(.app(.teams), pid: 1), at: 200)
        m.send(.tick, at: 203)
        #expect(m.panel == .offer(title: "Teams call", app: .teams, hidesIn: 15))
    }

    @Test func automaticStartCountsDownAndStarts() {
        var m = Machine()
        m.settings.callAutoStart = true
        m.teamsCall()
        #expect(m.panel == .autoStart(title: "Teams call", app: .teams, startsIn: 5))
        m.send(.tick, at: 6)
        #expect(m.panel == .autoStart(title: "Teams call", app: .teams, startsIn: 2))
        #expect(m.send(.tick, at: 8) == [.start(title: nil, app: .teams), .record(.startedAutomatically, app: .teams)])
        #expect(m.panel == nil)
    }

    @Test func dontRecordCancelsAutomaticStart() {
        var m = Machine()
        m.settings.callAutoStart = true
        m.teamsCall()
        m.send(.pressedOther, at: 4)
        m.send(.tick, at: 20)
        #expect(m.log == [.lookForName, .record(.dismissed, app: .teams)])
    }

    @Test func nothingStartsWithoutAClickWhenAutomaticStartIsOff() {
        var m = Machine()
        m.teamsCall()
        for second in stride(from: 4.0, to: 300, by: 1) { m.send(.tick, at: second) }
        #expect(!m.log.contains { if case .start = $0 { true } else { false } })
    }

    @Test func noOfferWhileATranscriptRunsAndNoneLaterForThatCall() {
        var m = Machine()
        m.send(.sessionStarted(byPanel: false), at: 0)
        m.send(.took(.app(.teams), pid: 1), at: 10)
        m.send(.tick, at: 13)
        #expect(m.panel == nil)
        m.send(.sessionStopping, at: 20)
        m.send(.sessionFinished(entries: 4, detail: "x"), at: 25)
        m.send(.pressedOther, at: 26)
        m.send(.tick, at: 40)
        #expect(m.panel == nil)
    }

    @Test func aShortGapIsTheSameCall() {
        var m = Machine()
        m.teamsCall()
        m.send(.pressedOther, at: 4)
        m.send(.released(pid: 1), at: 50)
        m.send(.took(.app(.teams), pid: 1), at: 52)
        m.send(.tick, at: 60)
        #expect(m.panel == nil) // still the dismissed call
    }

    @Test func theOfferClosesWhenTheCallEnds() {
        var m = Machine()
        m.teamsCall()
        m.send(.released(pid: 1), at: 5)
        #expect(m.send(.tick, at: 8) == [.record(.hidden, app: .teams)])
        #expect(m.panel == nil && !m.offer.needsTick)
    }

    @Test func theTranscriptStopsWhenItsCallEnds() {
        var m = Machine()
        m.teamsCall()
        m.send(.pressedMain, at: 4)
        m.send(.sessionStarted(byPanel: true), at: 4.2)
        m.send(.released(pid: 1), at: 100)
        m.send(.tick, at: 102)
        #expect(m.panel == nil)
        m.send(.tick, at: 103)
        #expect(m.panel == .ended(stopsIn: 10))
        #expect(m.send(.tick, at: 112) == [])
        #expect(m.send(.tick, at: 113) == [.stop])
        #expect(m.panel == nil)
    }

    @Test func keepRecordingKeepsItForTheRestOfTheSession() {
        var m = Machine()
        m.teamsCall()
        m.send(.pressedMain, at: 4)
        m.send(.sessionStarted(byPanel: true), at: 4.2)
        m.send(.released(pid: 1), at: 100)
        m.send(.tick, at: 103)
        m.send(.pressedMain, at: 105)
        #expect(m.panel == nil)
        m.send(.took(.app(.teams), pid: 1), at: 200)
        m.send(.tick, at: 203)
        m.send(.released(pid: 1), at: 300)
        m.send(.tick, at: 400)
        #expect(m.panel == nil && !m.log.contains(.stop))
    }

    @Test func stopNowStopsAtOnce() {
        var m = Machine()
        m.teamsCall()
        m.send(.pressedMain, at: 4)
        m.send(.sessionStarted(byPanel: true), at: 4.2)
        m.send(.released(pid: 1), at: 100)
        m.send(.tick, at: 103)
        #expect(m.send(.pressedOther, at: 104) == [.stop])
        #expect(m.panel == nil)
    }

    @Test func aTranscriptStartedByHandDuringACallBelongsToIt() {
        var m = Machine()
        m.teamsCall()
        m.send(.sessionStarted(byPanel: false), at: 5)
        #expect(m.panel == nil) // the offer closes
        m.send(.released(pid: 1), at: 100)
        m.send(.tick, at: 103)
        #expect(m.panel == .ended(stopsIn: 10))
    }

    @Test func aTranscriptWithoutACallIsNeverStopped() {
        var m = Machine()
        m.send(.sessionStarted(byPanel: false), at: 0)
        m.send(.took(.app(.zoom), pid: 1), at: 10)
        m.send(.tick, at: 13)
        m.send(.released(pid: 1), at: 100)
        m.send(.tick, at: 200)
        #expect(m.panel == nil && m.log.isEmpty)
    }

    @Test func noStopPanelWhileTheSessionIsFinishing() {
        var m = Machine()
        m.teamsCall()
        m.send(.pressedMain, at: 4)
        m.send(.sessionStarted(byPanel: true), at: 4.2)
        m.send(.sessionStopping, at: 50)
        m.send(.released(pid: 1), at: 51)
        m.send(.tick, at: 60)
        #expect(m.panel == nil && !m.log.contains(.stop))
    }

    @Test func aNewCallCancelsTheStopCountdown() {
        var m = Machine()
        m.teamsCall()
        m.send(.pressedMain, at: 4)
        m.send(.sessionStarted(byPanel: true), at: 4.2)
        m.send(.released(pid: 1), at: 100)
        m.send(.tick, at: 103)
        m.send(.took(.app(.teams), pid: 1), at: 104)
        m.send(.tick, at: 107)
        #expect(m.panel == nil)
        m.send(.tick, at: 120)
        #expect(!m.log.contains(.stop))
    }

    @Test func aSecondAppIsIgnoredUntilTheFirstCallEnds() {
        var m = Machine()
        m.teamsCall()
        m.send(.pressedOther, at: 4)
        m.send(.took(.app(.zoom), pid: 2), at: 10)
        m.send(.tick, at: 20)
        #expect(m.panel == nil)
        m.send(.released(pid: 1), at: 30)
        m.send(.tick, at: 33)
        m.send(.tick, at: 36)
        #expect(m.panel == .offer(title: "Zoom call", app: .zoom, hidesIn: 15))
    }

    @Test func aBreakRestartsTheThreeSeconds() {
        var m = Machine()
        m.send(.took(.app(.zoom), pid: 1), at: 0)
        m.send(.released(pid: 1), at: 1)
        m.send(.took(.app(.zoom), pid: 1), at: 2.5)
        m.send(.tick, at: 4)
        #expect(m.panel == nil)
        m.send(.tick, at: 5.5)
        #expect(m.panel == .offer(title: "Zoom call", app: .zoom, hidesIn: 15))
    }

    @Test func aTranscriptStartedByHandBeforeMeetIsConfirmedBelongsToTheCall() {
        var m = Machine()
        m.send(.took(.browser, pid: 7), at: 0)
        m.send(.sessionStarted(byPanel: false), at: 1)
        m.send(.tick, at: 3)
        m.send(.meetFound(true), at: 3.5)
        #expect(m.panel == nil)
        m.send(.released(pid: 7), at: 100)
        m.send(.tick, at: 103)
        #expect(m.panel == .ended(stopsIn: 10))
    }

    @Test func aTranscriptStartedWhileABrowserWithoutMeetHoldsTheMicrophoneIsNeverStopped() {
        var m = Machine()
        m.send(.took(.browser, pid: 7), at: 0)
        m.send(.sessionStarted(byPanel: false), at: 1)
        m.send(.tick, at: 3)
        m.send(.meetFound(false), at: 3.5)
        m.send(.released(pid: 7), at: 100)
        m.send(.tick, at: 200)
        #expect(m.panel == nil && !m.log.contains(.stop))
    }

    @Test func aQuickRejoinBeatsAShortStopCountdown() {
        var m = Machine()
        m.settings.callAutoStopSeconds = 3
        m.teamsCall()
        m.send(.pressedMain, at: 4)
        m.send(.sessionStarted(byPanel: true), at: 4.2)
        m.send(.released(pid: 1), at: 100)
        m.send(.tick, at: 103)
        m.send(.took(.app(.teams), pid: 1), at: 104)
        for second in stride(from: 105.0, through: 120, by: 1) { m.send(.tick, at: second) }
        #expect(m.panel == nil && !m.log.contains(.stop))
    }

    @Test func aBlipDuringTheStopCountdownOnlyDelaysTheStop() {
        var m = Machine()
        m.teamsCall()
        m.send(.pressedMain, at: 4)
        m.send(.sessionStarted(byPanel: true), at: 4.2)
        m.send(.released(pid: 1), at: 100)
        m.send(.tick, at: 103)
        m.send(.took(.app(.zoom), pid: 2), at: 104)
        m.send(.released(pid: 2), at: 105)
        for second in stride(from: 106.0, through: 125, by: 1) { m.send(.tick, at: second) }
        #expect(m.log.contains(.stop))
    }

    @Test func theNextCallIsAnAppBeforeABrowser() {
        var m = Machine()
        m.teamsCall()
        m.send(.pressedOther, at: 4)
        m.send(.took(.browser, pid: 2), at: 10)
        m.send(.took(.app(.zoom), pid: 9), at: 11)
        m.send(.released(pid: 1), at: 30)
        m.send(.tick, at: 33)
        m.send(.tick, at: 36)
        #expect(m.panel == .offer(title: "Zoom call", app: .zoom, hidesIn: 15))
    }

    @Test func anEmptyTranscriptOfACallIsRemoved() {
        var m = Machine()
        m.teamsCall()
        m.send(.pressedMain, at: 4)
        m.send(.sessionStarted(byPanel: true), at: 4.2)
        m.send(.sessionStopping, at: 20)
        #expect(m.send(.sessionFinished(entries: 0, detail: ""), at: 21) == [.removeEmptyNote])
        #expect(m.panel == nil)
    }

    @Test func aFinishedTranscriptShowsReadyForAWhile() {
        var m = Machine()
        m.send(.sessionStarted(byPanel: false), at: 0)
        m.send(.sessionStopping, at: 50)
        #expect(m.send(.sessionFinished(entries: 0, detail: "1 min"), at: 60) == []) // by hand, no call: kept
        #expect(m.panel == .ready(detail: "1 min"))
        m.send(.tick, at: 67)
        #expect(m.panel == .ready(detail: "1 min"))
        m.send(.tick, at: 68)
        #expect(m.panel == nil && !m.offer.needsTick)
    }

    @Test func namePeopleFromTheReadyPanel() {
        var m = Machine()
        m.send(.sessionStarted(byPanel: false), at: 0)
        m.send(.sessionFinished(entries: 3, detail: "d"), at: 60)
        #expect(m.send(.pressedMain, at: 61) == [.namePeople])
        #expect(m.panel == nil)
    }
}
