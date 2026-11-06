import Foundation

/// Pure layout of the floating panel (port of the helpers in overlay.lua).
/// Coordinates are top-down, like the Lua canvas: y grows downwards from the panel's top edge.
public enum OverlayLayout {
    public static let pad = 18.0
    public static let margin = 80.0 // distance from the screen edge for top/bottom positions
    public static let meterGap = 16.0 // space between the text column and the meter column
    public static let minText = 200.0 // narrowest text column
    public static let barWidth = 6.0
    public static let barGap = 4.0
    public static let minBar = 3.0
    public static let frameSeconds = 0.06
    public static let fftSamples = 1024

    public struct Rect: Equatable, Sendable {
        public var x, y, w, h: Double

        public init(x: Double, y: Double, w: Double, h: Double) {
            self.x = x
            self.y = y
            self.w = w
            self.h = h
        }
    }

    public struct Bars: Equatable, Sendable {
        public var x, w, bottom, maxHeight: Double
    }

    public struct Geometry: Equatable, Sendable {
        public var width, height: Double
        public var title, body: Rect
        public var bars: Bars?
        public var tailChars: Int
    }

    public struct RGBA: Equatable, Sendable {
        public var red, green, blue, alpha: Double
    }

    public static func formatElapsed(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// The end of `text` in at most `maxChars` characters, cut at a word boundary, with a leading "…".
    public static func tailText(_ text: String, _ maxChars: Int) -> String {
        guard text.count > maxChars else { return text }
        let cut = String(text.suffix(maxChars - 1))
        if let space = cut.firstIndex(where: \.isWhitespace) {
            let word = cut[space...].drop(while: \.isWhitespace)
            if !word.isEmpty { return "…" + word }
        }
        return "…" + cut
    }

    public static func barHeight(_ value: Double, _ maxHeight: Double) -> Double {
        max(minBar, (min(1, value) * maxHeight + 0.5).rounded(.down))
    }

    /// `#RRGGBB` or `#RRGGBBAA`; `alpha` overrides the hex alpha.
    public static func color(_ hex: String, alpha: Double? = nil) -> RGBA {
        let digits = Array(hex.dropFirst())
        func byte(_ i: Int) -> Double {
            guard i + 2 <= digits.count, let value = UInt8(String(digits[i..<i + 2]), radix: 16) else { return 0 }
            return Double(value) / 255
        }
        return RGBA(red: byte(0), green: byte(2), blue: byte(4), alpha: alpha ?? (digits.count == 8 ? byte(6) : 1))
    }

    public static func recordingTitle(_ style: OverlayStyle, elapsed: Double) -> String {
        let title = "🔴  \(style.listeningText)"
        return style.showTimer ? "\(title) · \(formatElapsed(elapsed))" : title
    }

    /// Text column on the left, meter column on the right; they never share space.
    public static func geometry(_ style: OverlayStyle, withBars: Bool) -> Geometry {
        let fontSize = Double(style.fontSize)
        let titleH = (fontSize * 1.6).rounded(.up)
        let bodyH = (fontSize * 1.35 * 2).rounded(.up) + 4 // two lines
        let height = pad + titleH + 6 + bodyH + pad - 6
        let barsW = withBars ? Double(style.bars) * barWidth + Double(style.bars - 1) * barGap : 0
        let meterW = withBars ? barsW + meterGap : 0
        // widen the panel rather than squeeze the text column below minText
        let width = max(Double(style.width), 2 * pad + minText + meterW)
        let textW = width - 2 * pad - meterW
        let bars = withBars ? Bars(x: width - pad - barsW, w: barsW, bottom: height - pad, maxHeight: height - 2 * pad) : nil
        let charW = fontSize * 0.55
        return Geometry(
            width: width,
            height: height,
            title: Rect(x: pad, y: pad - 4, w: textW, h: titleH),
            body: Rect(x: pad, y: pad - 4 + titleH + 6, w: textW, h: bodyH),
            bars: bars,
            tailChars: max(20, Int((textW / charW * 2).rounded(.down)) - 4))
    }

    /// The panel's frame on `screen` (top-down coordinates).
    public static func panelFrame(screen: Rect, _ g: Geometry, position: String) -> Rect {
        let x = screen.x + (screen.w - g.width) / 2
        let y: Double = switch position {
        case "top": screen.y + margin
        case "center": screen.y + (screen.h - g.height) / 2
        default: screen.y + screen.h - g.height - margin
        }
        return Rect(x: x, y: y, w: g.width, h: g.height)
    }
}
