import Foundation
import ShepitCore

/// `Shepit voices-check` (voices design §8): how well the saved voices would recognise the author's people, on the
/// samples in meetings.sqlite. Counts only: no names, no text.
enum VoicesCheck {
    static func run() -> Int32 {
        let settings = SettingsStore(file: Paths.settingsFile)
        settings.load()
        let store = MeetingStore(file: settings.settings.databasesFolderURL(home: Paths.home).appending(path: "meetings.sqlite"))
        do {
            let rows = try store.voiceRows()
            let meetings = Dictionary(grouping: rows, by: \.person).mapValues { Set($0.map(\.meeting)).count }
            print("\(rows.count) samples of \(meetings.count) people; \(meetings.values.filter { $0 > 1 }.count) of them in two meetings or more")
            print("match    threshold  recognised  wrong  missed  new, left alone")
            for match in Voices.Match.allCases {
                for threshold in stride(from: Float(0.3), through: 0.951, by: 0.05) {
                    let count = Voices.check(rows, match: match, threshold: threshold)
                    print(String(format: "%-8@ %9.2f  %10d  %5d  %6d  %d", "\(match)", threshold, count.recognised, count.wrong,
                                 count.missed, count.unknown))
                }
            }
            print("Now: \(Voices.threshold) with a margin of \(Voices.margin), by the mean.")
            return 0
        } catch {
            FileHandle.standardError.write(Data("voices-check: \(error.localizedDescription)\n".utf8))
            return 1
        }
    }
}
