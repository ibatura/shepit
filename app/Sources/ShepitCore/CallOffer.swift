import Foundation

/// Apps whose calls get an offer; the raw values are the keys of `Settings.callModes` and what notes and databases keep.
public enum CallApp: String, Sendable, CaseIterable {
    case teams = "Teams", zoom = "Zoom", meet = "Meet"

    /// The name shown on screen; `rawValue` is what settings, notes and databases keep.
    public var title: String {
        switch self {
        case .teams: "Teams"
        case .zoom: "Zoom"
        case .meet: "Google Meet"
        }
    }

    /// The title of a stored app name, or the name itself when this version doesn't know it.
    public static func title(of stored: String) -> String { CallApp(rawValue: stored)?.title ?? stored }
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
        /// Last time's name of a repeating meeting, for an app with rules: it decides only if the app shows no name
        /// within the wait, as the lookup for the app's own name can outlast it.
        case remembered(String)
        /// The panel's main and second button.
        case pressedMain, pressedOther
        /// Home's Start for the call that runs now (`current`), with its offer on screen or not.
        case startCurrent
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

    public enum Outcome: String, Sendable, CaseIterable { case started, startedAutomatically, dismissed, hidden }

    public enum Effect: Equatable, Sendable {
        case lookForMeet, lookForName
        case start(title: String?, app: CallApp)
        case stop, removeEmptyNote, namePeople
        case record(Outcome, app: CallApp)
    }

    /// Seconds an app must hold the microphone to count as a call, and must have released it to count as the end.
    static let hold: TimeInterval = 3
    static let meetRetry: TimeInterval = 10
    /// How long the choice waits for the call's name when the app has rules (settings review design §7.1).
    static let namingWait: TimeInterval = 5
    static let readySeconds: TimeInterval = 8

    private enum Phase: Equatable {
        case pending
        /// `next` nil: waiting for the answer.
        case checkingMeet(next: Date?)
        /// Confirmed while the last transcript was finishing: offered once it has.
        case held
        /// Confirmed, and its app has rules: the choice waits for the name.
        case naming(since: Date)
        /// `auto`: the panel counts down to a start.
        case offered(since: Date, auto: Bool)
        /// Nothing more to show for this call.
        case quiet
    }

    private struct Call {
        var pid: Int32
        var app: CallApp?
        var since: Date
        var releasedAt: Date?
        var name: String?
        var remembered: String?
        var phase = Phase.pending
    }

    private struct Session {
        /// Started from the panel, or by hand during a call: stops when the call ends.
        var ours: Bool
        /// Started by hand while a call was not confirmed yet: ours once it is.
        var awaitsCall = false
        var end = End.open
        var endingSince: Date? { if case .counting(let since) = end { since } else { nil } }
    }

    /// How a session's end stands: nothing yet, the stop countdown, "Keep recording" pressed, or stopping.
    private enum End: Equatable { case open, counting(since: Date), kept, stopping }

    private var holders: [Int32: CallSource] = [:]
    private var call: Call?
    private var session: Session?
    private var ready: (until: Date, detail: String)?
    /// A start asked of the host and not confirmed yet.
    private var starting: (outcome: Outcome, app: CallApp)?
    public private(set) var panel: Panel?

    public init() {}

    public struct Current: Equatable, Sendable {
        public var name: String?
        public var app: CallApp

        public init(name: String?, app: CallApp) {
            self.name = name
            self.app = app
        }
    }

    /// The call running now, once it counts as one (also after a dismiss): the window offers Start for it.
    public var current: Current? {
        guard let call, let app = call.app, call.releasedAt == nil else { return nil }
        switch call.phase {
        case .naming, .offered, .quiet: return Current(name: call.name, app: app)
        case .pending, .checkingMeet, .held: return nil
        }
    }

    /// Whether time alone can change anything: without it no timer needs to run.
    public var needsTick: Bool {
        (call.map { ($0.phase != .quiet && $0.phase != .held) || $0.releasedAt != nil } ?? false) || session?.endingSince != nil || ready != nil
    }

