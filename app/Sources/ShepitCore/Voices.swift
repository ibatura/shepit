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

    /// Cosine similarity: 1 for the same direction, 0 for unrelated voices.
    public func similarity(_ other: VoiceSample) -> Float {
        zip(vector, other.vector).reduce(0) { $0 + $1.0 * $1.1 }
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

    /// A line's sample, the person its line belongs to now, and its meeting (`MeetingStore.voiceRows`).
    public struct Row: Equatable, Sendable {
        public var person: Int
        public var meeting: Int
        public var sample: VoiceSample

        public init(person: Int, meeting: Int, sample: VoiceSample) {
            self.person = person
            self.meeting = meeting
            self.sample = sample
        }
    }

    /// A person's voice: never stored, made from the samples of the lines that are theirs now (voices design §5).
    public struct Print: Sendable {
        public var mean: VoiceSample
        public var samples: [VoiceSample]
    }

    /// How a voice is compared with a print: with its mean, or with its nearest sample (`Shepit voices-check` says which works).
    public enum Match: Sendable, CaseIterable { case mean, nearest }

    /// Starting values, to be settled with `Shepit voices-check` on the author's meetings (voices plan Task 10). On the
    /// first meeting kept with voices (2026-11-18) two different voices had means 0.76 alike, so the bar is high.
    public static let threshold: Float = 0.8
    /// How far the best print must lead the second best.
    public static let margin: Float = 0.1
    /// Samples a voice or a print needs before it is compared at all.
    public static let enough = 3

    public static func prints(_ rows: [Row]) -> [Int: Print] {
        Dictionary(grouping: rows, by: \.person).compactMapValues { rows in
            let samples = rows.map(\.sample)
            return samples.count >= enough ? VoiceSample.mean(samples).map { Print(mean: $0, samples: samples) } : nil
        }
    }

    /// The people of one meeting (samples by key) that a print names: the best print passing `threshold` and leading the
    /// second best by `margin`; never one print for two keys (the closer key gets it).
    public static func recognise(_ people: [String: [VoiceSample]], prints: [Int: Print], match: Match = .mean,
                                 threshold: Float = threshold, margin: Float = margin) -> [String: Int] {
        var candidates: [(key: String, person: Int, score: Float)] = []
        for (key, samples) in people where samples.count >= enough {
            guard let voice = VoiceSample.mean(samples) else { continue }
            let scores = prints.map { person, print in
                (person, match == .mean ? voice.similarity(print.mean) : print.samples.map(voice.similarity).max() ?? -1)
            }.sorted { $0.1 > $1.1 }
            guard let best = scores.first, best.1 >= threshold, best.1 - (scores.dropFirst().first?.1 ?? -1) >= margin else { continue }
            candidates.append((key, best.0, best.1))
        }
        var links: [String: Int] = [:]
        for candidate in candidates.sorted(by: { $0.score > $1.score }) where !links.values.contains(candidate.person) {
            links[candidate.key] = candidate.person
        }
        return links
    }

    /// `Shepit voices-check` (voices design §8): each meeting's people taken as new and matched against the prints of
    /// the other meetings. `unknown`: no print elsewhere and left alone, as it should be.
    public struct CheckCount: Equatable, Sendable {
        public var recognised = 0, wrong = 0, missed = 0, unknown = 0

        public init(recognised: Int = 0, wrong: Int = 0, missed: Int = 0, unknown: Int = 0) {
            self.recognised = recognised
            self.wrong = wrong
            self.missed = missed
            self.unknown = unknown
        }
    }

    public static func check(_ rows: [Row], match: Match, threshold: Float, margin: Float = margin) -> CheckCount {
        var count = CheckCount()
        for meeting in Set(rows.map(\.meeting)) {
            let here = Dictionary(grouping: rows.filter { $0.meeting == meeting }, by: \.person).mapValues { $0.map(\.sample) }
            let prints = prints(rows.filter { $0.meeting != meeting })
            let links = recognise(Dictionary(uniqueKeysWithValues: here.map { (String($0.key), $0.value) }), prints: prints,
                                  match: match, threshold: threshold, margin: margin)
            for (person, samples) in here where samples.count >= enough {
                switch links[String(person)] {
                case person?: count.recognised += 1
                case .some: count.wrong += 1
                case nil: if prints[person] != nil { count.missed += 1 } else { count.unknown += 1 }
                }
            }
        }
        return count
    }
}
