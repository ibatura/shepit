import AppKit
import ShepitCore

/// The menu bar's rhombus, drawn (icon and name design §6). The app icon, H1, is drawn from the same glyph by scripts/make-icon.py.
extension MenuIcon {
    /// The glyph in 18×18 pt (round 3): 7 columns, with a gap in the middle one for the heart.
    private static let bars: [NSRect] = [
        (0.9, 7.8, 2.4), (3.3, 5.3, 7.4), (5.8, 3, 5.6), (5.8, 9.4, 5.6), (8.2, 0.5, 5.6),
        (8.2, 11.9, 5.6), (10.6, 3, 5.6), (10.6, 9.4, 5.6), (13.1, 5.3, 7.4), (15.5, 7.8, 2.4),
    ].map { NSRect(x: $0.0, y: $0.1, width: 1.6, height: $0.2) }

    /// AppKit may call the drawing handler on any thread, so it captures only the icon.
    var image: NSImage {
        let icon = self, side: CGFloat = 18, dot: CGFloat = 6
        let left: CGFloat = meeting ? dot + 3 : 0
        let image = NSImage(size: NSSize(width: left + side, height: side), flipped: true) { _ in
            if icon.meeting {
                NSColor.systemRed.setFill()
                NSBezierPath(ovalIn: NSRect(x: 0, y: (side - dot) / 2, width: dot, height: dot)).fill()
            }
            let ink: NSColor = icon.isPlain ? .black : .labelColor // a template keeps only the alpha
            let colour = switch icon.mark {
            case .recording: NSColor.systemRed
            case .transcribing: ink.withAlphaComponent(0.4)
            case .ready, .problem: ink
            }
            let badge = NSRect(x: left + side - 5, y: 0, width: 5, height: 5)
            NSGraphicsContext.saveGraphicsState()
            if icon.mark == .problem { // 1 pt clear around the dot, so it doesn't touch the bars
                let clip = NSBezierPath(rect: NSRect(x: 0, y: 0, width: left + side, height: side))
                clip.appendOval(in: badge.insetBy(dx: -1, dy: -1))
                clip.windingRule = .evenOdd
                clip.addClip()
            }
            colour.setFill()
            for bar in Self.bars { NSBezierPath(roundedRect: bar.offsetBy(dx: left, dy: 0), xRadius: 0.4, yRadius: 0.4).fill() }
            NSGraphicsContext.restoreGraphicsState()
            if icon.mark == .problem {
                NSColor.systemOrange.setFill()
                NSBezierPath(ovalIn: badge).fill()
            }
            return true
        }
        image.isTemplate = isPlain
        return image
    }
}

/// `Shepit menubar-test`: shows each menu bar icon for a moment, for looking at it without a dictation or a call.
/// Shepit's theme doesn't matter here: a status item has the menu bar's own appearance, whatever `NSApp.appearance` is.
enum MenuBarTest {
    @MainActor static func run() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        Task { @MainActor in
            for icon in MenuIcon.allCases {
                item.button?.image = icon.image
                print("\(icon.mark)\(icon.meeting ? ", meeting" : "")")
                try? await Task.sleep(for: .seconds(2))
            }
            exit(0)
        }
        application.run()
    }
}
