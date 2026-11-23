import Testing
@testable import ShepitCore

// Ported from tests/test_addword.lua.
struct AddWordTests {
    @Test func promptWithASelectedWordAndNoExistingRule() {
        let p = AddWord.prompt(selected: "кубернетіс", existing: nil)
        #expect(p.title == "Add to dictionary")
        #expect(p.message == "“кубернетіс” → how should it be written?")
        #expect(p.defaultValue == "")
    }

    @Test func promptShowsTheExistingRuleAsTheDefault() {
        let p = AddWord.prompt(selected: "кубернетіс", existing: "Kubernetes")
        #expect(p.message == "“кубернетіс” → how should it be written? (now: Kubernetes)")
        #expect(p.defaultValue == "Kubernetes")
    }

    @Test func promptWithoutASelectionAsksForBothSpellings() {
        let p = AddWord.prompt(selected: "", existing: nil)
        #expect(p.message == "As heard = as it should be written (джира = Jira), or just the right spelling")
        #expect(p.defaultValue == "")
    }

    @Test func longSelectionsAreShortenedInTheMessage() {
        #expect(AddWord.prompt(selected: String(repeating: "дуже довгий текст ", count: 10), existing: nil).message.count < 90)
    }

    @Test func parseWithASelectionTheInputIsTheCorrectSpelling() {
        #expect(AddWord.parse(selected: "кубернетіс", input: "Kubernetes") == .rule(wrong: "кубернетіс", right: "Kubernetes"))
    }

    @Test func parseWithoutASelectionWrongEqualsRightOrJustATerm() {
        #expect(AddWord.parse(selected: "", input: "джира = Jira") == .rule(wrong: "джира", right: "Jira"))
        #expect(AddWord.parse(selected: "", input: "Jira") == .rule(wrong: "", right: "Jira"))
        #expect(AddWord.parse(selected: "", input: "  ") == .rule(wrong: "", right: ""))
    }

    @Test func parseSelectionLongerThanAPhraseIsRejected() {
        #expect(AddWord.parse(selected: String(repeating: "слово ", count: 12), input: "X")
            == .error("Too much text is selected: select one word or a short phrase"))
    }
}
