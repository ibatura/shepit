import Foundation
import Testing
@testable import ShepitCore

// Meetings design §8 "The meeting's name".
struct MeetingRenameTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        return calendar
    }()

    private var start: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 14, minute: 30, second: 5))! }

    // The new file name

    private func renamed(_ template: String, _ title: String?, note: String = "/n/2026-10-18 14-30 Old.md",
                         taken: Set<String> = []) -> String {
        MeetingFileName.renamed(URL(fileURLWithPath: note), template: template, start: start, title: title, app: "Teams",
                                calendar: calendar) { taken.contains($0.path) || $0.path == note }.path
    }

    @Test func theTemplateIsFilledAgainInTheNotesFolder() {
        #expect(renamed("{date} {time} {title}", "New") == "/n/2026-10-18 14-30 New.md")
        #expect(renamed("{year}/{month}/{date} {app} {title}", "New", note: "/n/moved/x.md") == "/n/moved/2026-10-18 Teams New.md")
        #expect(renamed("{date} {time} {title}", nil) == "/n/2026-10-18 14-30.md")
        #expect(renamed("{date} {time} {title}", "New", taken: ["/n/2026-10-18 14-30 New.md"]) == "/n/2026-10-18 14-30 New (2).md")
    }

    @Test func theNoteItselfIsNotTakenAndATemplateWithoutTitleKeepsTheName() {
        #expect(renamed("{date} {time} {title}", "Old") == "/n/2026-10-18 14-30 Old.md")
        // A case change on a case-blind disk: the new name "exists", but it is the note itself.
        #expect(renamed("{date} {time} {title}", "OLD", taken: ["/n/2026-10-18 14-30 OLD.md"]) == "/n/2026-10-18 14-30 OLD.md")
        #expect(renamed("{date} {time}", "New", note: "/n/my own name.md") == "/n/my own name.md")
    }

    // meeting-names.json

    @Test func theRememberedNameOfThisStartChanges() {
        let entries = [MeetingNames.Entry(title: "Old", app: "Zoom", start: start), MeetingNames.Entry(title: "Other", app: nil, start: start.addingTimeInterval(-86400))]
        let later = start.addingTimeInterval(0.4) // the file keeps whole seconds
        #expect(MeetingNames.renaming(entries, start: later, to: "New", app: "Zoom").map(\.title) == ["New", "Other"])
        #expect(MeetingNames.renaming(entries, start: later, to: nil, app: "Zoom").map(\.title) == ["Other"])
        #expect(MeetingNames.renaming([entries[1]], start: later, to: "New", app: "Zoom")
                == [entries[1], MeetingNames.Entry(title: "New", app: "Zoom", start: later)])
    }

    // The whole rename

    private func setUp(note: String?) throws -> (MeetingStore, MeetingStore.Meeting, URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "meeting-rename-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let notes = dir.appending(path: "notes")
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        let file = notes.appending(path: "2026-10-18 14-30 Old.md")
        if let note { try Data(note.utf8).write(to: file) }
        let store = MeetingStore(file: dir.appending(path: "meetings.sqlite"))
        let id = try #require(try store.add(path: file.path, start: start, duration: 60, title: "Old", app: "Teams", you: "Me", entries: []))
        return (store, try store.meetings().first { $0.id == id }!, dir)
    }

    private let note = "---\ndate: 2026-10-18\ntime: \"14:30\"\ntitle: \"Old\"\napp: Teams\n---\n[Me] 2026-10-18 14:30:09\nhi\n"

    @Test func renameMovesTheNoteSetsItsTitleAndUpdatesTheStoreAndNames() throws {
        let (store, meeting, dir) = try setUp(note: note)
        defer { try? FileManager.default.removeItem(at: dir) }
        let names = dir.appending(path: MeetingNames.fileName)
        try MeetingNames.save([.init(title: "Old", app: "Teams", start: start)], to: names)
        try store.rename(meeting, to: "Sprint \"7\"", template: "{date} {time} {title}", namesFile: names, calendar: calendar)
        let moved = dir.appending(path: "notes/2026-10-18 14-30 Sprint 7.md")
        #expect(!FileManager.default.fileExists(atPath: meeting.path))
        #expect(try String(contentsOf: moved, encoding: .utf8) == note.replacingOccurrences(of: #""Old""#, with: #""Sprint \"7\"""#))
        #expect(try store.meetings().map { [$0.title, $0.path] } == [["Sprint \"7\"", moved.path]])
        #expect(MeetingNames.load(names).map(\.title) == ["Sprint \"7\""])
    }

    @Test func aMissingNoteChangesOnlyTheStoreAndNames() throws {
        let (store, meeting, dir) = try setUp(note: nil)
        defer { try? FileManager.default.removeItem(at: dir) }
        let names = dir.appending(path: MeetingNames.fileName)
        try store.rename(meeting, to: nil, template: "{date} {time} {title}", namesFile: names, calendar: calendar)
        #expect(try store.meetings().map { [$0.title, $0.path] } == [[nil, meeting.path]])
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.appending(path: "notes").path).isEmpty)
    }

    @Test func aFailedWriteChangesNothing() throws {
        let (store, meeting, dir) = try setUp(note: note)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.appending(path: "notes").path)
            try? FileManager.default.removeItem(at: dir)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.appending(path: "notes").path)
        #expect(throws: (any Error).self) {
            try store.rename(meeting, to: "New", template: "{date} {time} {title}", namesFile: dir.appending(path: "names.json"), calendar: calendar)
        }
        #expect(try store.meetings().map { [$0.title, $0.path] } == [["Old", meeting.path]])
        #expect(try String(contentsOf: URL(fileURLWithPath: meeting.path), encoding: .utf8) == note)
    }
}
