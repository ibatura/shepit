import Foundation
import Testing
@testable import ShepitCore

struct WAVFileTests {
    @Test func streamedFileMatchesTheOneShotEncoderAndReadsBack() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: file) }
        let samples: [Float] = (0..<5000).map { Float(sin(Double($0) / 10)) * 0.5 }
        let writer = try WAVFileWriter(file: file)
        try writer.append(Array(samples[..<1234]))
        try writer.append(Array(samples[1234...]))
        try writer.finish()
        #expect(try Data(contentsOf: file) == WAV.data(samples: samples))
        let back = try WAV.read(file)
        #expect(back.count == samples.count)
        #expect(zip(back, samples).allSatisfy { abs($0 - $1) < 0.0001 })
    }

    @Test func partsAreReadOneAfterAnotherAndNothingPastTheEnd() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: file) }
        try WAV.data(samples: (0..<10).map { Float($0) / 10 }).write(to: file)
        let parts = try WAV.read(file, [2..<4, 7..<12])
        #expect(parts.count == 5)
        #expect(zip(parts, [0.2, 0.3, 0.7, 0.8, 0.9] as [Float]).allSatisfy { abs($0 - $1) < 0.0001 })
        #expect(try WAV.read(file, [20..<30]).isEmpty)
    }
}
