# Offer to record when a call starts: implementation plan

**Goal:** When Teams, Zoom or a Meet page in Chrome holds the microphone, Shepit shows a small panel with the call's name and a Start button. One click starts the meeting transcript. When the app releases the microphone, a panel counts down and the transcript stops. With `callAutoStart` on, the transcript starts by itself after a countdown.

**Architecture:** The decisions are a pure state machine in `ShepitCore` (`CallOffer`), fed with events and settings and fully unit-tested. System code in `Shepit` stays thin: `CallWatch` turns Core Audio's per-process microphone flag into "took" and "released" events, `CallPanel` draws what the state machine says, and `AppHost+Calls` connects them to the existing meeting session.

**Spec:** `docs/superpowers/specs/2026-11-12-call-offer-design.md` ("the spec"; section numbers refer to it). Panels and settings keys: `docs/superpowers/specs/2026-11-11-visual-style/visual-style.md` §5.7 Calls and §6, `mockups.html` screens 8 and 9.

**Branch:** `call-offer`, cut from `ui-redesign` (which holds the specs). Ask the author before merging into `main` and before pushing.

## Execution notes

- One task at a time, a commit per task, `make test` green after each (407 tests on 2026-11-10).
- Tests first for everything in `ShepitCore`.
- The author's own `~/.config/dictation/settings.json` is not changed by code or tests.
- Try a change with `scripts/install.sh`. Before running a temporary command of the app, check that the build succeeded.
- **Author gates: Tasks 3 and 8.**

## Global constraints

- Nothing is recorded without a click while `callAutoStart` is off.
- Only Teams, Zoom and a browser with a Meet tab can give an offer. Dictation, and any other app holding the microphone, never does.
- No network. No new permission: the microphone flag needs none; names use the Accessibility Shepit already has.
- Offer rows in `stats.sqlite` hold no names and no text.
- Constants from the spec: 3 s to count as a call, 3 s released to count as its end, `callOfferSeconds` 15 (0 or 5–120), `callAutoStartSeconds` 5 (3–60), `callAutoStopSeconds` 10 (3–120).

## Review focus

1. **No start without a click** unless `callAutoStart` is on. Pinned by Task 2 tests.
2. **One offer per call**, none after a dismiss, none while a transcript runs or finishes. Task 2.
3. **A transcript is never stopped while its call still holds the microphone**, and a transcript without a call is never stopped by this feature. Task 2.
4. **The panel never takes keyboard focus**: a dictation or typing in the call app is not interrupted. Tasks 5 and 8.
5. **Watching is cheap**: no Accessibility walk while no call app holds the microphone. Tasks 3 and 6.

## File structure

```
app/Sources/ShepitCore/
  Settings.swift / SettingsValidation.swift   + call keys (Task 1)
  CallOffer.swift            apps by bundle ID, the state machine, panel content (Task 2)
  Stats.swift / StatsDatabase.swift           + offers table (Task 7)
app/Sources/Shepit/
  CallWatch.swift            Core Audio process flags → took / released events (Task 3)
  CallPanel.swift            floating panel, SwiftUI content, countdown bar (Task 5)
  AppHost+Calls.swift        wiring: watch → state machine → panel → meeting session (Task 6)
  AppHost+Meetings.swift     startMeeting variant without the dialog; empty transcript removed (Task 4)
  Settings/CallsSection.swift                 the Calls section (Task 7)
  main.swift                 `call-watch` diagnostic command (Task 3)
```

---

### Task 1: Call settings

**Files:** `ShepitCore/Settings.swift`, `SettingsValidation.swift`, `examples/settings.json`, `README.md` (settings table); tests in `SettingsTests.swift`.
**Spec:** §5.6; visual style §5.7.

**Interfaces:** `Settings` gets `callOffer: Bool` (true), `callOfferSeconds: Int` (15), `callAutoStart: Bool` (false), `callAutoStartSeconds: Int` (5), `callAutoStopSeconds: Int` (10), `callApps: [String]` (`["Teams", "Zoom", "Meet"]`).

- [ ] Tests: defaults; `callOfferSeconds` accepts 0 and 5–120, rejects 1–4, 121 and negatives; the two other ranges; `callApps` accepts any subset of Teams, Zoom, Meet (empty too), rejects other names and duplicates; unknown keys kept on update; a settings file without the new keys still loads. → FAIL → implement → PASS.
- [ ] `examples/settings.json` and the README table get the keys with defaults. Commit `Shepit: call offer settings`.

### Task 2: The decisions

**Files:** Create `ShepitCore/CallOffer.swift`, `Tests/ShepitCoreTests/CallOfferTests.swift`.
**Spec:** §5.1 (table), §5.2, §5.3, §6.

