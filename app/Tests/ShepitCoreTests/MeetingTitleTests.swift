import Testing
@testable import ShepitCore

// Spec §5.4 "Meeting name". Sample titles, to be replaced with real ones from Task 11.
struct MeetingTitleTests {
    private func w(_ app: String, _ title: String, inCall: Bool = false) -> MeetingTitle.Window { .init(app: app, title: title, inCall: inCall) }

    @Test func newTeamsCallWindowIsTheOneWithTheMuteButton() {
        // Window titles as Teams showed them on the call of 2026-11-04.
        let windows = [w("Microsoft Teams", "Ivan/ Iryna: Sync with HR"),
                       w("Microsoft Teams", "Refinement: Phase 3 Requirements Gaps and Open Questions", inCall: true),
                       w("Microsoft Teams", "Calendar"), w("Google Chrome", "Meet - Other - Google Chrome")]
        #expect(MeetingTitle.detect(windows) == ("Refinement: Phase 3 Requirements Gaps and Open Questions", .teams))
        #expect(MeetingTitle.detect([w("Microsoft Teams", "Weekly sync | Microsoft Teams", inCall: true)]) == ("Weekly sync", .teams))
        #expect(MeetingTitle.detect([w("Microsoft Teams", "Calendar", inCall: true)]) == (nil, .teams))
        // The pre-join screen of a meeting with no name (2026-11-12).
        #expect(MeetingTitle.detect([w("Microsoft Teams", "Meeting join", inCall: true)]) == (nil, .teams))
    }

    @Test func teamsMeetingWindowGivesTheName() {
        let result = MeetingTitle.detect([w("Microsoft Teams", "Weekly sync | Microsoft Teams")])
        #expect(result.title == "Weekly sync" && result.app == .teams)
    }

    @Test func teamsMainViewsAreIgnored() {
        for title in ["Chat | Olha Barbara | Microsoft Teams", "Calendar | Calendar | Microsoft Teams", "Activity | Microsoft Teams", "Microsoft Teams"] {
            #expect(MeetingTitle.detect([w("Microsoft Teams", title)]).app == nil, "\(title)")
        }
    }

    @Test func aTeamsMeetingAmongOtherTeamsWindows() {
        let result = MeetingTitle.detect([w("Microsoft Teams", "Chat | Olha | Microsoft Teams"), w("Microsoft Teams", "Release review | Microsoft Teams")])
        #expect(result.title == "Release review")
    }

    @Test func meetTabInABrowser() {
        #expect(MeetingTitle.detect([w("Google Chrome", "Meet - Weekly sync - Google Chrome - Ivan (Work)")]) == ("Weekly sync", .meet))
        #expect(MeetingTitle.detect([w("Arc", "Meet – Design review")]) == ("Design review", .meet))
        #expect(MeetingTitle.detect([w("Safari", "Meet - abc-defg-hij")]) == (nil, .meet))
        #expect(MeetingTitle.detect([w("Google Chrome", "abc-defg-hij - Google Chrome")]) == (nil, .meet))
        // Chrome during a call, 2026-11-06.
        #expect(MeetingTitle.detect([w("Google Chrome", "Meet: \"qbu-gkgc-bjh\" – Camera and microphone recording - Google Chrome – Ivan (Ivan (private))")]) == (nil, .meet))
        #expect(MeetingTitle.detect([w("Google Chrome", "Meet: \"Weekly sync\" – Microphone recording – Part of group Work - Google Chrome – Ivan")]) == ("Weekly sync", .meet))
        #expect(MeetingTitle.detect([w("Google Chrome", "Meet - Weekly sync - Audio playing - Google Chrome")]) == ("Weekly sync", .meet))
    }

    @Test func otherWindowsGiveNothing() {
        #expect(MeetingTitle.detect([w("Google Chrome", "Inbox - Gmail - Google Chrome"), w("Finder", "Meet - x")]) == (nil, nil))
        #expect(MeetingTitle.detect([]) == (nil, nil))
    }

    @Test func teamsWinsOverMeet() {
        #expect(MeetingTitle.detect([w("Google Chrome", "Meet - A"), w("Microsoft Teams", "B | Microsoft Teams")]) == ("B", .teams))
    }

    @Test func zoomCallGivesTheAppAndATopicWhenTheTitleHasOne() {
        #expect(MeetingTitle.detect([w("zoom.us", "Zoom Meeting")]) == (nil, .zoom))
        #expect(MeetingTitle.detect([w("zoom.us", "Zoom Workplace", inCall: true)]) == (nil, .zoom))
        #expect(MeetingTitle.detect([w("zoom.us", "Design review", inCall: true)]) == ("Design review", .zoom))
        #expect(MeetingTitle.detect([w("zoom.us", "Zoom Workplace")]) == (nil, nil)) // the app open, no call
    }

    @Test func aMeetTabThatIsNotTheActiveOneIsFound() {
        // Tabs are listed as windows of the browser too.
        let windows = [w("Google Chrome", "Inbox - Gmail - Google Chrome"), w("Google Chrome", "Meet - Weekly sync")]
        #expect(MeetingTitle.detect(windows) == ("Weekly sync", .meet))
    }

    @Test func muteLabelsOfTeamsMeetAndZoom() {
        for label in ["Unmute mic", "Turn on microphone (⌘ + d)", "Unmute audio", "Увімкнути мікрофон"] { #expect(MeetingTitle.micMuted(byLabel: label) == true, "\(label)") }
        for label in ["Mute All", "Unmute All", "Ask All to Unmute", "Mute participants upon entry", "Mute tab", "Unmute site", "Mute notifications"] { #expect(MeetingTitle.micMuted(byLabel: label) == nil, "\(label)") }
        #expect(MeetingTitle.micMuted(byLabel: "Mute call audio") == false) // "call" holds "all" but isn't it
        for label in ["Mute mic", "Turn off microphone (⌘ + d)", "Mute audio", "Mute my audio"] { #expect(MeetingTitle.micMuted(byLabel: label) == false, "\(label)") }
        for label in ["Camera", "Leave", "Microsoft Teams", ""] { #expect(MeetingTitle.micMuted(byLabel: label) == nil, "\(label)") }
    }
}
