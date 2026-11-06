import Foundation
import Testing
@testable import ShepitCore

// Ported from tests/test_history.lua, plus WAV and failed-audio cases.
struct HistoryTests {
    private func date(_ stamp: String) -> Date {
        History.parse(stamp)!
    }

    private func tempFile(_ lines: [String]?) throws -> URL {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).log")
        if let lines {
            try (lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")).write(to: file, atomically: true, encoding: .utf8)
        }
        return file
    }

    private func read(_ file: URL) throws -> String {
        try String(contentsOf: file, encoding: .utf8)
    }

    @Test func formatPutsTimestampAndFlattensNewlines() {
        #expect(History.format("рядок 1\nрядок 2", at: date("2026-10-05 09:03:07")) == "2026-10-05 09:03:07\tрядок 1 рядок 2\n")
    }

    @Test func appendAddsLinesToTheFile() throws {
        let file = try tempFile(nil)
        defer { try? FileManager.default.removeItem(at: file) }
        try History.append("один", to: file, at: Date(timeIntervalSince1970: 0))
        try History.append("два", to: file, at: Date(timeIntervalSince1970: 0))
        let text = try read(file)
        #expect(text.filter { $0 == "\n" }.count == 2)
        #expect(text.contains("\tодин\n") && text.contains("\tдва\n"))
    }