**Interfaces:**
```swift
public enum CallApp: String, Sendable { case teams = "Teams", zoom = "Zoom", meet = "Meet"
    /// nil = not a call app; .browser needs a Meet tab before it counts.
    public static func source(bundleID: String) -> CallSource? }
public enum CallSource: Equatable, Sendable { case app(CallApp), browser }

public struct CallOffer {
    public enum Event { case took(CallSource, pid: Int32), released(pid: Int32), meetFound(Bool), named(String?),
                        pressedStart, pressedDismiss, pressedKeep, pressedStopNow, pressedClose,
                        sessionStarted(byPanel: Bool), sessionFinished(entries: Int), tick }
    public enum Panel: Equatable { case offer(title: String, app: CallApp, hidesIn: Int?), autoStart(title: String, app: CallApp, startsIn: Int),
                                   ended(stopsIn: Int), ready(title: String, detail: String) }
    public enum Effect: Equatable { case lookForMeet, lookForName, start(title: String?, app: CallApp), stop, removeEmptyNote,
                                    record(OfferOutcome) }
    public enum OfferOutcome: String, Sendable { case started, startedAutomatically, dismissed, hidden }
    public var panel: Panel? { get }
    public mutating func handle(_ event: Event, at now: Date, settings: Settings) -> [Effect]
}
```
`tick` comes once a second while anything is pending; all timing is computed from `now`, so tests pass dates and never sleep.

- [ ] Tests, one per rule:
  - bundle IDs: the three §4.1 processes, a Chrome helper, Edge, an unknown app, Shepit itself;
  - under 3 s of microphone gives nothing; at 3 s Teams and Zoom give the offer and `lookForName`;
  - a browser gives `lookForMeet`; no offer until `meetFound(true)`; `meetFound(false)` asks again after 10 s;
  - the title is the name, else "Teams call" / "Zoom call" / "Meet call"; `named` updates an open panel;
  - `callOffer` off: nothing; an app missing from `callApps`: nothing;
  - `hidesIn` counts down from `callOfferSeconds` and the panel goes at 0 with `record(.hidden)`; with 0 there is no countdown and no hiding;
  - `pressedDismiss` → `record(.dismissed)`, no second offer for this call; a new call after the release gets one;
  - `pressedStart` → `start`, `record(.started)`;
  - `callAutoStart`: the `autoStart` panel, `start` and `record(.startedAutomatically)` when it ends; `pressedDismiss` during it → no start;
  - no offer while a session is running or finishing; a call that begins then gets none later either;
  - released for under 3 s, then taken again: same call, nothing shown;
  - released for 3 s during the offer: the panel closes;
  - released for 3 s while its session runs: `ended` panel, then `stop`; `pressedKeep` → no stop and no more `ended` panels for this session; `pressedStopNow` → `stop` at once;
  - a session started by hand during a call belongs to it; a session started by hand with no call is never stopped;
  - a second call app during a call is ignored;
  - `sessionFinished(entries: 0)` for a call's session → `removeEmptyNote` and no `ready` panel; with entries → `ready`;
  - a process that already holds the microphone at launch behaves like one that just took it.
  → FAIL → implement → PASS.
- [ ] Commit `Shepit: call offer decisions`.

### Task 3: GATE — watching the microphone (with the author)

**Files:** Create `Shepit/CallWatch.swift`; add a `call-watch` command to `main.swift`.
**Spec:** §4.1, §5.1.

**Interfaces:** `final class CallWatch { init(onEvent: @escaping @MainActor (CallWatch.Change) -> Void); func start(); func stop() }`, where `Change` is `took(bundleID: String, pid: pid_t)` or `released(pid: pid_t)`. No filtering here: `CallApp.source` decides.

- [ ] **Step 1:** Read the process list and `kAudioProcessPropertyIsRunningInput` as `tools/call-probe/probe.swift` does. Try listeners first (`AudioObjectAddPropertyListenerBlock` on the process list, and on each process object for the input flag). `call-watch` prints every change with a time, and whether it came from a listener or from a once-a-second check that runs beside it.
- [ ] **Step 2 (author):** run `call-watch` during one call in each app. If the listener lines match the check's lines every time, keep listeners only; if any is missed, use the once-a-second check. Record which in the commit message.
- [ ] **Step 3 (author, not blocking):** in the same run, join a Zoom and a Meet meeting by a link and wait on the pre-join screen, for spec §9.
- [ ] Commit `Shepit: watch which app holds the microphone`.

### Task 4: Start without the dialog; remove an empty transcript

**Files:** `Shepit/AppHost+Meetings.swift`; `ShepitCore/MeetingSession.swift` if the entry count is not available yet; tests in `MeetingSessionTests.swift`.
**Spec:** §5.4.

