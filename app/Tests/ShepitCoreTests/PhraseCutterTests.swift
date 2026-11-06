import Testing
@testable import ShepitCore

// Spec §5.2 and §5.8. Frames are 0.1 s (1600 samples) so the spec's constants map to whole frames:
// pause 0.6 s = 6 frames, min speech 0.4 s = 4 frames, max phrase 25 s = 250 frames, padding 0.2 s = 3200 samples.
struct PhraseCutterTests {
    private let frame = 1600

    private func cutter() -> PhraseCutter {
        PhraseCutter(frameSamples: frame, padding: 0.2)
    }

    /// Feeds probabilities starting at frame `from`; returns every phrase emitted.
    private func feed(_ cutter: inout PhraseCutter, _ probabilities: [Float], from: Int = 0) -> [Phrase] {
        probabilities.enumerated().flatMap { cutter.push(probability: $1, frameStart: (from + $0) * frame) }
    }

    private func run(_ probabilities: [Float]) -> [Phrase] {
        var c = cutter()
        return feed(&c, probabilities) + c.finish()
    }

    private func speech(_ n: Int, _ p: Float = 0.9) -> [Float] { Array(repeating: p, count: n) }
    private func quiet(_ n: Int) -> [Float] { Array(repeating: 0.05, count: n) }

    @Test func aPhraseEndsAfterThePauseWithPadding() {
        var c = cutter()
        #expect(feed(&c, quiet(5) + speech(10) + quiet(5)).isEmpty)
        #expect(feed(&c, quiet(1), from: 20) == [Phrase(start: 5 * frame - 3200, end: 15 * frame + 3200)])
        #expect(c.finish().isEmpty)
    }

    @Test func paddingIsClampedAtTheStreamStart() {
        #expect(run(speech(10) + quiet(6)) == [Phrase(start: 0, end: 10 * frame + 3200)])
    }

    @Test func blipsUnderMinimumSpeechAreDropped() {
        #expect(run(speech(3) + quiet(6)).isEmpty)
        #expect(run(speech(4) + quiet(6)).count == 1)
    }

    @Test func shortPausesDoNotSplitAPhrase() {
        #expect(run(speech(5) + quiet(5) + speech(5) + quiet(6)) == [Phrase(start: 0, end: 15 * frame + 3200)])
    }

    @Test func longPhraseIsCutAtTheLowestProbabilityNearTheLimit() {
        var probabilities = speech(300)
        probabilities[230] = 0.55 // still speech, but the weakest frame in the last 5 s before 25 s
        probabilities[100] = 0.51 // weaker, but too far from the limit
        #expect(run(probabilities + quiet(6)) == [
            Phrase(start: 0, end: 230 * frame),
            Phrase(start: 230 * frame, end: 300 * frame + 3200),
        ])
    }

    @Test func finishClosesTheOpenPhrase() {
        #expect(run(quiet(2) + speech(8)) == [Phrase(start: 2 * frame - 3200, end: 10 * frame + 3200)])
    }

    @Test func silenceGivesNoPhrases() {
        #expect(run(quiet(500)).isEmpty)
    }

    @Test func dictationRangeIsLeftOutAndSplitsAPhrase() {
        var c = cutter()
        var phrases = feed(&c, speech(10))
        c.startSkip(at: 10 * frame)
        phrases += feed(&c, speech(10), from: 10)
        c.endSkip(at: 20 * frame)
        phrases += feed(&c, speech(10) + quiet(6), from: 20)
        #expect(phrases == [
            Phrase(start: 0, end: 10 * frame),
            Phrase(start: 20 * frame, end: 30 * frame + 3200),
        ])
    }

    @Test func aFrameThatOverlapsTheDictationIsSkipped() {
        var c = cutter()
        c.startSkip(at: 10 * frame + 400)
        var phrases = feed(&c, speech(12))
        c.endSkip(at: 11 * frame + 100)
        phrases += feed(&c, speech(8) + quiet(6), from: 12)
        #expect(phrases == [
            Phrase(start: 0, end: 10 * frame + 400),
            Phrase(start: 11 * frame + 100, end: 20 * frame + 3200), // padding stops at the dictation's end
        ])
    }

    @Test func paddingNeverReachesBackIntoThePreviousPhrase() {
        var c = PhraseCutter(frameSamples: frame, padding: 0.5) // 8000 samples, more than half the pause
        let phrases = feed(&c, speech(10) + quiet(6) + speech(10) + quiet(6)) + c.finish()
        #expect(phrases == [
            Phrase(start: 0, end: 10 * frame + 8000),
            Phrase(start: 10 * frame + 8000, end: 26 * frame + 8000),
        ])
    }

    @Test func frontierIsTheEarliestStartOfAnythingNotEmittedYet() {
        var c = cutter()
        #expect(c.frontier == 0)
        _ = feed(&c, quiet(10))
        #expect(c.frontier == 10 * frame - 3200)
        _ = feed(&c, speech(5), from: 10)
        #expect(c.frontier == 10 * frame - 3200) // the open phrase, with its padding
        _ = feed(&c, quiet(6), from: 15)
        #expect(c.frontier == 21 * frame - 3200)
    }
}
