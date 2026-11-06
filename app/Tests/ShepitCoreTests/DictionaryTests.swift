import Foundation
import Testing
@testable import ShepitCore

// Ported case-for-case from tests/test_dictionary.lua.
struct DictionaryTests {
    private func replace(_ text: String, _ rules: [String: String]) -> String {
        DictionaryRules.applyReplacements(text, rules).text
    }

    // estimateTokens / buildPrompt

    @Test func estimateTokensCountsASCIIAndNonASCIIWordsDifferently() {
        #expect(DictionaryRules.estimateTokens("Hello world") == 3)
        #expect(DictionaryRules.estimateTokens("Привіт world") == 4.5)
        #expect(DictionaryRules.estimateTokens("") == 0)
    }

    @Test func buildPromptJoinsStyleAndTerms() {
        #expect(DictionaryRules.buildPrompt(style: "Стиль.", terms: ["Kubernetes", "pull request"], maxTokens: 200)
            == "Стиль. Kubernetes, pull request")
    }

    @Test func buildPromptWithEmptyStyleOrNoTerms() {
        #expect(DictionaryRules.buildPrompt(style: "", terms: ["A", "B"], maxTokens: 200) == "A, B")
        #expect(DictionaryRules.buildPrompt(style: "Стиль.", terms: [], maxTokens: 200) == "Стиль.")
        #expect(DictionaryRules.buildPrompt(style: "", terms: [], maxTokens: 200) == "")
    }

    @Test func buildPromptDropsTermsFromTheEndWhenOverBudget() {
        // style 3 + one 1.5 + two 1.5 = 6 fits; three would make 7.5
        #expect(DictionaryRules.buildPrompt(style: "Слово", terms: ["one", "two", "three"], maxTokens: 6) == "Слово one, two")
    }

    @Test func buildPromptStopsAtFirstTermThatDoesNotFit() {
        #expect(DictionaryRules.buildPrompt(style: "Слово", terms: ["one", "довгий термін", "x"], maxTokens: 6) == "Слово one")
    }

    // applyReplacements

    @Test func replacesCaseInsensitivelyCyrillicIncludedValueVerbatim() {
        #expect(replace("Відкрив Пул Реквест сьогодні", ["пул реквест": "pull request"]) == "Відкрив pull request сьогодні")
    }

    @Test func matchesWholeWordsOnly() {
        #expect(replace("пул і пулемет", ["пул": "pool"]) == "pool і пулемет")
    }

    @Test func apostropheCountsAsPartOfAWord() {
        #expect(replace("з'їв з’їв зʼїв їв", ["їв": "X"]) == "з'їв з’їв зʼїв X")
    }

    @Test func matchesNextToGuillemetsPunctuationAndEmoji() {
        #expect(replace("«Кубернетіс», кубернетіс🙂 (кубернетіс).", ["кубернетіс": "Kubernetes"])
            == "«Kubernetes», Kubernetes🙂 (Kubernetes).")
    }

    @Test func longestKeyWinsAtAPosition() {
        #expect(replace("пул реквест і пул", ["пул": "pool", "пул реквест": "pull request"]) == "pull request і pool")
    }

    @Test func outputOfOneRuleIsNotReMatchedByAnother() {
        #expect(replace("пул реквест", ["пул реквест": "pull request", "pull": "XX"]) == "pull request")
    }

    @Test func emptyKeysAreIgnoredAndEmptyReplaceTableIsANoOp() {
        #expect(replace("текст", ["": "X"]) == "текст")
        #expect(replace("текст", [:]) == "текст")
    }

    // Swift strings can't hold invalid UTF-8 (decoding turns it into U+FFFD), so the Lua
    // "invalid UTF-8 does not crash" case checks replacement characters instead.
    @Test func replacementCharactersDoNotBreakMatching() {
        #expect(replace("пул \u{FFFD}\u{FFFD} пул", ["пул": "pool"]) == "pool \u{FFFD}\u{FFFD} pool")
    }

    @Test func firedTermsListEveryMatch() {
        let result = DictionaryRules.applyReplacements("пул і кубер і пул", ["пул": "pool", "кубер": "Kuber", "x": "y"])
        #expect(result.fired == ["pool", "Kuber", "pool"])
    }

    // stripHallucinations

    @Test func dropsOutputThatIsEntirelyAKnownPhrase() {
        #expect(DictionaryRules.stripHallucinations("Дякую за перегляд!", extra: []) == "")
        #expect(DictionaryRules.stripHallucinations("  thanks for watching.  ", extra: []) == "")
    }

    @Test func dropsAKnownPhraseAsTheFinalSentenceOnly() {
        #expect(DictionaryRules.stripHallucinations("Зробив деплой. Дякую за перегляд!", extra: []) == "Зробив деплой.")
        #expect(DictionaryRules.stripHallucinations("Дякую за перегляд! Зробив деплой.", extra: [])
            == "Дякую за перегляд! Зробив деплой.")
    }

    @Test func dropsPhrasePrefixesLikeSubtitlesMadeByCommunity() {
        #expect(DictionaryRules.stripHallucinations("Готово. Субтитри зроблено спільнотою Amara.org", extra: []) == "Готово.")
    }

    @Test func dropsRepeatedTrailingHallucinationsAndEllipsisSeparatedOnes() {
        #expect(DictionaryRules.stripHallucinations("Готово… Дякую за перегляд! Дякую за перегляд!", extra: []) == "Готово…")
    }

    @Test func usesExtraPhrasesFromTheDictionary() {
        #expect(DictionaryRules.stripHallucinations("Текст. Бла бла.", extra: ["бла бла"]) == "Текст.")
    }

    @Test func removesBlankAudioStyleTags() {
        #expect(DictionaryRules.stripHallucinations("[BLANK_AUDIO]", extra: []) == "")
        #expect(DictionaryRules.stripHallucinations("Привіт [MUSIC] світ", extra: []) == "Привіт  світ")
    }

    // process

    @Test func processStripsReplacesAndTidiesWhitespace() {
        let dict = DictionaryFile(terms: [], replace: ["гіт хаб": "GitHub"], dropPhrases: [])
        #expect(DictionaryRules.process("  Запушив у гіт хаб [BLANK_AUDIO]  зміни. Дякую за перегляд! ", dict).text
            == "Запушив у GitHub зміни.")
    }

    @Test func processToleratesEmptyDictionary() {
        #expect(DictionaryRules.process(" текст ", .empty).text == "текст")
    }

    // validateDictionary (from tests/test_config.lua)

    @Test func dictionaryDefaultsToEmptyListsAndMaps() {
        let (dict, errors) = validateDictionary([:])
        #expect(errors.isEmpty)
        #expect(dict == .empty)
    }

    @Test func dictionaryAcceptsValidContent() {
        let (dict, errors) = validateDictionary(["terms": ["Kubernetes"], "replace": ["пул": "pool"], "dropPhrases": ["бла"]])
        #expect(errors.isEmpty)
        #expect(dict == DictionaryFile(terms: ["Kubernetes"], replace: ["пул": "pool"], dropPhrases: ["бла"]))
    }

    @Test func dictionaryRejectsWrongShapes() {
        let (dict, errors) = validateDictionary(["terms": [1], "replace": ["a": 2], "dropPhrases": "x"])
        #expect(dict == nil)
        #expect(errors == [
            #"dictionary.json: "terms" must be a list of strings"#,
            #"dictionary.json: "dropPhrases" must be a list of strings"#,
            #"dictionary.json: "replace" must map strings to strings"#
        ])
    }
}