- [ ] `startMeeting(title: String?, app: String?)`: the body of today's `startMeeting` after the name dialog, taking the name and app as given. Today's `startMeeting()` keeps the scan and the dialog and calls it. The mute button is found by `MuteWatch` on its own (it already looks when it has none).
- [ ] The session reports how many entries it wrote (a count on `MeetingRecord`, or from its words). Test: a session with no phrases reports 0.
- [ ] Removing an empty transcript: delete the note file, put back the earlier `last-meeting` value (it is written at Start), skip the statistics row and the name in `meeting-names.json`. Only called for a transcript that belongs to a call (Task 6).
- [ ] Commit `Shepit: start a meeting transcript with a given name`.

### Task 5: The panel

**Files:** Create `Shepit/CallPanel.swift`.
**Spec:** §5.5; visual style §3 and §6; mockup screen 9.

**Interfaces:** `final class CallPanel { func show(_ panel: CallOffer.Panel, onMain: @escaping () -> Void, onOther: @escaping () -> Void); func hide() }`.

- [ ] A borderless non-activating `NSPanel` (`.nonactivatingPanel`, floating level, joins all Spaces, shows over full-screen apps, `becomesKeyOnlyIfNeeded`), top right of the screen with the mouse, with a SwiftUI view: title, one status line, a thin progress bar when a countdown runs, the main button in the accent colour and one plain button. Standard controls and materials; light and dark from the system.
- [ ] Texts and buttons per state exactly as visual style §6. The countdown text and bar are redrawn from the state machine's panel value each second; the panel keeps no timers of its own.
- [ ] A `panel-test` command shows each state for a few seconds, for looking at it without a call.
- [ ] Check by hand: typing in another app goes on while the panel is up; clicking a button doesn't bring Shepit to the front.
- [ ] Commit `Shepit: floating call panel`.

### Task 6: Wiring

**Files:** Create `Shepit/AppHost+Calls.swift`; modify `AppHost.swift` (start the watch at launch, restart on settings change), `AppHost+Meetings.swift` (session start and finish tell the state machine).
**Spec:** §5.2–5.4, §6.

- [ ] `CallWatch` changes → `CallApp.source` → `CallOffer.handle`. A one-second timer sends `tick` only while the state machine has something pending, so nothing runs while no call app holds the microphone.
- [ ] Effects: `lookForMeet` reads window and tab titles of that browser off the main thread (`MeetingApps`, titles only, no deep walk) and answers `meetFound`; `lookForName` runs `MeetingApps.scan(limit: 2)` up to 5 times a second apart, then `MeetingNames.repeating`, and answers `named`; `start` calls `startMeeting(title:app:)`; `stop` is today's Stop; `removeEmptyNote` is Task 4; `record` goes to statistics (Task 7; a no-op until then).
- [ ] Session start (from the menu too) and finish send `sessionStarted` / `sessionFinished`. The `ready` panel replaces the "transcript ready" notice; "Name people" runs Rename speakers….
- [ ] After wake from sleep the watch reads the flags again.
- [ ] Install and try with a call to yourself in one app. Commit `Shepit: offer a transcript when a call starts`.

### Task 7: Settings section, statistics rows, docs

**Files:** Create `Shepit/Settings/CallsSection.swift`; modify `SettingsModel.swift`, `SettingsWindow.swift`, `ShepitCore/Stats.swift`, `StatsDatabase.swift`, `README.md`, `docs/manual-test-checklist.md`; tests in `StatsDatabaseTests.swift`, `SettingsModelTests.swift`.
**Spec:** §5.6, §5.7, §7.

- [ ] Calls section in the current Settings window, laid out as mockup screen 8: the offer switch, "Hide the panel after", automatic start and its seconds, stop seconds, and a switch per app. A line says Meet needs Accessibility when it is missing.
- [ ] `offers` table: time, app, outcome. Insert and read back; existing databases get the table on open; `clear()` empties it; a schema test that it has no text column besides app and outcome. Written only when `collectStats` is on.
- [ ] README: what the panel does, the settings, the known limits of spec §6, and that nothing starts by itself unless automatic start is on. Manual checklist: the spec §7 additions as C1–C10.
- [ ] Commit `Shepit: call settings, offer statistics and docs`.

### Task 8: GATE — real calls and review (with the author)

- [ ] Run C1–C10 with the author on real calls in Teams, Zoom and Meet.
- [ ] Review the whole branch diff against the Review focus list; fix what it finds.
- [ ] Update `docs/future-ideas.md` and "Where things stand" in `CLAUDE.md`. Ask the author before merging into `main`.

---

## Open questions to raise when the task starts (not blockers)

- Task 3: whether Core Audio keeps a process object for an app that has stopped using audio, so a listener can stay on it, or the list has to be re-read each time.
- Task 5: whether the panel should avoid the dictation overlay when `overlayStyle.position` is also top right.
- Task 6: whether Chrome's helper PID can be tied to one browser profile or window; if not, any Meet tab in that browser counts.
