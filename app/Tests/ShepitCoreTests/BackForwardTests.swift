import Testing
@testable import ShepitCore

// Back and forward design §4–5: the history of the window's places, here with letters for places.
struct BackForwardTests {
    private let all: (String) -> Bool = { _ in true }

    private func visited(_ steps: String...) -> BackForward<String> {
        var history = BackForward<String>()
        for step in steps { history.visit(step) }
        return history
    }

    @Test func backAndForwardRetraceTheVisits() {
        var history = visited("a", "b", "c")
        #expect(history.current == "c")
        #expect(history.back(alive: all) == "b")
        #expect(history.back(alive: all) == "a")
        #expect(history.back(alive: all) == nil)
        #expect(history.current == "a")
        #expect(history.forward(alive: all) == "b")
        #expect(history.forward(alive: all) == "c")
        #expect(history.forward(alive: all) == nil)
        #expect(history.current == "c")
    }

    @Test func aVisitEqualToTheCurrentStepDoesNothing() {
        var history = visited("a", "b")
        _ = history.back(alive: all)
        history.visit("a") // what applying the step back gives
        #expect(history.peekForward(alive: all) == "b")
        #expect(history.peekBack(alive: all) == nil)
    }

    @Test func aNewVisitDropsTheStepsAhead() {
        var history = visited("a", "b", "c")
        _ = history.back(alive: all)
        history.visit("d")
        #expect(history.forward(alive: all) == nil)
        #expect(history.back(alive: all) == "b")
        #expect(history.back(alive: all) == "a")
    }

    @Test func goneStepsAreSkippedAndDroppedBothWays() {
        var history = visited("a", "b", "c", "d")
        #expect(history.back(alive: { $0 != "c" }) == "b")
        #expect(history.forward(alive: all) == "d") // "c" was dropped on the way back
        #expect(history.back(alive: all) == "b")
        #expect(history.back(alive: all) == "a")
        #expect(history.forward(alive: { $0 != "b" }) == "d")
        #expect(history.back(alive: all) == "a")
    }

    @Test func whenEveryStepAheadIsGoneNothingMovesAndTheyAreDropped() {
        var history = visited("a", "b", "c")
        #expect(history.back(alive: { $0 == "c" }) == nil)
        #expect(history.current == "c")
        #expect(history.peekBack(alive: all) == nil)
    }

    @Test func theCurrentStepIsNeverTested() {
        var history = visited("a", "b")
        #expect(history.back(alive: { $0 != "b" }) == "a")
        #expect(history.forward(alive: all) == "b")
    }

    @Test func peekingSkipsGoneStepsAndMovesNothing() {
        let history = visited("a", "b", "c")
        #expect(history.peekBack(alive: { $0 != "b" }) == "a")
        #expect(history.peekForward(alive: all) == nil)
        #expect(history.current == "c")
        #expect(history.peekBack(alive: all) == "b")
    }

    @Test func replaceChangesEveryEqualStep() {
        var history = visited("run", "a", "run", "b")
        _ = history.back(alive: all) // on the second "run", "b" ahead
        history.replace("run", with: "m")
        #expect(history.current == "m")
        #expect(history.forward(alive: all) == "b")
        #expect(history.back(alive: all) == "m")
        #expect(history.back(alive: all) == "a")
        #expect(history.back(alive: all) == "m")
    }

    @Test func theOldestStepGoesPastTheLimit() {
        var history = BackForward<Int>()
        for step in 0...BackForward<Int>.limit + 1 { history.visit(step) }
        var behind: [Int] = []
        while let step = history.back(alive: { _ in true }) { behind.append(step) }
        #expect(behind.count == BackForward<Int>.limit)
        #expect(behind.last == 1)
    }
}
