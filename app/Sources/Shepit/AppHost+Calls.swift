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
        // The panel first: an effect can open a dialog and stay in it.
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
        for effect in effects { run(effect) }
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
                let windows = MeetingApps.scan(limit: 2, depth: .titles).windows.filter { MeetingTitle.browsers.contains($0.app) }
                let found = MeetingTitle.detect(windows).app == CallApp.meet.rawValue
                await MainActor.run { _ = self.callEvent(.meetFound(found)) }
            }
        case .lookForName:
            guard let app = offeredApp?.rawValue else { return }
            // A repeating meeting (same time last week, or daily) is named like last time, at once.
            let names = MeetingNames.load(Paths.dataDir.appending(path: MeetingNames.fileName))
            if let name = MeetingNames.repeating(names, at: Date(), app: app) { callEvent(.named(name)) }
            callNameLookup?.cancel()
            callNameLookup = Task {
                // The name the app shows wins. The call window's tree can still be building: look up to 5 times, as Start does.
                for attempt in 0..<5 {
                    if attempt > 0 { try? await Task.sleep(for: .seconds(1)) }
                    if Task.isCancelled { return }
                    let found = await Task.detached {
                        // Only the windows of the call's own kind: a Teams window must not hide the Meet call's name.
                        var scan = MeetingApps.scan(limit: 2)
                        scan.windows = scan.windows.filter { MeetingTitle.browsers.contains($0.app) == (app == CallApp.meet.rawValue) }
                        return scan.detected
                    }.value
                    if Task.isCancelled { return }
                    if found.app == app, let name = found.title {
                        self.callEvent(.named(name))
                        return
                    }
                }
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
        case .record(let outcome, _):
            // A start that failed (model missing, folder error) is not counted as started.
            if outcome == .started || outcome == .startedAutomatically, !meetingActive { break }
            // statistics of offers: plan Task 7
        }
    }
}
