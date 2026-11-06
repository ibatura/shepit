import AppKit
import ApplicationServices
import ShepitCore

/// Floating status panel that never takes focus (port of overlay.lua's canvas part).
@MainActor
final class OverlayPanel {
    private let style: () -> OverlayStyle
    private let tail: (Int) -> [Float]
    private var panel: NSPanel?
    private let view = OverlayView()
    private var ticker: Timer?
    private var clock: Timer?
    private var generation = 0
    private var startedAt = Date()
    private var previewText = ""
    private var state = "hidden"
    private var levels: [Float]?

    /// `tail(count)` gives the newest recorded samples for the meter.
    init(style: @escaping () -> OverlayStyle, tail: @escaping (Int) -> [Float]) {
        self.style = style
        self.tail = tail
    }

    func recording(_ at: Date) {
        generation += 1
        stopTimers()
        state = "recording"
        startedAt = at
        previewText = ""
        levels = nil
        let s = style()
        if layout(title: OverlayLayout.recordingTitle(s, elapsed: 0), withBars: true) {
            ticker = repeating(OverlayLayout.frameSeconds) { [weak self] in self?.updateBars() }
        }
        if s.showTimer {
            clock = repeating(1) { [weak self] in
                guard let self else { return }
                self.view.title = OverlayLayout.recordingTitle(self.style(), elapsed: Date().timeIntervalSince(self.startedAt))
            }
        }
    }

    func preview(_ text: String) {
        previewText = text
        if state == "recording" || state == "transcribing" { view.body = bodyText(text) }
    }

    func transcribing() {
        stopTimers()
        state = "transcribing"
        layout(title: "⏳  \(style().transcribingText)", withBars: false)
        view.body = bodyText(previewText)
    }

    func done(_ text: String) {
        generation += 1
        stopTimers()
        state = "done"
        let s = style()
        layout(title: "✓  \(s.doneText)", withBars: false)
        view.body = bodyText(text)
        if s.doneSeconds > 0 { hide(after: s.doneSeconds) } else { hide() }
    }

    /// `detail` goes on the two lines below the title (a title line is cut at the panel's width).
    func message(_ text: String, detail: String = "") {
        generation += 1
        stopTimers()
        state = "message"
        layout(title: text, withBars: false)
        view.body = detail
        hide(after: style().messageSeconds * (detail.isEmpty ? 1 : 2))
    }

    func hide() {
        stopTimers()
        state = "hidden"
        panel?.orderOut(nil)
    }

    /// Full layout only when the state changes; ticks update single fields.
    @discardableResult
    private func layout(title: String, withBars: Bool) -> Bool {
        let s = style()
        let bars = withBars && s.showMeter
        let geometry = OverlayLayout.geometry(s, withBars: bars)
        let panel = ensurePanel()
        view.style = s
        view.geometry = geometry
        view.title = title
        view.body = ""
        view.levels = bars ? [Float](repeating: 0, count: s.bars) : []
        panel.setFrame(frame(for: geometry, position: s.position), display: true)
        panel.orderFrontRegardless()
        return bars
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.contentView = view
        self.panel = panel
        return panel
    }

    /// On the screen with the focused window, converted from the layout's top-down coordinates.
    private func frame(for geometry: OverlayLayout.Geometry, position: String) -> NSRect {
        let visible = focusedScreen().visibleFrame
        let screen = OverlayLayout.Rect(x: visible.minX, y: 0, w: visible.width, h: visible.height)
        let f = OverlayLayout.panelFrame(screen: screen, geometry, position: position)
        return NSRect(x: f.x, y: visible.maxY - f.y - f.h, width: f.w, height: f.h)
    }

    private func focusedScreen() -> NSScreen {
        let fallback = NSScreen.main ?? NSScreen.screens[0]
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication else { return fallback }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.2) // a hung app mustn't stall the panel
        var window: CFTypeRef?
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return fallback }
        let axWindow = window as! AXUIElement
        AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &position)
        AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &size)
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard let position, let size,
              AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return fallback }
        // AX uses top-left origin on the primary screen; Cocoa uses bottom-left.
        let primaryHeight = NSScreen.screens[0].frame.height
        let centre = CGPoint(x: origin.x + extent.width / 2, y: primaryHeight - (origin.y + extent.height / 2))
        return NSScreen.screens.first { $0.frame.contains(centre) } ?? fallback
    }

    private func updateBars() {
        let s = style()
        let target = Spectrum.bands(tail(OverlayLayout.fftSamples), count: s.bars)
        levels = Spectrum.smooth(levels, target)
        view.levels = levels ?? []
    }

    private func bodyText(_ text: String) -> String {
        OverlayLayout.tailText(text, view.geometry?.tailChars ?? 80)
    }

    private func hide(after seconds: Double) {
        let generation = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.generation == generation else { return }
            self.hide()
        }
    }

    private func repeating(_ seconds: Double, _ action: @escaping @MainActor () -> Void) -> Timer {
        Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { _ in MainActor.assumeIsolated { action() } }
    }

    private func stopTimers() {
        ticker?.invalidate()
        clock?.invalidate()
        ticker = nil
        clock = nil
    }
}

/// Draws background, title, body and meter bars from the pure layout.
private final class OverlayView: NSView {
    var style = OverlayStyle.defaults
    var geometry: OverlayLayout.Geometry? { didSet { needsDisplay = true } }
    var title = "" { didSet { if title != oldValue { needsDisplay = true } } }
    var body = "" { didSet { if body != oldValue { needsDisplay = true } } }
    var levels: [Float] = [] { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true } // top-down, like the layout

    override func draw(_ dirtyRect: NSRect) {
        guard let geometry else { return }
        color(style.backgroundColor, alpha: style.opacity).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14).fill()

        let font = Double(style.fontSize)
        let titleStyle = NSMutableParagraphStyle()
        titleStyle.lineBreakMode = .byTruncatingTail
        (title as NSString).draw(in: rect(geometry.title), withAttributes: [
            .font: NSFont.systemFont(ofSize: font + 1), .foregroundColor: color(style.textColor), .paragraphStyle: titleStyle,
        ])
        let bodyStyle = NSMutableParagraphStyle()
        bodyStyle.lineBreakMode = .byWordWrapping
        (body as NSString).draw(in: rect(geometry.body), withAttributes: [
            .font: NSFont.systemFont(ofSize: font), .foregroundColor: color(style.textColor, alpha: 0.7), .paragraphStyle: bodyStyle,
        ])

        guard let bars = geometry.bars else { return }
        color(style.meterColor).setFill()
        for (i, level) in levels.enumerated() {
            let h = OverlayLayout.barHeight(Double(level), bars.maxHeight)
            let x = bars.x + Double(i) * (OverlayLayout.barWidth + OverlayLayout.barGap)
            NSBezierPath(roundedRect: NSRect(x: x, y: bars.bottom - h, width: OverlayLayout.barWidth, height: h), xRadius: 2, yRadius: 2).fill()
        }
    }

    private func rect(_ r: OverlayLayout.Rect) -> NSRect {
        NSRect(x: r.x, y: r.y, width: r.w, height: r.h)
    }

    private func color(_ hex: String, alpha: Double? = nil) -> NSColor {
        let c = OverlayLayout.color(hex, alpha: alpha)
        return NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
    }
}
