import Foundation

/// dictionary.json: prompt terms, replace rules, extra phrases to drop.
public struct DictionaryFile: Equatable, Sendable {
    public var terms: [String]
    public var replace: [String: String]
    public var dropPhrases: [String]

    public static let empty = DictionaryFile(terms: [], replace: [:], dropPhrases: [])

    public init(terms: [String], replace: [String: String], dropPhrases: [String]) {
        self.terms = terms
        self.replace = replace
        self.dropPhrases = dropPhrases
    }
}

/// Prompt building and transcript post-processing (port of src/dictation/dictionary.lua).
public enum DictionaryRules {
    public static let builtinDrop = [
        "Дякую за перегляд",
        "Субтитри зроблено",
        "Субтитри створено",
        "Редактор субтитрів",
        "Продовження слідує",
        "Thanks for watching",
        "Thank you for watching",
        "Subtitles by",
    ]

    public static func estimateTokens(_ text: String) -> Double {
        text.split(whereSeparator: \.isWhitespace).reduce(0) { total, word in
            total + (word.unicodeScalars.contains { !$0.isASCII } ? 3 : 1.5)
        }
    }

    public static func buildPrompt(style: String, terms: [String], maxTokens: Double) -> String {
        var used = estimateTokens(style)
        var picked: [String] = []
        for term in terms {
            let cost = estimateTokens(term)
            if used + cost > maxTokens { break }
            used += cost
            picked.append(term)
        }
        let list = picked.joined(separator: ", ")
        if style.isEmpty { return list }
        if list.isEmpty { return style }
        return "\(style) \(list)"
    }

    /// Replaces whole-word, case-insensitive matches; the longest key wins at a position and
    /// output is never re-matched. `fired` lists the replacement of every match, in order.
    public static func applyReplacements(_ text: String, _ replace: [String: String]) -> (text: String, fired: [String]) {
        let rules = replace.filter { !$0.key.isEmpty }
            .map { (key: lowered(Array($0.key)), value: $0.value) }
            .sorted { $0.key.count != $1.key.count ? $0.key.count > $1.key.count : $0.key.joined() < $1.key.joined() }
        guard !rules.isEmpty else { return (text, []) }
        let chars = Array(text)
        let lower = lowered(chars)
        var out = ""
        var fired: [String] = []
        var pos = 0
        while pos < chars.count {
            let match = rules.first { rule in
                let stop = pos + rule.key.count
                guard stop <= chars.count, Array(lower[pos..<stop]) == rule.key else { return false }
                let wordStart = isWordChar(rule.key.first.flatMap(\.first))
                let wordEnd = isWordChar(rule.key.last.flatMap(\.last))
                return (!wordStart || pos == 0 || !isWordChar(chars[pos - 1]))
                    && (!wordEnd || stop == chars.count || !isWordChar(chars[stop]))
            }
            if let match {
                out += match.value
                fired.append(match.value)
                pos += match.key.count
            } else {
                out.append(chars[pos])
                pos += 1
            }
        }
        return (out, fired)
    }

    public static func stripHallucinations(_ text: String, extra: [String]) -> String {
        let phrases = (builtinDrop + extra).map(normalize).filter { !$0.isEmpty }
        var s = text.replacingOccurrences(of: #"\[[A-Z_]+\]"#, with: "", options: .regularExpression).trimmed
        while !s.isEmpty {
            let start = lastSentenceStart(s)
            let last = normalize(String(s[start...]))
            guard phrases.contains(where: { last.hasPrefix($0) }) else { break }
            s = String(s[..<start]).trimmed
        }
        return s
    }

    public static func process(_ text: String, _ dict: DictionaryFile) -> (text: String, fired: [String]) {
        let stripped = stripHallucinations(text, extra: dict.dropPhrases)
        let replaced = applyReplacements(stripped, dict.replace)
        let tidy = replaced.text.replacingOccurrences(of: " +", with: " ", options: .regularExpression).trimmed
        return (tidy, replaced.fired)
    }

    static func isWordChar(_ ch: Character?) -> Bool {
        guard let ch else { return false }
        return ch.isLetter || ch.isNumber || ch == "_" || ch == "'" || ch == "ʼ" || ch == "’"
    }

    // Per character, so lowercasing can never shift positions between text and its lowered copy.
    private static func lowered(_ chars: [Character]) -> [String] {
        chars.map { String($0).lowercased() }
    }

    /// Lowercase, collapse whitespace, drop non-word characters at both ends.
    private static func normalize(_ s: String) -> String {
        var chars = Array(s.lowercased().replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression))
        while let first = chars.first, !isWordChar(first) { chars.removeFirst() }
        while let last = chars.last, !isWordChar(last) { chars.removeLast() }
        return String(chars)
    }

    /// Where the last sentence of `s` begins: after the last `.`, `!`, `?` or `…` followed by whitespace.
    private static func lastSentenceStart(_ s: String) -> String.Index {
        var start = s.startIndex
        var searchFrom = s.startIndex
        while let range = s.range(of: #"[.!?…]\s+"#, options: .regularExpression, range: searchFrom..<s.endIndex) {
            start = range.upperBound
            searchFrom = range.upperBound
        }
        return start
    }
}

/// Validates a raw dictionary.json object (port of config.lua validateDictionary).
public func validateDictionary(_ raw: [String: Any]) -> (DictionaryFile?, [String]) {
    var dict = DictionaryFile.empty
    var errors: [String] = []
    for key in ["terms", "dropPhrases"] {
        guard let value = raw[key] else { continue }
        if let list = value as? [Any], let strings = list as? [String], strings.count == list.count {
            if key == "terms" { dict.terms = strings } else { dict.dropPhrases = strings }
        } else {
            errors.append(#"dictionary.json: "\#(key)" must be a list of strings"#)
        }
    }
    if let value = raw["replace"] {
        if let map = value as? [String: Any], let strings = map as? [String: String], strings.count == map.count {
            dict.replace = strings
        } else {
            errors.append(#"dictionary.json: "replace" must map strings to strings"#)
        }
    }
    return errors.isEmpty ? (dict, []) : (nil, errors)
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
