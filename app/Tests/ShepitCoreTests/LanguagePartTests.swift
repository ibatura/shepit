import Foundation
import Testing
@testable import ShepitCore

struct LanguagePartTests {
    private func speech(_ seconds: Double) -> [Float] {
        (0..<Int(seconds * 16_000)).map { Float(sin(Double($0) * 0.05)) * 0.3 }
    }
    private func pause(_ seconds: Double) -> [Float] { [Float](repeating: 0, count: Int(seconds * 16_000)) }

    @Test func aShortPhraseIsOnePiece() {
        let samples = speech(1.5) + pause(0.3) + speech(1.5)
        #expect(LanguagePart.pieces(samples) == [0..<samples.count])
        #expect(LanguagePart.pieces([]).isEmpty)
    }

    @Test func piecesAreCutInShortPausesAndCoverThePhrase() {
        let samples = speech(3) + pause(0.3) + speech(3) + pause(0.3) + speech(3)
        let pieces = LanguagePart.pieces(samples)
        #expect(pieces.count == 3)
        #expect(pieces.first?.lowerBound == 0)
        #expect(pieces.last?.upperBound == samples.count)
        #expect(zip(pieces, pieces.dropFirst()).allSatisfy { $0.upperBound == $1.lowerBound })
        let cut = pieces[0].upperBound
        #expect(cut > 48_000 && cut < 48_000 + 4_800) // inside the first pause
    }

    @Test func pausesTooShortOrTooCloseDoNotCut() {
        // 0.1 s is a gap between words, not a cut; a cut that would leave under 2 s is skipped.
        #expect(LanguagePart.pieces(speech(3) + pause(0.1) + speech(3)).count == 1)
        #expect(LanguagePart.pieces(speech(3) + pause(0.3) + speech(1) + pause(0.3) + speech(3)).count == 2)
    }
}
