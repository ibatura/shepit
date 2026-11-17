import Foundation
import Testing
@testable import ShepitCore

// Voices design §4: voice samples.
struct VoicesTests {
    /// A sample pointing along axis `axis` (with a little of axis 0 so two axes aren't orthogonal by accident).
    private func voice(_ axis: Int, _ weight: Float = 1) -> VoiceSample {
        var vector = [Float](repeating: 0, count: VoiceSample.size)
        vector[axis] = weight
        return VoiceSample(vector)!
    }

    @Test func aSampleIsNormalisedAndKeptAsABlob() throws {
        let sample = try #require(VoiceSample([3, 4] + [Float](repeating: 0, count: 254)))
        #expect(sample.vector[0] == 0.6 && sample.vector[1] == 0.8)
        #expect(VoiceSample(blob: sample.blob) == sample && sample.blob.count == 1024)
        #expect(VoiceSample(blob: Data([0, 1, 2])) == nil)
        #expect(VoiceSample([1, 2]) == nil && VoiceSample([Float](repeating: 0, count: 256)) == nil)
        #expect(VoiceSample.mean([voice(1), voice(2)])?.vector[1] == 1 / Float(2).squareRoot())
        #expect(VoiceSample.mean([]) == nil)
    }

    @Test func aLineGetsTheWindowsOfItsOwnSpeakerThatOverlapIt() {
        let diarization = Diarization(
            turns: [SpeakerTurn(speaker: "S1", start: 0, end: 10), SpeakerTurn(speaker: "S2", start: 10, end: 20)],
            windows: [VoiceWindow(speaker: "S1", start: 0, end: 6, sample: voice(1)), VoiceWindow(speaker: "S1", start: 4, end: 9, sample: voice(2)),
                      VoiceWindow(speaker: "S2", start: 3, end: 5, sample: voice(3)), // another voice in the same window
                      VoiceWindow(speaker: "S2", start: 12, end: 18, sample: voice(4))])
        let samples = Voices.lineSamples([1..<5, 7..<9, 12..<13, 30..<31], diarization)
        #expect(samples[0] == VoiceSample.mean([voice(1), voice(2)]))
        #expect(samples[1] == voice(2))
        #expect(samples[2] == voice(4))
        #expect(samples[3] == nil) // no speaker there
        #expect(Voices.lineSamples([1..<5], Diarization(turns: diarization.turns)) == [nil]) // no windows: Remember voices off
    }
}
