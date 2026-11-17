import Foundation

/// A voice (voices design §4): the speaker model's 256 numbers, normalised. Not audio and not words.
public struct VoiceSample: Equatable, Sendable {
    public static let size = 256
    public let vector: [Float]

    /// nil for another size or a vector of no length.
    public init?(_ vector: [Float]) {
        let length = vector.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard vector.count == Self.size, length > 0 else { return nil }
        self.vector = vector.map { $0 / length }
    }

    /// As `blob` stores it; nil for a blob of another size.
    public init?(blob: Data) {
        guard blob.count == Self.size * MemoryLayout<Float>.size else { return nil }
        var vector = [Float](repeating: 0, count: Self.size)
        _ = vector.withUnsafeMutableBytes { blob.copyBytes(to: $0) }
        self.init(vector)
    }

    public var blob: Data { vector.withUnsafeBytes { Data($0) } }

    /// The mean of several, normalised; nil for none.
    public static func mean(_ samples: [VoiceSample]) -> VoiceSample? {
        guard !samples.isEmpty else { return nil }
        var sum = [Float](repeating: 0, count: size)
        for sample in samples { for i in sum.indices { sum[i] += sample.vector[i] } }
        return VoiceSample(sum)
    }
}

/// One voice in one window of speaker detection: the speech of `speaker` (as `SpeakerTurn.speaker` names it) within
/// one 10-s window, from its first to its last spoken frame.
public struct VoiceWindow: Sendable {
    public var speaker: String
    public var start: Double
    public var end: Double
    public var sample: VoiceSample

    public init(speaker: String, start: Double, end: Double, sample: VoiceSample) {
        self.speaker = speaker
        self.start = start
        self.end = end
        self.sample = sample
    }
}

/// What speaker detection gives: who spoke when, and the windows' voices (none while Remember voices is off).
public struct Diarization: Sendable {
    public var turns: [SpeakerTurn]
    public var windows: [VoiceWindow]

    public init(turns: [SpeakerTurn], windows: [VoiceWindow] = []) {
        self.turns = turns
        self.windows = windows
    }
}

/// Voice samples, prints and recognition (voices design §4, §5).
public enum Voices {
    /// A sample per call line (offsets in seconds, in note order): the mean of the windows of the line's own speaker
    /// that overlap it; nil when none does.
    public static func lineSamples(_ lines: [Range<Double>], _ diarization: Diarization) -> [VoiceSample?] {
        lines.map { line in
            guard let speaker = Speakers.speaker(for: line, turns: diarization.turns) else { return nil }
            return VoiceSample.mean(diarization.windows.filter {
                $0.speaker == speaker && $0.start < line.upperBound && $0.end > line.lowerBound
            }.map(\.sample))
        }
    }
}
