import Foundation

extension DateFormatter {
    /// English dates in the calendar's time zone, whatever the Mac's language (labels are English).
    static func english(_ format: String, _ calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // Gregorian whatever the Mac's calendar, so a year is 2026, not 2569.
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        formatter.calendar = gregorian
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter
    }
}
