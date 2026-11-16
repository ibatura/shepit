import Foundation
import Testing
@testable import ShepitCore

// WAV and failed audio, from tests/test_wav.lua and platform.lua keepFailed / cleanupFailed.
struct FailedAudioTests {
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
        let now = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9, minute: 3, second: 7)))
        let kept = try #require(try FailedAudio.keep([0.1, -0.1], in: dir, hours: 24, now: now))
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
