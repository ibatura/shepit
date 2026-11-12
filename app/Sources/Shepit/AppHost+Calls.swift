import AppKit
import ShepitCore

/// Offers a meeting transcript when a call starts (call offer design §5): `CallWatch` says which app holds
/// the microphone, `CallOffer` decides, `CallPanel` shows it.
extension AppHost {
    func startCallWatch() {
        let watch = CallWatch { [weak self] change in
            Task { @MainActor in
                switch change {
                case .took(let bundleID, let pid):
                    if let source = CallSource(bundleID: bundleID) { self?.callEvent(.took(source, pid: pid)) }
                case .released(let pid):
                    self?.callEvent(.released(pid: pid))
                }
            }
        }
        watch.start()
        callWatch = watch
    }

    /// Feeds the state machine, does what it asks, and shows its panel. Returns the effects.
    @discardableResult
    func callEvent(_ event: CallOffer.Event) -> [CallOffer.Effect] {
        let effects = callOffer.handle(event, at: Date(), settings: settings)
        for effect in effects { run(effect) }
        if let shown = callOffer.panel {
            callPanel.show(shown, onMain: { [unowned self] in self.callEvent(.pressedMain) },
                           onOther: { [unowned self] in self.callEvent(.pressedOther) })
        } else {
            callPanel.hide()
        }
        // A name found after the offer is gone must not land on the next call.
        if offeredApp == nil { callNameLookup?.cancel() }
        // The timer runs only while time alone can change something.
        if callOffer.needsTick {
            callTicker = callTicker ?? TimerBox(repeating: 1) { [unowned self] in self.callEvent(.tick) }
        } else {
            callTicker?.cancel()
            callTicker = nil
        }
        return effects
    }

    /// The app of the offer on screen.
    private var offeredApp: CallApp? {
        switch callOffer.panel {
        case .offer(_, let app, _), .autoStart(_, let app, _): app
        default: nil
        }
    }

    private func run(_ effect: CallOffer.Effect) {
        switch effect {
        case .lookForMeet:
            Task.detached {
                // Titles of browser windows and tabs only; a Teams window must not hide a Meet tab.
                let windows = MeetingApps.scan(limit: 2, titlesOnly: true).windows.filter { MeetingTitle.browsers.contains($0.app) }
                let found = MeetingTitle.detect(windows).app == CallApp.meet.rawValue
                await MainActor.run { _ = self.callEvent(.meetFound(found)) }
            }
        case .lookForName:
            guard let app = offeredApp?.rawValue else { return }
            callNameLookup?.cancel()
            callNameLookup = Task {
                // The call window's tree can still be building: look up to 5 times, as Start does.
                var name: String?
                for attempt in 0..<5 where name == nil {
                    if attempt > 0 { try? await Task.sleep(for: .seconds(1)) }
                    let found = await Task.detached { MeetingApps.scan(limit: 2).detected }.value
                    if found.app == app { name = found.title }
                }
                // A repeating meeting (same time last week, or daily) is named like last time.
                let names = MeetingNames.load(Paths.dataDir.appending(path: MeetingNames.fileName))
                name = name ?? MeetingNames.repeating(names, at: Date(), app: app)
                if !Task.isCancelled, let name { self.callEvent(.named(name)) }
            }
        case .start(let title, let app):
            if let missing = meetingMissing {
                panel.message("⚠ Meeting transcript not started", detail: missing)
            } else {
                startMeeting(title: title, app: app.rawValue, fromCall: true)
            }
        case .stop:
            Task { await meeting?.stop() }
        case .removeEmptyNote:
            removeEmptyMeeting()
        case .namePeople:
            if let note = lastMeetingNote() { renameSpeakers(in: note) }
        case .record:
            break // statistics of offers: plan Task 7
        }
    }
}
