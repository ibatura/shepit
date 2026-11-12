import Foundation

/// Apps whose calls get an offer; the raw values are the names in `Settings.callApps`.
public enum CallApp: String, Sendable, CaseIterable {
    case teams = "Teams", zoom = "Zoom", meet = "Meet"
}

/// What a process holding the microphone is (call offer design §5.1). A browser counts only with a Meet tab.
public enum CallSource: Equatable, Sendable {
    case app(CallApp), browser

    static let browsers = ["com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser",
                           "company.thebrowser.Browser", "org.chromium.Chromium"]

    /// nil = not a call app. Prefixes, because the microphone is held by helpers
    /// ("com.microsoft.teams2.modulehost", "com.google.Chrome.helper", probe of 2026-11-11).
    public init?(bundleID: String) {
        if bundleID.hasPrefix("com.microsoft.teams2") {
            self = .app(.teams)
        } else if bundleID.hasPrefix("us.zoom.xos") {
            self = .app(.zoom)
        } else if Self.browsers.contains(where: bundleID.hasPrefix) {
            self = .browser
        } else {
            return nil
        }
    }

    var app: CallApp? { if case .app(let app) = self { app } else { nil } }
}

/// Decides when to offer a meeting transcript, start it and stop it (call offer design §5.3). Pure: fed with
/// events and the time, it returns what to do and keeps what the floating panel shows in `panel`.
public struct CallOffer: Sendable {
    public enum Event: Equatable, Sendable {
        /// A process took or released the microphone (`CallWatch`).
        case took(CallSource, pid: Int32), released(pid: Int32)
        /// Answers to `.lookForMeet` and `.lookForName`.
        case meetFound(Bool), named(String?)
        /// The panel's main and second button.
        case pressedMain, pressedOther
        case sessionStarted(byPanel: Bool)
        /// Stop was pressed or the session stopped by itself: it is finishing.
        case sessionStopping
        case sessionFinished(entries: Int, detail: String)
        /// Once a second while `needsTick`.
        case tick
    }

    public enum Panel: Equatable, Sendable {
        /// Start transcript · Not this call. `hidesIn` nil: stays until a button is pressed.
        case offer(title: String, app: CallApp, hidesIn: Int?)
        /// Start now · Don't record.
        case autoStart(title: String, app: CallApp, startsIn: Int)
        /// Keep recording · Stop now.
        case ended(stopsIn: Int)
        /// Name people · Close.
        case ready(detail: String)
    }

    public enum Outcome: String, Sendable { case started, startedAutomatically, dismissed, hidden }

    public enum Effect: Equatable, Sendable {
        case lookForMeet, lookForName
        case start(title: String?, app: CallApp)
        case stop, removeEmptyNote, namePeople
        case record(Outcome, app: CallApp)
    }

    /// Seconds an app must hold the microphone to count as a call, and must have released it to count as the end.
    static let hold: TimeInterval = 3
    static let meetRetry: TimeInterval = 10
    static let readySeconds: TimeInterval = 8

    private enum Phase: Equatable {
        case pending
        /// `next` nil: waiting for the answer.
        case checkingMeet(next: Date?)
        case offered(since: Date)
        /// Nothing more to show for this call.
        case quiet
    }

    private struct Call {
        var pid: Int32
        var app: CallApp?
        var since: Date
        var releasedAt: Date?
        var name: String?
        var phase = Phase.pending
    }

    private struct Session {
        /// Started from the panel, or by hand during a call: stops when the call ends.
        var ours: Bool
        /// Started by hand while a call was not confirmed yet: ours once it is.
        var awaitsCall = false
        var keep = false
        var stopping = false
        var endingSince: Date?
    }

    private var holders: [Int32: CallSource] = [:]
    private var call: Call?
    private var session: Session?
    private var ready: (until: Date, detail: String)?
    public private(set) var panel: Panel?

    public init() {}

