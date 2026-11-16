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

    /// At the end; a term already there stays where it is.
    public mutating func add(term: String) {
        if !terms.contains(term) { terms.append(term) }
    }

    /// `term` takes `target`'s place (a chip dropped on another).
    public mutating func move(term: String, to target: String) {
        guard term != target, let from = terms.firstIndex(of: term), let to = terms.firstIndex(of: target) else { return }
        terms.remove(at: from)
        terms.insert(term, at: to)
    }

    public mutating func add(dropPhrase: String) {
        if !dropPhrases.contains(dropPhrase) { dropPhrases.append(dropPhrase) }
    }

    /// `heard → written`, kept with `heard` in lower case. `previous` is the rule's heard phrase before an edit. Refuses
    /// an empty side and a heard phrase another rule has (in any case), so a change never drops another rule.
    public mutating func setRule(heard: String, written: String, replacing previous: String? = nil) throws {
        let heard = heard.trimmed, written = written.trimmed
        guard !heard.isEmpty, !written.isEmpty else { throw DictionaryStoreError.emptyRule }
        var replace = replace
        if let previous { replace[previous] = nil }
        guard !replace.keys.contains(where: { $0.lowercased() == heard.lowercased() }) else { throw DictionaryStoreError.ruleExists(heard) }
        replace[heard.lowercased()] = written
        self.replace = replace
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

    /// About how many tokens of style prompt and terms the engine reads.
    public static let promptTokens = 200.0

    public static func buildPrompt(style: String, terms: [String], maxTokens: Double = promptTokens) -> String {
        let list = terms.prefix(fittingTerms(style: style, terms: terms, maxTokens: maxTokens)).joined(separator: ", ")
        if style.isEmpty { return list }
        if list.isEmpty { return style }
        return "\(style) \(list)"
    }

    /// How many of the first terms fit the prompt after `style`; the count stops at the first term that does not fit.
    public static func fittingTerms(style: String, terms: [String], maxTokens: Double = promptTokens) -> Int {
        var used = estimateTokens(style)
        for (index, term) in terms.enumerated() {
            used += estimateTokens(term)
            if used > maxTokens { return index }
        }
        return terms.count
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
