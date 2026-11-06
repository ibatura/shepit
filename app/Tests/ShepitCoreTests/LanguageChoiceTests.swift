import Testing
@testable import ShepitCore

struct LanguageChoiceTests {
    @Test func englishFirstIsAlwaysEnglish() {
        #expect(LanguageChoice.pick(top: "en", probabilities: ["en": 0.4, "uk": 0.35], leaning: nil) == "en")
        #expect(LanguageChoice.pick(top: "en", probabilities: ["en": 0.4], leaning: "en") == "en")
    }

    @Test func withoutALeaningAnythingElseIsUkrainian() {
        #expect(LanguageChoice.pick(top: "other", probabilities: ["uk": 0.3, "en": 0.2, "de": 0.35], leaning: nil) == "uk")
    }

    @Test func onAnEnglishStreamOnlyClearlySlavicPiecesAreUkrainian() {
        // A short accented English piece: Ukrainian first, but not by much.
        #expect(LanguageChoice.pick(top: "other", probabilities: ["uk": 0.4, "en": 0.3, "ru": 0.1], leaning: "en") == "en")
        // Real Ukrainian, split between uk and ru.
        #expect(LanguageChoice.pick(top: "other", probabilities: ["uk": 0.45, "ru": 0.3, "en": 0.05], leaning: "en") == "uk")
    }

    @Test func aStreamLeansEnglishAfterEnoughMostlyEnglishSpeech() {
        var leaning = LanguageLeaning()
        leaning.add(seconds: 15, detected: "en")
        #expect(leaning.leaning == nil) // under 20 s heard
        leaning.add(seconds: 10, detected: "en")
        #expect(leaning.leaning == "en")
        leaning.add(seconds: 10, detected: "uk")
        #expect(leaning.leaning == nil) // 25 of 35 s English: under 75%
    }

    @Test func mixedPhrasesCountHalfAndUnknownOnesAreSkipped() {
        var leaning = LanguageLeaning()
        leaning.add(seconds: 20, detected: "en")
        leaning.add(seconds: 4, detected: "uk+en")
        leaning.add(seconds: 30, detected: nil)
        #expect(leaning.leaning == "en") // 22 of 24 s
    }

    @Test func onlyTheLastTwoMinutesCount() {
        var leaning = LanguageLeaning()
        leaning.add(seconds: 200, detected: "uk")
        leaning.add(seconds: 130, detected: "en")
        #expect(leaning.leaning == "en")
    }
}