    /// Whether time alone can change anything: without it no timer needs to run.
    public var needsTick: Bool {
        (call.map { $0.phase != .quiet || $0.releasedAt != nil } ?? false) || session?.endingSince != nil || ready != nil
    }

    public mutating func handle(_ event: Event, at now: Date, settings: Settings) -> [Effect] {
        var effects: [Effect] = []
        switch event {
        case .took(let source, let pid):
            guard settings.callApps.contains((source.app ?? .meet).rawValue) else { break }
            holders[pid] = source
            if call?.pid == pid {
                call?.releasedAt = nil
                if call?.phase == .pending { call?.since = now } // the hold counts unbroken seconds
            } else if call == nil {
                begin(pid, source, now)
            }
        case .released(let pid):
            holders[pid] = nil
            if call?.pid == pid, call?.releasedAt == nil { call?.releasedAt = now }
        case .meetFound(let found):
            guard case .checkingMeet = call?.phase else { break }
            if found {
                call?.app = .meet
                effects += offer(now, settings)
            } else {
                call?.phase = .checkingMeet(next: now + Self.meetRetry)
            }
        case .named(let name):
            call?.name = name
        case .pressedMain:
            if session?.endingSince != nil {
                session?.endingSince = nil
                session?.keep = true
            } else if case .offered = call?.phase, let app = call?.app {
                effects += [.start(title: call?.name, app: app), .record(.started, app: app)]
                call?.phase = .quiet
            } else if ready != nil {
                ready = nil
                effects.append(.namePeople)
            }
        case .pressedOther:
            if session?.endingSince != nil {
                effects.append(.stop)
                session?.endingSince = nil
                session?.stopping = true
            } else if case .offered = call?.phase, let app = call?.app {
                effects.append(.record(.dismissed, app: app))
                call?.phase = .quiet
            } else {
                ready = nil
            }
        case .sessionStarted(let byPanel):
            let confirmed = call?.app != nil && call?.phase != .pending
            session = Session(ours: byPanel || confirmed, awaitsCall: call != nil && !confirmed)
            if case .offered = call?.phase { call?.phase = .quiet }
            ready = nil
        case .sessionStopping:
            session?.stopping = true
            session?.endingSince = nil
        case .sessionFinished(let entries, let detail):
            if session?.ours == true, entries == 0 {
                effects.append(.removeEmptyNote)
            } else {
                ready = (now + Self.readySeconds, detail)
            }
            session = nil
        case .tick:
            break
        }
        effects += advance(now, settings)
        panel = currentPanel(now, settings)
        return effects
    }

    private mutating func begin(_ pid: Int32, _ source: CallSource, _ now: Date) {
        call = Call(pid: pid, app: source.app, since: now)
    }

    /// The call is confirmed: offer it, unless offers are off or a transcript already runs.
    private mutating func offer(_ now: Date, _ settings: Settings) -> [Effect] {
        session?.endingSince = nil // a new call while the stop countdown runs: the transcript goes on
        if session?.awaitsCall == true { session?.ours = true }
        guard settings.callOffer, session == nil else {
            call?.phase = .quiet
            return []
        }
        call?.phase = .offered(since: now)
        return [.lookForName]
    }

