import Foundation
import Testing
@testable import ShepitCore

// Spec §5.4 "Content", §5.7 Copy, §5.10, §6.
struct MeetingNoteTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        return calendar
    }()

    private func at(_ h: Int, _ m: Int, _ s: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 31, hour: h, minute: m, second: s))!
    }

    @Test func frontMatterWithTitleAndApp() {
        #expect(MeetingNote.frontMatter(start: at(14, 30, 5), title: "Weekly sync", app: "Teams", calendar: calendar) == """
        ---
        date: 2026-07-31
        time: "14:30"
        title: "Weekly sync"
        app: Teams
        tags: [transcript]
        ---

        """)
    }

    @Test func frontMatterWithoutTitleAndApp() {
        #expect(MeetingNote.frontMatter(start: at(9, 5, 0), title: nil, app: "", calendar: calendar) == """
        ---
        date: 2026-07-31
        time: "09:05"
        tags: [transcript]
        ---

        """)
    }

    @Test func titleQuotesAndBackslashesAreEscaped() {
        #expect(MeetingNote.frontMatter(start: at(9, 5, 0), title: #"Q4 "plan" \ review"#, app: nil, calendar: calendar)
            .contains(#"title: "Q4 \"plan\" \\ review""#))
    }

    @Test func entryMatchesTheUsersSample() {
        let text = MeetingNote.entry(label: "Ivan Kan", at: at(18, 22, 37), text: "all 40 years history of public data", calendar: calendar)
            + MeetingNote.entry(label: "Olha Barbara", at: at(18, 22, 45), text: "One. What's the urgency in Friday evening?", calendar: calendar)
        #expect(text == """
        [Ivan Kan] 2026-07-31 18:22:37
        all 40 years history of public data
        [Olha Barbara] 2026-07-31 18:22:45
        One. What's the urgency in Friday evening?

        """)
    }

    @Test func entryTextIsOneLine() {
        #expect(MeetingNote.entry(label: "A", at: at(1, 2, 3), text: "  перший\nрядок \t і   другий ", calendar: calendar)
            == "[A] 2026-07-31 01:02:03\nперший рядок і другий\n")
    }

    @Test func markdownMarkersAtTheStartAreEscaped() {
        func body(_ text: String) -> String {
            MeetingNote.entry(label: "A", at: at(1, 2, 3), text: text, calendar: calendar).split(separator: "\n")[1].description
        }
        #expect(body("# заголовок") == ##"\# заголовок"##)
        #expect(body("- пункт") == #"\- пункт"#)
        #expect(body("> цитата") == #"\> цитата"#)
        #expect(body("[Person 1] 2026-07-31 01:02:03") == #"\[Person 1] 2026-07-31 01:02:03"#)
        #expect(body("1. перше") == #"1\. перше"#)
        #expect(body("2026 рік") == "2026 рік")
        #expect(body("звичайний текст") == "звичайний текст")
    }

    @Test func stripFrontMatterKeepsTheBody() {
        let note = MeetingNote.frontMatter(start: at(9, 5, 0), title: "x", app: nil, calendar: calendar) + "[A] 2026-07-31 09:05:01\nтекст\n"
        #expect(MeetingNote.stripFrontMatter(note) == "[A] 2026-07-31 09:05:01\nтекст\n")
        #expect(MeetingNote.stripFrontMatter("[A] t\nтекст\n") == "[A] t\nтекст\n")
        #expect(MeetingNote.stripFrontMatter("---\nnot closed\n") == "---\nnot closed\n")
    }

    @Test func noticeLines() {
        #expect(MeetingNote.interruptedLine(at: at(15, 4, 9), calendar: calendar) == "⚠ Запис перервано о 15:04:09\n")
        #expect(MeetingNote.stoppedLine(.mine, at: at(15, 4, 9), calendar: calendar) == "⚠ Мікрофон перестав записувати о 15:04:09\n")
        #expect(MeetingNote.stoppedLine(.call, at: at(15, 4, 9), calendar: calendar) == "⚠ Звук дзвінка перестав записуватися о 15:04:09\n")
    }

    // Writer

    private func tempFile(_ relative: String) -> (URL, URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        return (dir.appending(path: relative), dir)
    }

    private func read(_ file: URL) throws -> String { try String(contentsOf: file, encoding: .utf8) }

    @Test func createMakesFoldersAndWritesFrontMatter() throws {
        let (file, dir) = tempFile("2026/07/note.md")
        defer { try? FileManager.default.removeItem(at: dir) }
        let writer = NoteWriter(file: file, frontMatter: "---\nx\n---\n")
        try writer.create()
        try writer.append("[A] t\nодин\n")
        try writer.append("[B] t\nдва\n")
        #expect(try read(file) == "---\nx\n---\n[A] t\nодин\n[B] t\nдва\n")
    }

    @Test func appendRecreatesADeletedNote() throws {
        let (file, dir) = tempFile("note.md")
        defer { try? FileManager.default.removeItem(at: dir) }
        let writer = NoteWriter(file: file, frontMatter: "---\nx\n---\n")
        try writer.create()
        try writer.append("[A] t\nодин\n")
        try FileManager.default.removeItem(at: dir)
        try writer.append("[B] t\nдва\n")
        #expect(try read(file) == "---\nx\n---\n[B] t\nдва\n")
    }

    @Test func appendAddsAMissingNewlineAfterTheUsersEdit() throws {
        let (file, dir) = tempFile("note.md")
        defer { try? FileManager.default.removeItem(at: dir) }
        let writer = NoteWriter(file: file, frontMatter: "---\nx\n---\n")
        try writer.create()
        try writer.append("[A] t\nодин\n")
        let handle = try FileHandle(forWritingTo: file)
        handle.seekToEndOfFile()
        handle.write(Data("моя примітка".utf8))
        try handle.close()
        try writer.append("[B] t\nдва\n")
        #expect(try read(file) == "---\nx\n---\n[A] t\nодин\nмоя примітка\n[B] t\nдва\n")
    }

    @Test func createFailsWhenTheFolderCannotBeMade() throws {
        let (blocker, dir) = tempFile("file")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data().write(to: blocker)
        #expect(throws: (any Error).self) { try NoteWriter(file: blocker.appending(path: "note.md"), frontMatter: "").create() }
    }

    // Reading a note and changing its title (Meetings design §4, §6, §8)

    private let written = """
    ---
    date: 2026-07-31
    time: "14:30"
    title: "Say \\"hi\\" \\\\ bye"
    app: Teams
    tags: [transcript]
    ---
    [Ivan Batura] 2026-07-31 14:30:05
    \\# not a heading
    [Person 1] 2026-07-31 14:30:09
    ⚠ не вдалося розпізнати
    ⚠ Мікрофон перестав записувати о 14:31:00
    [Person 2] 2026-07-31 14:31:02
    1\\. first
    second line added in Obsidian

    """

    @Test func parseReadsFrontMatterAndEntries() {
        let note = MeetingNote.parse(written, calendar: calendar)
        #expect(note.start == calendar.date(from: DateComponents(year: 2026, month: 7, day: 31, hour: 14, minute: 30)))
        #expect(note.title == #"Say "hi" \ bye"#)
        #expect(note.app == "Teams")
        #expect(note.entries == [
            .init(label: "Ivan Batura", timestamp: "2026-07-31 14:30:05", text: "# not a heading", line: 7),
            .init(label: "Person 1", timestamp: "2026-07-31 14:30:09", text: "⚠ не вдалося розпізнати", line: 9),
            .init(label: nil, timestamp: "", text: "⚠ Мікрофон перестав записувати о 14:31:00", line: 11),
            .init(label: "Person 2", timestamp: "2026-07-31 14:31:02", text: "1. first\nsecond line added in Obsidian", line: 12),
        ])
    }

    @Test func aWarningUnderAnEmptiedEntryIsALineOfItsOwn() {
        let note = MeetingNote.parse("[Me] 2026-07-31 14:30:05\n⚠ Запис перервано о 14:31:00\n", calendar: calendar)
        #expect(note.entries.map(\.label) == ["Me", nil])
    }

    @Test func parseWithoutFrontMatterOrHeaders() {
        let bare = MeetingNote.parse("[Me] 2026-07-31 14:30:05\nhello\n", calendar: calendar)
        #expect(bare.start == nil && bare.title == nil && bare.app == nil)
        #expect(bare.entries.map(\.line) == [0])
        #expect(MeetingNote.parse("---\ndate: 2026-07-31\n---\nJust text\n", calendar: calendar).entries.isEmpty)
    }

    @Test func parseReadsPlainAndSingleQuotedValuesAndCRLF() {
        let note = MeetingNote.parse("---\r\ndate: 2026-07-31\r\ntime: 09:05\r\ntitle: 'It''s on'\r\n---\r\n[Me] 2026-07-31 09:05:01\r\nhi\r\n", calendar: calendar)
        #expect(note.start == calendar.date(from: DateComponents(year: 2026, month: 7, day: 31, hour: 9, minute: 5)))
        #expect(note.title == "It's on")
        #expect(note.entries == [.init(label: "Me", timestamp: "2026-07-31 09:05:01", text: "hi", line: 5)])
    }

    @Test func timestampsReadBackAsDates() {
        #expect(MeetingNote.date("2026-07-31 14:30:05", calendar: calendar) == at(14, 30, 5))
        #expect(MeetingNote.date("2026-07-31 25:30:05", calendar: calendar) == nil)
    }

    @Test func settingTheTitleReplacesAddsOrRemovesOnlyThatLine() {
        let body = "[Me] 2026-07-31 14:30:05\ntitle: not front matter\n"
        let withTitle = "---\ndate: 2026-07-31\ntime: \"14:30\"\ntitle: \"Old\"\ntags: [transcript]\n---\n" + body
        let without = "---\ndate: 2026-07-31\ntime: \"14:30\"\ntags: [transcript]\n---\n" + body
        #expect(MeetingNote.settingTitle(withTitle, "New \"one\"") == withTitle.replacingOccurrences(of: #""Old""#, with: #""New \"one\"""#))
        #expect(MeetingNote.settingTitle(without, "New") == withTitle.replacingOccurrences(of: "Old", with: "New"))
        #expect(MeetingNote.settingTitle(withTitle, nil) == without)
        #expect(MeetingNote.settingTitle(withTitle, "  ") == without)
        #expect(MeetingNote.settingTitle(without, nil) == without)
        #expect(MeetingNote.settingTitle(body, "New") == body)
        let crlf = without.replacingOccurrences(of: "\n", with: "\r\n")
        #expect(MeetingNote.settingTitle(crlf, "Two\nlines") == withTitle.replacingOccurrences(of: "Old", with: "Two lines").replacingOccurrences(of: "\n", with: "\r\n"))
    }

}

struct MeetingFillerTests {
    @Test func entriesMadeOnlyOfSoundsAreFillers() {
        for text in ["Mm-hmm.", "you", "Uh...", "Hmm", "Угу.", "uh, um", "Mm-hmm. Mm-hmm."] { #expect(MeetingNote.isFiller(text), "\(text)") }
        for text in ["Mm-hmm, давай так", "You too", "Oh, what's", "Так", "Дякую.", "OK"] { #expect(!MeetingNote.isFiller(text), "\(text)") }
    }
}