    public mutating func handle(_ event: Event, at now: Date, settings: Settings) -> [Effect] {
        var effects: [Effect] = []
        switch event {
        case .took(let source, let pid):
            guard settings.callMode(for: source.app ?? .meet) != .off else { break } // an app set to Off is not watched
            holders[pid] = source
            if call?.pid == pid {
                call?.releasedAt = nil
                if call?.phase == .pending { call?.since = now } // the hold counts unbroken seconds
            } else if call == nil || (call?.app == nil && source.app != nil) {
                // A browser that has shown no Meet tab does not hold up an app's call; it stays in `holders`.
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
            if case .naming = call?.phase { decide(now, settings) }
        case .remembered(let name):
            call?.remembered = name
        case .pressedMain:
            // The buttons act on the panel that was on screen.
            switch panel {
            case .ended:
                session?.end = .kept
            case .offer(_, let app, _), .autoStart(_, let app, _):
                effects.append(start(app, .started))
            case .ready:
                ready = nil
                effects.append(.namePeople)
            case nil:
                break
            }
        case .startCurrent:
            guard session == nil, current != nil, let app = call?.app else { break }
            if case .offered = call?.phase {
                effects.append(start(app, .started)) // counted like its offer's Start
            } else {
                effects.append(.start(title: call?.name, app: app)) // the offer was answered already, or never shown
            }
        case .pressedOther:
            switch panel {
            case .ended:
                effects.append(.stop)
                session?.end = .stopping
            case .offer(_, let app, _), .autoStart(_, let app, _):
                effects.append(.record(.dismissed, app: app))
                call?.phase = .quiet
            case .ready, nil:
                ready = nil
            }
        case .sessionStarted(let byPanel):
            // Counted as started only now: a start that failed (model missing, folder error) never gets here.
            if byPanel, let starting { effects.append(.record(starting.outcome, app: starting.app)) }
            starting = nil
            let confirmed = call?.app != nil && call?.phase != .pending
            session = Session(ours: byPanel || confirmed, awaitsCall: call != nil && !confirmed)
            switch call?.phase {
            case .naming?, .offered?: call?.phase = .quiet
            default: break
            }
            ready = nil
        case .sessionStopping:
            session?.end = .stopping
        case .sessionFinished(let entries, let detail):
            if session?.ours == true, entries == 0 {
                effects.append(.removeEmptyNote)
            } else {
                ready = (now + Self.readySeconds, detail)
            }
            session = nil
            if call?.phase == .held { effects += offer(now, settings) }
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

    private mutating func start(_ app: CallApp, _ outcome: Outcome) -> Effect {
        starting = (outcome, app)
        call?.phase = .quiet
        return .start(title: call?.name, app: app)
    }

    /// The call is confirmed: offer it, unless a transcript already runs. A transcript that is finishing no longer
    /// records: the call waits for it, back-to-back calls (the author, 2026-11-19). With rules for its app the choice
    /// waits for the name; without, the panel is up at once and the name fills in.
    private mutating func offer(_ now: Date, _ settings: Settings) -> [Effect] {
        if session?.endingSince != nil { session?.end = .open } // a new call while the stop countdown runs: the transcript goes on
        if session?.awaitsCall == true { session?.ours = true }
        if session?.end == .stopping {
            call?.phase = .held
            return []
        }
        guard session == nil, let app = call?.app else {
            call?.phase = .quiet
            return []
        }
        if settings.hasCallRules(for: app) {
            call?.phase = .naming(since: now)
        } else {
            decide(now, settings)
        }
        return [.lookForName] // also for Home's Start when the choice is Off
    }

    /// The call's choice (settings review design §7.1): Auto or Offer puts its panel up; Off leaves Home's Start only.
    private mutating func decide(_ now: Date, _ settings: Settings) {
        guard let app = call?.app else { return }
        let choice = settings.callChoice(app: app, name: call?.name)
        call?.phase = choice == .off ? .quiet : .offered(since: now, auto: choice == .auto)
    }

    /// What the passing of time changes.
    private mutating func advance(_ now: Date, _ settings: Settings) -> [Effect] {
        var effects: [Effect] = []
        if let current = call, let released = current.releasedAt, now.timeIntervalSince(released) >= Self.hold {
            if case .offered = current.phase, let app = current.app { effects.append(.record(.hidden, app: app)) }
            if let running = session, running.ours, running.end != .kept, running.end != .stopping { session?.end = .counting(since: now) }
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
            session?.end = .counting(since: now)
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
            case .naming(let since) where now.timeIntervalSince(since) >= Self.namingWait:
                call?.name = current.name ?? current.remembered
                decide(now, settings)
            case .offered(let since, let auto):
                guard let app = current.app else { break }
                let elapsed = now.timeIntervalSince(since)
                if auto {
                    if elapsed >= Double(settings.callAutoStartSeconds) {
                        effects.append(start(app, .startedAutomatically))
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
            session?.end = .stopping
        }
        if let shown = ready, now >= shown.until { ready = nil }
        return effects
    }

    private func currentPanel(_ now: Date, _ settings: Settings) -> Panel? {
        func left(_ total: Int, _ since: Date) -> Int { max(0, Int((Double(total) - now.timeIntervalSince(since)).rounded(.up))) }
        if let since = session?.endingSince { return .ended(stopsIn: left(settings.callAutoStopSeconds, since)) }
        if let call, case .offered(let since, let auto) = call.phase, let app = call.app {
            let title = call.name ?? "\(app.title) call"
            if auto { return .autoStart(title: title, app: app, startsIn: left(settings.callAutoStartSeconds, since)) }
            return .offer(title: title, app: app, hidesIn: settings.callOfferSeconds == 0 ? nil : left(settings.callOfferSeconds, since))
        }
        return ready.map { .ready(detail: $0.detail) }
    }
}

extension CallOffer {
    /// The line of the "Transcript ready" panel: "42 min · 3 people · Weekly sync". The title goes last: the panel has
    /// one line, and a long title cut the numbers off (the author, 2026-11-20).
    public static func readyDetail(title: String?, duration: TimeInterval, speakers: Int?, recognised: Int = 0) -> String {
        let minutes = max(1, Int((duration / 60).rounded()))
        let people = speakers.flatMap { $0 > 0 ? "\($0) \($0 == 1 ? "person" : "people")" : nil }
        let known = recognised > 0 ? "\(recognised) recognised" : nil // voices design §9
        return ["\(minutes) min", people, known, title].compactMap { $0 }.joined(separator: " · ")
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
            Text(title: title, status: hidesIn.map { "\(app.title) · hides in \($0) s" } ?? app.title, seconds: hidesIn,
                 main: "Start transcript", other: "Not this call")
        case .autoStart(let title, let app, let startsIn):
            Text(title: title, status: "\(app.title) · transcript starts in \(startsIn) s", seconds: startsIn,
                 main: "Start now", other: "Don't record")
        case .ended(let stopsIn):
            Text(title: "Call ended", status: "Transcript stops in \(stopsIn) s", seconds: stopsIn,
                 main: "Keep recording", other: "Stop now")
        case .ready(let detail):
            Text(title: "Transcript ready", status: detail, seconds: nil, main: "Name people", other: "Close")
        }
    }
}
