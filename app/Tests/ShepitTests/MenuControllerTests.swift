import AppKit
import Testing
@testable import Shepit
import ShepitCore

// Icon and name design §6. AppKit may draw the menu bar's image on any thread, so each icon is drawn off the main one.
struct MenuControllerTests {
    @Test func everyIconDrawsItsRhombusOffTheMainThread() async {
        for mark in MenuIcon.Mark.allCases {
            for meeting in [false, true] {
                let icon = MenuIcon(mark: mark, meeting: meeting)
                let (size, isTemplate, rhombus) = await Task.detached { () -> (NSSize, Bool, CGFloat) in
                    let image = MenuController.image(icon)
                    let scale = 2
                    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(image.size.width) * scale, pixelsHigh: Int(image.size.height) * scale,
                                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return (.zero, false, 0) }
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                    image.draw(in: NSRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh))
                    NSGraphicsContext.restoreGraphicsState()
                    // Inside the middle column's top bar (x 8.2–9.8, y 0.5–6.1 from the top), after the meeting's dot.
                    let x = (image.size.width - 18 + 9) * CGFloat(scale), y = 3 * CGFloat(scale)
                    return (image.size, image.isTemplate, rep.colorAt(x: Int(x), y: Int(y))?.alphaComponent ?? 0)
                }.value
                #expect(size == NSSize(width: meeting ? 27 : 18, height: 18), "\(icon)")
                #expect(isTemplate == icon.isPlain, "\(icon)")
                #expect(rhombus > 0, "\(icon)")
            }
        }
    }
}
