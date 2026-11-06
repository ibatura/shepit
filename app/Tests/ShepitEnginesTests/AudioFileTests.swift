import AVFoundation
import Foundation
import ShepitCore
import Testing
@testable import ShepitEngines

struct AudioFileTests {
    @Test func loadsFixtureAsSixteenKilohertzMono() throws {
        let fixture = try #require(Bundle.module.url(forResource: "hello", withExtension: "wav", subdirectory: "Fixtures"))
        let audio = try AVAudioFile(forReading: fixture)
        let duration = Double(audio.length) / audio.processingFormat.sampleRate
        let samples = try AudioFile.load(fixture)

        #expect(abs(Double(samples.count) - 16_000 * duration) <= 16_000 * duration * 0.01)
    }

    @Test func loadsStereo44100HzFileAsOneSecondAtSixteenKilohertz() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeStereoSine(to: url)
        let written = try AVAudioFile(forReading: url)
        #expect(written.length == 44_100)
        let loaded = try AudioFile.load(url)

        #expect((15_840...16_160).contains(loaded.count))
    }

    private func writeStereoSine(to url: URL) throws {
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 44_100, channels: 2, interleaved: true))
        let output = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: true)
        let frames: AVAudioFrameCount = 44_100
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let samples = try #require(buffer.int16ChannelData?[0])
        for frame in 0..<Int(frames) {
            let value = Int16(sin(2 * Double.pi * 440 * Double(frame) / 44_100) * Double(Int16.max))
            samples[frame * 2] = value
            samples[frame * 2 + 1] = value
        }
        try output.write(from: buffer)
    }

    @Test func wavRoundTripsThroughAudioFile() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: file) }
        let samples = (0..<8_000).map { Float(sin(Double($0) / 10)) * 0.5 }
        try WAV.data(samples: samples).write(to: file)
        let loaded = try AudioFile.load(file)
        #expect(loaded.count == samples.count)
        #expect(abs(loaded[100] - samples[100]) < 0.001)
    }
}
