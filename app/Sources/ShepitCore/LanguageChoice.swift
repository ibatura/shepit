import Foundation

/// Ukrainian or English for one piece of a phrase, from Whisper's language detection.
/// English wins when it ranks first. Otherwise Ukrainian, unless the stream has been English lately
/// (`leaning`): then a short accented English piece that ranked something else first stays English,
/// and only a clearly Slavic piece is Ukrainian. In the Nov 4 Teams call 4 of 82 English call lines came
/// out as Ukrainian gibberish ("Адвання, часи, часи." for "advantages and disadvantages").
public enum LanguageChoice {
    /// Share of uk + ru + be a piece needs to be Ukrainian on an English stream.
    static let sureUkrainian: Float = 0.6

    public static func pick(top: String, probabilities: [String: Float], leaning: String?) -> String {
        if top == "en" { return "en" }
        guard leaning == "en" else { return "uk" }
        let slavic = ["uk", "ru", "be"].reduce(Float(0)) { $0 + (probabilities[$1] ?? 0) }
        return slavic >= sureUkrainian ? "uk" : "en"
    }
}

/// What one meeting stream has been speaking lately: "en" when at least 75% of its last 2 minutes of
/// recognized speech (20 s at least) was English, else nil. Kept per stream: the call can be English
/// while I speak Ukrainian.
public struct LanguageLeaning: Sendable {
    static let window: Double = 120
    static let enough: Double = 20
    static let share = 0.75

    private var recent: [(seconds: Double, english: Double)] = []

    public init() {}

    /// `detected` is the transcript's language: "en", "uk", or a join like "uk+en" (counted half English).
    public mutating func add(seconds: Double, detected: String?) {
        guard seconds > 0, let detected, !detected.isEmpty else { return }
        let parts = detected.split(separator: "+")
        let english = Double(parts.filter { $0 == "en" }.count) / Double(parts.count)
        recent.append((seconds, english * seconds))
        var total = recent.reduce(0) { $0 + $1.seconds }
        while total - recent[0].seconds >= Self.window {
            total -= recent.removeFirst().seconds
        }
    }

    public var leaning: String? {
        let total = recent.reduce(0) { $0 + $1.seconds }
        guard total >= Self.enough else { return nil }
        return recent.reduce(0) { $0 + $1.english } / total >= Self.share ? "en" : nil
    }
}
