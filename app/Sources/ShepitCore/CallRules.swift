import Foundation

/// What Shepit does when a call of an app starts (settings review design §7): start a transcript on its own, offer
/// one, or nothing.
public enum CallMode: String, CaseIterable, Sendable {
    case auto, offer, off

    public var title: String {
        switch self {
        case .auto: "Auto"
        case .offer: "Offer"
        case .off: "Off"
        }
    }

    /// What the choice does, under it in Settings.
    public func about(autoStartSeconds: Int) -> String {
        switch self {
        case .auto: "Starts a transcript on its own after \(autoStartSeconds) s"
        case .offer: "Shows a panel with the call's name and a Start button"
        case .off: "Does nothing"
        }
    }
}

/// A rule by meeting name: the first of an app's rules that matches the call's name decides instead of the app's choice.
public struct CallRule: Hashable, Sendable {
    public enum Match: String, CaseIterable, Sendable {
        case contains, `is`
    }

    public var app: CallApp
    public var match: Match
    /// Empty matches nothing.
    public var text: String
    public var then: CallMode

    public init(app: CallApp, match: Match, text: String, then: CallMode) {
        self.app = app
        self.match = match
        self.text = text
        self.then = then
    }

    /// Case and the spaces around the name don't count.
    func matches(_ name: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespaces), name = name.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return false }
        switch match {
        case .contains: return name.range(of: text, options: .caseInsensitive) != nil
        case .is: return name.caseInsensitiveCompare(text) == .orderedSame
        }
    }

    /// A rule as `callRules` keeps it; nil when it isn't one.
    init?(file value: Any) {
        guard let rule = value as? [String: Any],
              let app = (rule["app"] as? String).flatMap(CallApp.init(rawValue:)),
              let match = (rule["match"] as? String).flatMap(Match.init(rawValue:)),
              let text = rule["text"] as? String,
              let then = (rule["then"] as? String).flatMap(CallMode.init(rawValue:)) else { return nil }
        self.init(app: app, match: match, text: text, then: then)
    }
}

extension Settings {
    /// The app's choice; an app missing from `callModes` is Off.
    public func callMode(for app: CallApp) -> CallMode { callModes[app] ?? .off }

    /// Whether the app's choice can turn on the call's name: it has a rule with some text.
    public func hasCallRules(for app: CallApp) -> Bool {
        callRules.contains { $0.app == app && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// What a call of `app` named `name` gets: an app set to Off ignores its rules; else its first rule that matches
    /// the name, else the app's choice.
    public func callChoice(app: CallApp, name: String?) -> CallMode {
        let mode = callMode(for: app)
        guard mode != .off, let name else { return mode }
        return callRules.first { $0.app == app && $0.matches(name) }?.then ?? mode
    }

    /// `callModes` as the file keeps it; nil when it isn't one.
    static func callModes(file value: Any) -> [CallApp: CallMode]? {
        guard let modes = value as? [String: Any] else { return nil }
        var result: [CallApp: CallMode] = [:]
        for (app, mode) in modes {
            guard let app = CallApp(rawValue: app), let mode = (mode as? String).flatMap(CallMode.init(rawValue:)) else { return nil }
            result[app] = mode
        }
        return result
    }

    /// `callRules` as the file keeps it; nil when it isn't one.
    static func callRules(file value: Any) -> [CallRule]? {
        guard let rules = value as? [Any] else { return nil }
        let result = rules.compactMap(CallRule.init(file:))
        return result.count == rules.count ? result : nil
    }
}