    @Test func appendReportsAnUnwritablePath() {
        #expect(throws: (any Error).self) {
            try History.append("a", to: URL(fileURLWithPath: "/nonexistent-dir/x.log"), at: .now)
        }
    }

    @Test func recentReturnsTheNewestEntriesFirst() throws {
        let file = try tempFile(["2026-10-05 09:00:00\tперший", "2026-10-05 09:01:00\tдругий", "2026-10-05 09:02:00\tтретій"])
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(History.recent(file, count: 2) == [
            History.Entry(time: "2026-10-05 09:02:00", text: "третій"),
            History.Entry(time: "2026-10-05 09:01:00", text: "другий"),
        ])
        #expect(History.recent(file, count: 10).count == 3)
    }

    @Test func recentSkipsMalformedAndEmptyLines() throws {
        let file = try tempFile([
            "2026-10-05 09:00:00\t(history started)", "garbage line", "", "2026-10-05 09:01:00\t", "2026-10-05 09:02:00\tok",
        ])
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(History.recent(file, count: 10) == [History.Entry(time: "2026-10-05 09:02:00", text: "ok")])
    }

    @Test func recentHandlesAMissingFileAnEmptyFileAndZeroCount() throws {
        let missing = URL(fileURLWithPath: "/nonexistent/h.log")
        #expect(History.recent(missing, count: 5).isEmpty)
        let file = try tempFile([])
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(History.recent(file, count: 5).isEmpty)
        #expect(History.recent(missing, count: 0).isEmpty)
    }

    @Test func recentReadsOnlyTheTailOfALargeFile() throws {
        let file = try tempFile((1...5000).map { "2026-10-05 10:00:00\tрядок номер \($0) з текстом" })
        defer { try? FileManager.default.removeItem(at: file) }
        let recent = History.recent(file, count: 3)
        #expect(recent.first?.text == "рядок номер 5000 з текстом")
        #expect(recent.last?.text == "рядок номер 4998 з текстом")
    }

    @Test func labelShowsTimeForTodayAndDateOtherwiseAndShortensLongText() {
        let today = "2026-10-06"
        #expect(History.label(History.Entry(time: "2026-10-06 14:32:05", text: "Коротко"), today: today, maxChars: 60) == "14:32 · Коротко")
        #expect(History.label(History.Entry(time: "2026-10-05 09:01:00", text: "Вчора"), today: today, maxChars: 60) == "05.10 09:01 · Вчора")
        let long = String(repeating: "слово ", count: 20)
        let label = History.label(History.Entry(time: "2026-10-06 14:32:05", text: long), today: today, maxChars: 30)
        #expect(label.count <= 30 + 8)
        #expect(label.hasSuffix("…"))
    }

    @Test func pruneKeepsNewerEntriesDropsMalformedLinesReportsRemovedCount() throws {
        let file = try tempFile([
            "2026-09-01 10:00:00\told one", "2026-09-20 10:00:00\told two", "2026-10-05 10:00:00\tnew one",
            "garbage", "2026-10-06 09:00:00\tnew two",
        ])
        defer { try? FileManager.default.removeItem(at: file) }
        let cutoff = date("2026-10-01 00:00:00")
        #expect(History.prune(file, before: cutoff) == 3) // two old entries + one malformed line
        #expect(try read(file) == "2026-10-05 10:00:00\tnew one\n2026-10-06 09:00:00\tnew two\n")
        #expect(History.prune(file, before: cutoff) == 0)
    }

    @Test func pruneOnAMissingFileIsANoOp() {
        #expect(History.prune(URL(fileURLWithPath: "/nonexistent/h.log"), before: .now) == 0)
    }

    @Test func clearEmptiesTheFile() throws {
        let file = try tempFile(["2026-10-05 10:00:00\tx"])
        defer { try? FileManager.default.removeItem(at: file) }
        try History.clear(file)
        #expect(try read(file) == "")
    }

    // WAV (from tests/test_wav.lua: header case; the sox growing-file readers have no native counterpart)

    @Test func headerHasCorrectSizesAndFormat() {
        let data = WAV.data(samples: [Float](repeating: 0, count: 16_000))
        #expect(data.count == 44 + 32_000)
        #expect(data.prefix(4) == Data("RIFF".utf8))
        #expect(data.uint32(at: 4) == 36 + 32_000)
        #expect(data[8..<16] == Data("WAVEfmt ".utf8))
        #expect([data.uint32(at: 16), UInt32(data.uint16(at: 20)), UInt32(data.uint16(at: 22)), data.uint32(at: 24),
                 data.uint32(at: 28), UInt32(data.uint16(at: 32)), UInt32(data.uint16(at: 34))]
            == [16, 1, 1, 16_000, 32_000, 2, 16])
        #expect(data[36..<40] == Data("data".utf8))
        #expect(data.uint32(at: 40) == 32_000)
    }

    @Test func samplesAreClampedTo16Bit() {
        let data = WAV.data(samples: [0, 1, -1, 2, -2, 0.5])
        #expect((0..<6).map { Int16(bitPattern: data.uint16(at: 44 + $0 * 2)) } == [0, 32_767, -32_767, 32_767, -32_767, 16_384])
    }

    // Failed audio (from platform.lua keepFailed / cleanupFailed)

    @Test func keepWritesAWAVAndZeroHoursKeepsNothing() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: dir) }
        let kept = try #require(try FailedAudio.keep([0.1, -0.1], in: dir, hours: 24, now: date("2026-10-05 09:03:07")))
        #expect(kept.lastPathComponent == "2026-10-05_09-03-07.wav")
        #expect(try Data(contentsOf: kept).count == 44 + 4)
        #expect(try FailedAudio.keep([0.1], in: dir, hours: 0, now: .now) == nil)
    }

    @Test func cleanupRemovesOnlyOldWAVFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let now = Date.now
        for (name, age) in [("old.wav", 25.0), ("new.wav", 1.0), ("old.txt", 25.0)] {
            let file = dir.appending(path: name)
            try Data().write(to: file)
            try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age * 3600)], ofItemAtPath: file.path)
        }
        FailedAudio.cleanup(dir, olderThanHours: 24, now: now)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() == ["new.wav", "old.txt"])
    }
}

private extension Data {
    func uint32(at offset: Int) -> UInt32 {
        self[offset..<offset + 4].enumerated().reduce(0) { $0 | UInt32($1.element) << (8 * $1.offset) }
    }

    func uint16(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }
}
