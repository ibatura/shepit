import Foundation
import Testing
@testable import ShepitCore

/// The file-name examples in README.md (Settings → meetingFileName).
struct ReadmeExamplesTests {
    @Test func meetingFileNameExamples() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 14, minute: 5))!
        func name(_ template: String, _ title: String?) -> String {
            MeetingFileName.relativePath(template, start: start, title: title, app: "Teams", calendar: calendar)
        }
        #expect(name("{date} {time} {title}", "Weekly sync") == "2026-10-26 14-05 Weekly sync.md")
        #expect(name("Meetings/{year}/{month}/{date} {title}", "Weekly sync") == "Meetings/2026/10/2026-10-26 Weekly sync.md")
        #expect(name("{date} {app} {title}", "Weekly sync") == "2026-10-26 Teams Weekly sync.md")
        #expect(name("{date} {time} {title}", nil) == "2026-10-26 14-05.md")
    }
}