    /// What the passing of time changes.
    private mutating func advance(_ now: Date, _ settings: Settings) -> [Effect] {
        var effects: [Effect] = []
        if let current = call, let released = current.releasedAt, now.timeIntervalSince(released) >= Self.hold {
            if case .offered = current.phase, let app = current.app { effects.append(.record(.hidden, app: app)) }
            if let running = session, running.ours, !running.stopping, !running.keep { session?.endingSince = now }
            call = nil
            session?.awaitsCall = false
            // Another holder becomes the call: an app before a browser, then the lowest pid.
            if let next = holders.min(by: { ($0.value.app == nil ? 1 : 0, $0.key) < ($1.value.app == nil ? 1 : 0, $1.key) }) {
                begin(next.key, next.value, now)
            }
        }
        // While a new holder may still turn out to be a call, the stop countdown waits.
        if let current = call, current.releasedAt == nil, session?.endingSince != nil,
           current.phase == .pending || current.phase == .checkingMeet(next: nil) {
            session?.endingSince = now
        }
        if let current = call {
            switch current.phase {
            case .pending where current.releasedAt == nil && now.timeIntervalSince(current.since) >= Self.hold:
                if current.app != nil {
                    effects += offer(now, settings)
                } else {
                    call?.phase = .checkingMeet(next: nil)
                    effects.append(.lookForMeet)
                }
            case .checkingMeet(let next?) where now >= next:
                call?.phase = .checkingMeet(next: nil)
                effects.append(.lookForMeet)
            case .offered(let since):
                guard let app = current.app else { break }
                let elapsed = now.timeIntervalSince(since)
                if settings.callAutoStart {
                    if elapsed >= Double(settings.callAutoStartSeconds) {
                        effects += [.start(title: current.name, app: app), .record(.startedAutomatically, app: app)]
                        call?.phase = .quiet
                    }
                } else if settings.callOfferSeconds > 0, elapsed >= Double(settings.callOfferSeconds) {
                    effects.append(.record(.hidden, app: app))
                    call?.phase = .quiet
                }
            default:
                break
            }
        }
        if let since = session?.endingSince, now.timeIntervalSince(since) >= Double(settings.callAutoStopSeconds) {
            effects.append(.stop)
            session?.endingSince = nil
            session?.stopping = true
        }
        if let shown = ready, now >= shown.until { ready = nil }
        return effects
    }

    private func currentPanel(_ now: Date, _ settings: Settings) -> Panel? {
        func left(_ total: Int, _ since: Date) -> Int { max(0, Int((Double(total) - now.timeIntervalSince(since)).rounded(.up))) }
        if let since = session?.endingSince { return .ended(stopsIn: left(settings.callAutoStopSeconds, since)) }
        if let call, case .offered(let since) = call.phase, let app = call.app {
            let title = call.name ?? "\(app.rawValue) call"
            if settings.callAutoStart { return .autoStart(title: title, app: app, startsIn: left(settings.callAutoStartSeconds, since)) }
            return .offer(title: title, app: app, hidesIn: settings.callOfferSeconds == 0 ? nil : left(settings.callOfferSeconds, since))
        }
        return ready.map { .ready(detail: $0.detail) }
    }
}

extension CallOffer {
    /// The line of the "Transcript ready" panel: "Weekly sync · 42 min · 3 people".
    public static func readyDetail(title: String?, duration: TimeInterval, speakers: Int?) -> String {
        let minutes = max(1, Int((duration / 60).rounded()))
        let people = speakers.flatMap { $0 > 0 ? "\($0) \($0 == 1 ? "person" : "people")" : nil }
        return [title, "\(minutes) min", people].compactMap { $0 }.joined(separator: " · ")
    }
}

extension CallOffer.Panel {
    /// What the floating panel says (visual style §6). `seconds` is the countdown behind the progress bar.
    public struct Text: Equatable, Sendable {
        public var title, status: String
        public var seconds: Int?
        public var main, other: String
    }

    public var text: Text {
        switch self {
        case .offer(let title, let app, let hidesIn):
            Text(title: title, status: hidesIn.map { "\(app.rawValue) · hides in \($0) s" } ?? app.rawValue, seconds: hidesIn,
                 main: "Start transcript", other: "Not this call")
        case .autoStart(let title, let app, let startsIn):
            Text(title: title, status: "\(app.rawValue) · transcript starts in \(startsIn) s", seconds: startsIn,
                 main: "Start now", other: "Don't record")
        case .ended(let stopsIn):
            Text(title: "Call ended", status: "Transcript stops in \(stopsIn) s", seconds: stopsIn,
                 main: "Keep recording", other: "Stop now")
        case .ready(let detail):
            Text(title: "Transcript ready", status: detail, seconds: nil, main: "Name people", other: "Close")
        }
    }
}
