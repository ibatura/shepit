/// A stretch of a phrase in one language ("uk" or "en"), sample offsets at 16 kHz.
public struct LanguagePart: Equatable, Sendable {
    public var range: Range<Int>
    public var language: String

    public init(range: Range<Int>, language: String) {
        self.range = range
        self.language = language
    }

    static let frame = 320            // 20 ms
    static let minPause = 8           // 160 ms of quiet frames is a cut point
    static let minPiece = 32_000      // 2 s: shorter pieces are too short to tell the language

    /// The phrase split at short pauses into pieces of at least 2 s that cover it end to end.
    /// A pause is a run of frames quieter than 15% of the loud frames' level.
    public static func pieces(_ samples: [Float]) -> [Range<Int>] {
        guard samples.count >= 2 * minPiece else { return samples.isEmpty ? [] : [0..<samples.count] }
        let levels = stride(from: 0, to: samples.count - frame + 1, by: frame).map { start in
            (samples[start..<start + frame].reduce(0) { $0 + $1 * $1 } / Float(frame)).squareRoot()
        }
        let loud = levels.sorted()[levels.count * 8 / 10]
        let quiet = max(0.002, loud * 0.15)
        var cuts: [Int] = []
        var run = 0
        for (index, level) in levels.enumerated() {
            if level < quiet {
                run += 1
            } else {
                if run >= minPause { cuts.append((index - run / 2) * frame) }
                run = 0
            }
        }
        var pieces: [Range<Int>] = []
        var start = 0
        for cut in cuts where cut - start >= minPiece && samples.count - cut >= minPiece {
            pieces.append(start..<cut)
            start = cut
        }
        pieces.append(start..<samples.count)
        return pieces
    }
}
