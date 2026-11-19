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

    /// Your speech for the microphone's speaker detection (voices design §4): your first `lines` (offsets in seconds, in
    /// order) until `seconds` of them are taken, wherever in the meeting you spoke. `ranges`: their audio in the
    /// microphone's (16 kHz samples); `lines`: where each one is once they are put one after another.
    public static func speech(of lines: [Range<Double>], upTo seconds: Double) -> (ranges: [Range<Int>], lines: [Range<Double>]) {
        var ranges: [Range<Int>] = [], taken: [Range<Double>] = [], length = 0
        for line in lines {
            guard Double(length) < seconds * 16_000 else { break }
            let from = Int((line.lowerBound * 16_000).rounded()), to = max(from, Int((line.upperBound * 16_000).rounded()))
            ranges.append(from..<to)
            taken.append(Double(length) / 16_000..<Double(length + to - from) / 16_000)
            length += to - from
        }
        return (ranges, taken)
    }

    /// Your lines' samples from the microphone (voices plan Task 8): the samples of the voice that speaks most of `lines`;
    /// a line of another voice (someone in the room) gets none. On a tie, the first voice by name, so the same audio
    /// always gives the same voice.
    public static func yourSamples(_ lines: [Range<Double>], _ diarization: Diarization) -> [VoiceSample?] {
        let voices = lines.map { Speakers.speaker(for: $0, turns: diarization.turns) }
        let counts = Dictionary(grouping: voices.compactMap { $0 }, by: { $0 }).mapValues(\.count)
        guard let you = counts.max(by: { ($0.value, $1.key) < ($1.value, $0.key) })?.key else { return lines.map { _ in nil } }
        return zip(voices, lineSamples(lines, diarization)).map { voice, sample in voice == you ? sample : nil }
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

    /// A person's voice: never stored, the mean of the samples of the lines that are theirs now (voices design §5).
    public struct Print: Sendable {
        public var mean: VoiceSample
        public var samples: Int
    }

    /// Starting values, to be settled with `Shepit voices-check` on the author's meetings (voices plan Task 10). On the
    /// first meeting kept with voices (2026-11-18) two different voices had means 0.76 alike, so the bar is high.
    public static let threshold: Float = 0.8
    /// How far the best print must lead the second best.
    public static let margin: Float = 0.1
    /// Samples a voice or a print needs before it is compared at all.
    public static let enough = 3

    /// The prints of the people with `enough` samples, summed as the rows come: no sample is kept.
    public static func prints(_ rows: [Row]) -> [Int: Print] {
        var sums: [Int: (sum: [Float], count: Int)] = [:]
        for row in rows {
            var entry = sums[row.person] ?? ([Float](repeating: 0, count: VoiceSample.size), 0)
            for i in entry.sum.indices { entry.sum[i] += row.sample.vector[i] }
            entry.count += 1
            sums[row.person] = entry
        }
        return sums.compactMapValues { sum, count in count >= enough ? VoiceSample(sum).map { Print(mean: $0, samples: count) } : nil }
    }

    /// The people of one meeting (samples by key) that a print names: the best print passing `threshold` and leading the
    /// second best by `margin`; never one print for two keys (the closer key gets it).
    public static func recognise<Key: Hashable>(_ people: [Key: [VoiceSample]], prints: [Int: Print], threshold: Float = threshold,
                                                margin: Float = margin) -> [Key: Int] {
        recognise(people, threshold: threshold, margin: margin) { voice in prints.mapValues { voice.similarity($0.mean) } }
    }

    /// `recognise` with how alike a voice is to each person (`scores`).
    private static func recognise<Key: Hashable>(_ people: [Key: [VoiceSample]], threshold: Float, margin: Float,
                                                 scores: (VoiceSample) -> [Int: Float]) -> [Key: Int] {
        var candidates: [(key: Key, person: Int, score: Float)] = []
        for (key, samples) in people where samples.count >= enough {
            guard let voice = VoiceSample.mean(samples) else { continue }
            let ranked = scores(voice).sorted { $0.value > $1.value }
            guard let best = ranked.first, best.value >= threshold, best.value - (ranked.dropFirst().first?.value ?? -1) >= margin else { continue }
            candidates.append((key, best.key, best.value))
        }
        var links: [Key: Int] = [:]
        for candidate in candidates.sorted(by: { $0.score > $1.score }) where !links.values.contains(candidate.person) {
            links[candidate.key] = candidate.person
        }
        return links
    }

    /// May also be in (voices design §6): the meetings whose unnamed people (samples by key, by meeting) recognition would
    /// name `person`, with the key it would name; none without a print of theirs.
    public static func suggestions(_ person: Int, unnamed: [Int: [String: [VoiceSample]]], prints: [Int: Print]) -> [Int: String] {
        guard prints[person] != nil else { return [:] }
        return unnamed.compactMapValues { people in recognise(people, prints: prints).first { $0.value == person }?.key }
    }

    /// How `Shepit voices-check` compares a voice with a person: with the mean of their samples (as recognition does), or
    /// with their nearest sample. Which works better is settled on the author's meetings (voices plan Task 10).
    public enum Match: Sendable, CaseIterable { case mean, nearest }

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
            let others = rows.filter { $0.meeting != meeting }
            let prints = prints(others)
            let nearest = Dictionary(grouping: others, by: \.person).filter { prints[$0.key] != nil }.mapValues { $0.map(\.sample) }
            let links = recognise(here, threshold: threshold, margin: margin) { voice in
                switch match {
                case .mean: prints.mapValues { voice.similarity($0.mean) }
                case .nearest: nearest.mapValues { $0.map(voice.similarity).max() ?? -1 }
                }
            }
            for (person, samples) in here where samples.count >= enough {
                switch links[person] {
                case person?: count.recognised += 1
                case .some: count.wrong += 1
                case nil: if prints[person] != nil { count.missed += 1 } else { count.unknown += 1 }
                }
            }
        }
        return count
    }
}
