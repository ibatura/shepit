import Testing
@testable import ShepitCore

struct StatusTextTests {
    @Test func amountsNameTheirLargestWholeUnit() {
        #expect([1, 45, 60, 90, 300, 3600, 7200].map(StatusText.seconds)
                == ["1 second", "45 seconds", "1 minute", "90 seconds", "5 minutes", "1 hour", "2 hours"])
        #expect([1, 6, 24, 72, 168, 720].map(StatusText.hours) == ["1 hour", "6 hours", "1 day", "3 days", "1 week", "30 days"])
        #expect([1, 30, 365, 730].map(StatusText.days) == ["1 day", "30 days", "1 year", "2 years"])
    }
}
