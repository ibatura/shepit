import Foundation
import Testing
@testable import Shepit
@testable import ShepitCore

// Back and forward design §4–6: the window's place, going back and forward, gone steps, the hints. The history itself
// is tested in BackForwardTests.
@MainActor
struct WindowNavigationTests {
    @MainActor
    private struct Rig {
        let navigation: WindowNavigation
        let meetings: MeetingsModel
        let people: PeopleModel
        let store: MeetingStore
        let dir: URL
        let suite: String
        /// Meeting 1 "Daily sync" with Olena and Marko, meeting 2 with Olena.
        let one: Int, two: Int
        let olena: Int, marko: Int

        func clean() {
            try? FileManager.default.removeItem(at: dir)
            UserDefaults().removePersistentDomain(forName: suite)
        }

        /// A change of place, then a wait for the navigation to record it on the main actor's next turn.
        func go(_ change: () -> Void) async {
            change()
            await settle()
        }

        func settle() async {
            for _ in 0..<3 { await Task.yield() }
        }
    }

    private func note(_ day: String, _ labels: [String]) -> String {
        "---\ndate: \(day)\ntime: \"10:00\"\n---\n"
            + labels.enumerated().map { "[\($1)] \(day) 10:00:0\($0 + 1)\ntext\n" }.joined(separator: "\n")
    }

