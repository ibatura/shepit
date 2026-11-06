import Foundation
import Testing
@testable import ShepitCore

// Spec §5.4 "Folder and file name" and §5.9 validation.
struct MeetingFileNameTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        calendar.locale = Locale(identifier: "uk_UA")
        return calendar
    }()

    /// 2026-10-18 14:30:05 Kyiv time, a Sunday.
    private var start: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 14, minute: 30, second: 5))!
    }

    private func name(_ template: String, title: String? = nil, app: String? = nil) -> String {
        MeetingFileName.relativePath(template, start: start, title: title, app: app, calendar: calendar)
    }

    @Test func specExamples() {
        #expect(name("{date} {time} {title}", title: "Weekly sync") == "2026-10-18 14-30 Weekly sync.md")
        #expect(name("{date} {time} {title}") == "2026-10-18 14-30.md")
        #expect(name("{date} {title}", title: "Weekly sync") == "2026-10-18 Weekly sync.md")
        #expect(name("{year}/{month}/{date} {time} {app} {title}", title: "Weekly sync", app: "Teams")
            == "2026/10/2026-10-18 14-30 Teams Weekly sync.md")
        #expect(name("Meeting {date} {time}") == "Meeting 2026-10-18 14-30.md")
    }

    @Test func everyPlaceholder() {
        #expect(name("{year}-{month}-{day} {hour}.{minute} {weekday}") == "2026-10-18 14.30 Sun.md")
        #expect(name("{app}", app: "Meet") == "Meet.md")
    }

    @Test func weekdayIsEnglishWhateverTheLocale() {
        var other = calendar
        other.locale = Locale(identifier: "de_DE")
        #expect(MeetingFileName.relativePath("{weekday}", start: start, title: nil, app: nil, calendar: other) == "Sun.md")
    }

    @Test func timeHasNoColon() {
        #expect(!name("{time}").contains(":"))
    }

    @Test func emptyPartsAndSeparatorsAreCleanedUp() {
        #expect(name("{date} - {title} -- {app}") == "2026-10-18.md")
        #expect(name("{title}   ·  {date}") == "2026-10-18.md")
        #expect(name("{date}  {time}") == "2026-10-18 14-30.md")
        #expect(name("{app}/{date}") == "2026-10-18.md")
        #expect(name("_{title}_/x") == "x.md")
    }

    @Test func allEmptyFallsBackToDateAndTime() {
        #expect(name("{title}") == "2026-10-18 14-30.md")
        #expect(name("{title} - {app}") == "2026-10-18 14-30.md")
    }

    @Test func unsafeCharactersInTitleAndAppBecomeSpaces() {
        #expect(name("{title}", title: "Q4: plan/review [draft] #1 a|b\u{7}c") == "Q4 plan review draft 1 a b c.md")
        #expect(name("{app}", app: "Te*ams?") == "Te ams.md")
    }

    @Test func titleIsCappedAt80CharactersOfText() {
        let long = String(repeating: "Зустріч ", count: 20)
        let result = name("{title}", title: long)
        #expect(result.hasSuffix(".md"))
        #expect(result.dropLast(3).count <= 80)
        #expect(result.hasPrefix("Зустріч Зустріч"))
    }

    @Test func mdIsAddedOnce() {
        #expect(name("{date}.md") == "2026-10-18.md")
        #expect(name("{date}.MD") == "2026-10-18.MD")
        #expect(name("notes/{date}") == "notes/2026-10-18.md")
    }

    @Test func collisionsGetANumber() {
        let folder = URL(fileURLWithPath: "/m", isDirectory: true)
        let taken: Set<String> = ["/m/a/x.md", "/m/a/x (2).md"]
        #expect(MeetingFileName.unique("a/x.md", in: folder) { taken.contains($0.path) }.path == "/m/a/x (3).md")
        #expect(MeetingFileName.unique("a/y.md", in: folder) { taken.contains($0.path) }.path == "/m/a/y.md")
    }

    // Validation

    @Test func validTemplatesPass() {
        for template in ["{date} {time} {title}", "{year}/{month}/{date} {time} {app} {title}", "Meeting {date} {time}", "x"] {
            #expect(MeetingFileName.validate(template) == nil, "\(template)")
        }
    }

    @Test func invalidTemplatesSayWhy() {
        #expect(MeetingFileName.validate("") == "must have 1 to 200 characters")
        #expect(MeetingFileName.validate(String(repeating: "a", count: 201)) == "must have 1 to 200 characters")
        #expect(MeetingFileName.validate("{date} {room}") == "has unknown placeholder {room}; allowed: {date} {time} {year} {month} {day} {hour} {minute} {weekday} {title} {app}")
        #expect(MeetingFileName.validate("{date") == "has a { or } that is not part of a placeholder")
        #expect(MeetingFileName.validate("{date}: {title}") == #"must not contain any of \ : * ? " < > | # ^ [ ] outside placeholders"#)
        #expect(MeetingFileName.validate("/{date}") == "must not start with /")
        #expect(MeetingFileName.validate("a//{date}") == "must not have empty, . or .. folder parts")
        #expect(MeetingFileName.validate("../{date}") == "must not have empty, . or .. folder parts")
        #expect(MeetingFileName.validate("a/./{date}") == "must not have empty, . or .. folder parts")
        #expect(MeetingFileName.validate("{date}/") == "must not have empty, . or .. folder parts")
    }
}
