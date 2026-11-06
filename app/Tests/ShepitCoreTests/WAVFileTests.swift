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
}