    private func rig() throws -> Rig {
        let dir = FileManager.default.temporaryDirectory.appending(path: "window-navigation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = MeetingStore(file: dir.appending(path: "meetings.sqlite"))
        var ids: [Int] = []
        for (name, text) in [("a", note("2026-07-31", ["Ivan", "Person 1", "Person 2"])), ("b", note("2026-08-01", ["Ivan", "Person 1"]))] {
            let file = dir.appending(path: "\(name).md")
            try Data(text.utf8).write(to: file)
            ids.append(try #require(try store.add(note: file, you: "Ivan")))
        }
        try store.rename(ids[0], title: "Daily sync")
        try store.setName(ids[0], person: "Person 1", to: "Olena")
        try store.setName(ids[0], person: "Person 2", to: "Marko")
        try store.setName(ids[1], person: "Person 1", to: "Olena")
        let suite = "window-navigation-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let meetings = MeetingsModel(store: store, settings: { .defaults }, defaults: defaults)
        let people = PeopleModel(store: store, settings: { .defaults }, defaults: defaults)
        meetings.reload()
        people.reload()
        let olena = try #require(try store.people(ids[0])[1].person), marko = try #require(try store.people(ids[0])[2].person)
        return Rig(navigation: WindowNavigation(meetings: meetings, people: people, defaults: defaults), meetings: meetings,
                   people: people, store: store, dir: dir, suite: suite, one: ids[0], two: ids[1], olena: olena, marko: marko)
    }

    @Test func thePlaceIsTheSectionAndItsChoice() async throws {
        let r = try rig()
        defer { r.clean() }
        #expect(r.navigation.place == .section(.home))
        r.navigation.section = .people
        r.people.selection = r.olena
        #expect(r.navigation.place == .people(r.olena))
        r.meetings.selection = .meeting(r.two) // not the section shown
        #expect(r.navigation.place == .people(r.olena))
        r.navigation.openSettings(.engines)
        #expect(r.navigation.place == .settings(.engines))
    }

    @Test func backAndForwardShowTheStepWithItsChoice() async throws {
        let r = try rig()
        defer { r.clean() }
        await r.go { r.navigation.section = .people; r.people.selection = r.olena }
        await r.go { r.navigation.section = .meetings; r.meetings.selection = .meeting(r.two) } // Open in Meetings
        await await r.go { r.navigation.back() } // the place it gives is no new step
        #expect(r.navigation.section == .people && r.people.selection == r.olena)
        #expect(r.navigation.canGoForward)
        r.meetings.selection = .meeting(r.one) // chosen elsewhere meanwhile
        r.navigation.forward()
        #expect(r.navigation.place == .meetings(.meeting(r.two)))
        r.navigation.back()
        r.navigation.back()
        #expect(r.navigation.place == .section(.home))
        #expect(!r.navigation.canGoBack)
    }

    @Test func aRemovedMeetingIsSkipped() async throws {
        let r = try rig()
        defer { r.clean() }
        await r.go { r.navigation.section = .meetings; r.meetings.selection = .meeting(r.one) }
        await r.go { r.navigation.section = .people; r.people.selection = r.olena }
        try r.store.remove(r.one)
        r.navigation.back()
        #expect(r.navigation.place == .section(.home))
    }

    @Test func aMergedPersonIsSkipped() async throws {
        let r = try rig()
        defer { r.clean() }
        await r.go { r.navigation.section = .people; r.people.selection = r.marko }
        let marko = try #require(r.people.people.first { $0.id == r.marko })
        let olena = try #require(r.people.people.first { $0.id == r.olena })
        await r.people.merge(marko, into: olena)
        await r.go {}
        #expect(r.navigation.place == .people(r.olena))
        r.navigation.back()
        #expect(r.navigation.place == .section(.home))
    }

    /// People's list still has Marko: it is read only when the section appears.
    @Test func aPersonLeftWithNoLinesByAnEditInMeetingsIsSkipped() async throws {
        let r = try rig()
        defer { r.clean() }
        await r.go { r.navigation.section = .people; r.people.selection = r.marko }
        await r.go { r.navigation.section = .meetings; r.meetings.selection = .meeting(r.one) }
        try r.store.give(r.one, line: try r.store.lines(r.one)[2].place, to: "Person 1") // his only line
        #expect(r.people.people.contains { $0.id == r.marko })
        r.navigation.back()
        #expect(r.navigation.place == .section(.home))
    }

    @Test func theRunningTranscriptsStepsBecomeTheMeetings() async throws {
        let r = try rig()
        defer { r.clean() }
        r.meetings.setLive(LiveMeeting(state: .recording(elapsed: 1, waiting: 0)))
        await r.go { r.navigation.section = .meetings; r.meetings.selection = .running } // the recording card
        await r.go { r.navigation.section = .home }
        #expect(r.navigation.backHint == "Back to Meetings: the running transcript")
        r.meetings.setLive(nil)
        r.navigation.finished(running: r.two)
        r.navigation.back()
        #expect(r.navigation.place == .meetings(.meeting(r.two)))
        #expect(r.meetings.selection == .meeting(r.two))
    }

    @Test func aRunningTranscriptThatWasNotListedIsSkipped() async throws {
        let r = try rig()
        defer { r.clean() }
        r.meetings.setLive(LiveMeeting(state: .recording(elapsed: 1, waiting: 0)))
        await r.go { r.navigation.section = .meetings; r.meetings.selection = .running }
        await r.go { r.navigation.section = .dictations }
        r.meetings.setLive(nil)
        r.navigation.back()
        #expect(r.navigation.place == .section(.home))
    }

    @Test func theHintsSayWhereTheArrowsGo() async throws {
        let r = try rig()
        defer { r.clean() }
        #expect(r.navigation.backHint == "Back")
        #expect(r.navigation.forwardHint == "Forward")
        await r.go { r.navigation.openSettings(.engines) }
        await r.go { r.navigation.section = .people; r.people.selection = r.olena }
        await r.go { r.navigation.section = .meetings; r.meetings.selection = .meeting(r.one) }
        #expect(r.navigation.backHint == "Back to People: Olena")
        r.navigation.back()
        #expect(r.navigation.backHint == "Back to Settings: Engines and models")
        #expect(r.navigation.forwardHint == "Forward to Meetings: Daily sync")
        r.navigation.back()
        #expect(r.navigation.backHint == "Back to Home")
        await r.go { r.navigation.section = .meetings; r.meetings.selection = nil }
        #expect(r.navigation.backHint == "Back to Settings: Engines and models")
        await r.go { r.navigation.section = .statistics }
        #expect(r.navigation.backHint == "Back to Meetings")
    }
}
