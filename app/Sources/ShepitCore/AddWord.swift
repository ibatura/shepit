import Foundation

/// Text for the Add to dictionary dialog, in English like the rest of the app (the author, 2026-11-23), and parsing of
/// its answer (port of addword.lua).
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
            message = "As heard = as it should be written (джира = Jira), or just the right spelling"
        } else {
            let shown = selected.count <= maxShown ? selected : String(selected.prefix(maxShown - 1)) + "…"
            message = "“\(shown)” → how should it be written?" + (existing.map { " (now: \($0))" } ?? "")
        }
        return Prompt(title: "Add to dictionary", message: message, defaultValue: existing ?? "")
    }

    public static func parse(selected: String, input: String) -> Answer {
        if !selected.isEmpty {
            if selected.split(whereSeparator: \.isWhitespace).count > maxWords {
                return .error("Too much text is selected: select one word or a short phrase")
            }
            return .rule(wrong: selected, right: input.trimmed)
        }
        if let equals = input.firstIndex(of: "=") {
            return .rule(wrong: String(input[..<equals]).trimmed, right: String(input[input.index(after: equals)...]).trimmed)
        }
        return .rule(wrong: "", right: input.trimmed)
    }
}
