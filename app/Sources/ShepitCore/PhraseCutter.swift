/// A phrase as sample offsets in its stream, `start..<end`.
public struct Phrase: Equatable, Sendable {
    public var start: Int
    public var end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }
}

/// Cuts a meeting stream into phrases from voice-activity probabilities, one per frame (spec §5.2).
/// A phrase ends after `pause` seconds without speech; one longer than `maxPhrase` is cut at the weakest
/// frame in the last `cutSearch` seconds; one with less than `minSpeech` seconds of speech is dropped.
/// Audio between `startSkip` and `endSkip` (a dictation, §5.8) never lands in a phrase.
public struct PhraseCutter: Sendable {
    public static let sampleRate = 16_000

    private let frameSamples: Int
    private let pause: Int
    private let maxPhrase: Int
    private let minSpeech: Int
    private let padding: Int
    private let cutSearch: Int
    private let threshold: Float

    private var frames: [(start: Int, probability: Float)] = [] // frames of the open phrase
    private var openStart: Int?
    private var lastSpeechEnd = 0
    private var silence = 0
    /// Padding never reaches before this: the previous phrase's end or a dictation's end.
    private var floor = 0
    private var skipStart: Int?
    private var skipEnd: Int?
    private var position = 0 // end of the last frame pushed

    public init(frameSamples: Int, pause: Double = 0.6, maxPhrase: Double = 25, minSpeech: Double = 0.4,
                padding: Double = 0.2, cutSearch: Double = 5, threshold: Float = 0.5) {
        func samples(_ seconds: Double) -> Int { Int(seconds * Double(Self.sampleRate)) }
        self.frameSamples = frameSamples
        self.pause = samples(pause)
        self.maxPhrase = samples(maxPhrase)
        self.minSpeech = samples(minSpeech)
        self.padding = samples(padding)
        self.cutSearch = samples(cutSearch)
        self.threshold = threshold
    }

    /// The earliest sample a phrase not emitted yet can start at (open phrase, or padding before the next one).
    public var frontier: Int {
        max(floor, (openStart ?? position) - padding)
    }

    public mutating func push(probability: Float, frameStart: Int) -> [Phrase] {
        let frameEnd = frameStart + frameSamples
        position = max(position, frameEnd)
        if let skipStart, frameEnd > skipStart, skipEnd.map({ frameStart < $0 }) ?? true {
            let closed = close(at: skipStart, limit: skipStart)
            floor = max(floor, skipStart)
            return closed.map { [$0] } ?? []
        }
        if let skipEnd, frameStart >= skipEnd {
            skipStart = nil
            self.skipEnd = nil
        }

        var out: [Phrase] = []
        if probability >= threshold {
            if openStart == nil { openStart = frameStart }
            lastSpeechEnd = frameEnd
            silence = 0
        } else if openStart != nil {
            silence += frameSamples
        }
        guard let start = openStart else { return out }
        frames.append((frameStart, probability))

        if silence >= pause {
            if let phrase = close(at: lastSpeechEnd + padding, limit: frameEnd) { out.append(phrase) }
        } else if frameEnd - start >= maxPhrase {
            out.append(cut(before: frameEnd))
        }
        return out
    }

    public mutating func startSkip(at sample: Int) {
        skipStart = sample
        skipEnd = nil
    }

    public mutating func endSkip(at sample: Int) {
        skipEnd = sample
        floor = max(floor, sample)
    }

    public mutating func finish() -> [Phrase] {
        close(at: lastSpeechEnd + padding, limit: .max).map { [$0] } ?? []
    }

    /// Closes the open phrase at `end` (but not after `limit`); nil if there is none or it is a blip.
    private mutating func close(at end: Int, limit: Int) -> Phrase? {
        defer {
            frames = []
            openStart = nil
            silence = 0
        }
        guard let start = openStart else { return nil }
        let speech = frames.filter { $0.probability >= threshold }.count * frameSamples
        guard speech >= minSpeech else { return nil }
        let phrase = Phrase(start: max(start - padding, floor), end: min(end, limit))
        floor = phrase.end
        return phrase
    }

    /// Cuts the over-long open phrase at its weakest recent frame; the rest stays open as a new phrase.
    private mutating func cut(before frameEnd: Int) -> Phrase {
        let start = openStart!
        let recent = frames.indices.filter { frames[$0].start >= frameEnd - cutSearch && frames[$0].start > start }
        let weakest = recent.min { frames[$0].probability < frames[$1].probability } ?? frames.count - 1
        let point = frames[weakest].start
        let phrase = Phrase(start: max(start - padding, floor), end: point)
        floor = point
        frames.removeFirst(weakest)
        openStart = point
        return phrase
    }
}
