import Foundation

/// Text for the "add to dictionary" dialog and parsing of its answer (port of addword.lua).
public enum AddWord {
    public static let maxWords = 6
    public static let maxShown = 40

    public struct Prompt: Equatable, Sendable {
        public var title: String
        public var message: String
        public var defaultValue: String
    }

    public enum Answer: Equatable, Sendable {
        case rule(wrong: String, right: String)
        case error(String)
    }

    public static func prompt(selected: String, existing: String?) -> Prompt {
        let message: String
        if selected.isEmpty {
            message = "Як Whisper пише → як має бути (через «=»), або лише правильне слово"
        } else {
            let shown = selected.count <= maxShown ? selected : String(selected.prefix(maxShown - 1)) + "…"
            message = "«\(shown)» → як має бути?" + (existing.map { " (зараз: \($0))" } ?? "")
        }
        return Prompt(title: "Додати в словник", message: message, defaultValue: existing ?? "")
    }

    public static func parse(selected: String, input: String) -> Answer {
        if !selected.isEmpty {
            if selected.split(whereSeparator: \.isWhitespace).count > maxWords {
                return .error("Виділено забагато тексту — виділіть одне слово або коротку фразу")
            }
            return .rule(wrong: selected, right: input.trimmed)
        }
        if let equals = input.firstIndex(of: "=") {
            return .rule(wrong: String(input[..<equals]).trimmed, right: String(input[input.index(after: equals)...]).trimmed)
        }
        return .rule(wrong: "", right: input.trimmed)
    }
}
