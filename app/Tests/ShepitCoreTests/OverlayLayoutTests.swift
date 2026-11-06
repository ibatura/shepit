import Testing
@testable import ShepitCore

// Ported from tests/test_overlay.lua.
struct OverlayLayoutTests {
    private func style(_ change: (inout OverlayStyle) -> Void = { _ in }) -> OverlayStyle {
        var style = OverlayStyle.defaults
        change(&style)
        return style
    }

    private func overlaps(_ a: OverlayLayout.Rect, _ b: OverlayLayout.Rect) -> Bool {
        a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
    }

    @Test func formatElapsed() {
        #expect(OverlayLayout.formatElapsed(0) == "0:00")
        #expect(OverlayLayout.formatElapsed(7.9) == "0:07")
        #expect(OverlayLayout.formatElapsed(65) == "1:05")
        #expect(OverlayLayout.formatElapsed(-1) == "0:00")
    }

    @Test func tailTextKeepsShortTextAndCutsLongTextAtAWordBoundary() {
        #expect(OverlayLayout.tailText("Привіт світ", 50) == "Привіт світ")
        #expect(OverlayLayout.tailText("один два три чотири", 12) == "…три чотири")
        #expect(OverlayLayout.tailText("", 10) == "")
    }

    @Test func tailTextCountsCharactersNotBytes() {
        let s = String(repeating: "ї", count: 30)
        #expect(OverlayLayout.tailText(s, 40) == s)
    }

    @Test func tailTextWithNoSpacesCutsByCharacters() {
        #expect(OverlayLayout.tailText("абвгдежзик", 5) == "…жзик")
    }

    @Test func barHeightHasAVisibleMinimumAndIsClamped() {
        #expect(OverlayLayout.barHeight(0, 40) == 3)
        #expect(OverlayLayout.barHeight(1, 40) == 40)
        #expect(OverlayLayout.barHeight(2, 40) == 40)
        #expect(OverlayLayout.barHeight(0.5, 40) == 20)
    }

    @Test func colorParses6And8DigitHexOpacityOverridesAlpha() {
        #expect(OverlayLayout.color("#FF8000") == .init(red: 1, green: 128.0 / 255, blue: 0, alpha: 1))
        #expect(OverlayLayout.color("#00000080").alpha == 128.0 / 255)
        #expect(OverlayLayout.color("#141414", alpha: 0.5).alpha == 0.5)
    }

    @Test func geometryBarsNeverOverlapTitleOrBodyText() throws {
        let variants: [(inout OverlayStyle) -> Void] = [
            { _ in }, { $0.bars = 24 }, { $0.fontSize = 28 }, { $0.width = 360; $0.bars = 24 }, { $0.width = 1200; $0.fontSize = 10 },
        ]
        for variant in variants {
            let g = OverlayLayout.geometry(style(variant), withBars: true)
            let bars = try #require(g.bars)
            let box = OverlayLayout.Rect(x: bars.x, y: bars.bottom - bars.maxHeight, w: bars.w, h: bars.maxHeight)
            #expect(!overlaps(g.body, box))
            #expect(!overlaps(g.title, box))
            #expect(g.body.w > 100)
            #expect(bars.x + bars.w <= g.width)
            #expect(g.body.y + g.body.h <= g.height)
        }
    }

    @Test func geometryWithoutBarsUsesTheFullWidthForText() {
        #expect(OverlayLayout.geometry(style(), withBars: false).body.w > OverlayLayout.geometry(style(), withBars: true).body.w)
    }

    @Test func geometryTailCharsGrowsWithWidthAndShrinksWithFontSize() {
        let base = OverlayLayout.geometry(style(), withBars: true).tailChars
        #expect(OverlayLayout.geometry(style { $0.width = 1000 }, withBars: true).tailChars > base)
        #expect(OverlayLayout.geometry(style { $0.fontSize = 24 }, withBars: true).tailChars < base)
    }

    @Test func panelFramePositionsThePanelOnTheScreen() {
        let screen = OverlayLayout.Rect(x: 0, y: 25, w: 1000, h: 800)
        var g = OverlayLayout.geometry(style(), withBars: false)
        g.width = 500
        g.height = 100
        #expect(OverlayLayout.panelFrame(screen: screen, g, position: "bottom") == .init(x: 250, y: 25 + 800 - 100 - 80, w: 500, h: 100))
        #expect(OverlayLayout.panelFrame(screen: screen, g, position: "top").y == 25 + 80)
        #expect(OverlayLayout.panelFrame(screen: screen, g, position: "center").y == 25 + 350)
    }

    @Test func recordingTitleUsesTheConfiguredTextAndTimerSetting() {
        #expect(OverlayLayout.recordingTitle(style(), elapsed: 65) == "🔴  Слухаю · 1:05")
        #expect(OverlayLayout.recordingTitle(style { $0.listeningText = "Listening"; $0.showTimer = false }, elapsed: 65) == "🔴  Listening")
    }
}
