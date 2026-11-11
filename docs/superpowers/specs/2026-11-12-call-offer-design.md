# Offer to record when a call starts: design

Date: 2026-11-12
Status: Draft, awaiting review
Look of the panels and the settings keys: `2026-11-11-visual-style/visual-style.md` §5.7 (Calls) and §6, `mockups.html` screens 8 and 9.

## 1. Intent

Today a meeting transcript starts only when the author opens the menu and presses Start, so calls get missed. Shepit should notice a call in Teams, Zoom or Google Meet and show a small panel with the call's name and a Start button. When the call ends, it should stop the transcript by itself after a short countdown.

## 2. Decided by the author (2026-11-11)

- A floating panel, not a macOS notification.
- The offer appears once the author has joined the call, not on the pre-join screen.
- With a name: the panel shows it and Start; one click starts, no name dialog. Without a name: "Zoom call" and the same button.
- The panel hides after `callOfferSeconds` (default 15; 0 keeps it until a button is pressed).
- Automatic start is a setting, off by default: the panel counts down and the transcript starts unless "Don't record" is pressed.
- When the call ends, a panel counts down and the transcript stops unless "Keep recording" is pressed.
- A dismiss applies to this call only.
- Apps: Teams, Zoom, Meet now. Slack and Teams in a browser after their own probe. FaceTime and Telegram if possible, later.

## 3. Goals, non-goals, anti-goals

**Goals**
- A call in Teams, Zoom or Meet gives one offer panel within a few seconds of joining.
- One click starts a transcript named after the call.
- The transcript stops by itself when the call ends, unless the author keeps it.
- Watching for calls costs nothing noticeable while no call runs.

**Non-goals**
- Slack, Teams in a browser, FaceTime, Telegram (need probes first).
- Calendar names (`docs/future-ideas.md`).
- The main window. Until it exists, the Calls settings get a section in the current Settings window.
- A hotkey for Start and Stop (comes with the window's Hotkeys section).

**Anti-goals**
- Recording that starts without a click while `callAutoStart` is off.
- An offer for something that is not a call (a voice message, a microphone test, dictation in another app).
- A second offer for a call the author dismissed.
- Stopping a transcript while the call still runs (a headphone switch, a short network drop).
- Anything leaving the Mac.

## 4. Facts

### 4.1 Probe on real calls (2026-11-11, `tools/call-probe/probe.swift`)

Core Audio lists the processes that use audio (`kAudioHardwarePropertyProcessObjectList`) and tells for each whether it runs input (`kAudioProcessPropertyIsRunningInput`). No permission is needed.

| app | process that held the microphone | held for |
|---|---|---|
| Teams | `com.microsoft.teams2.modulehost` | 35 s, one stretch |
| Zoom | `us.zoom.xos` | 36 s, one stretch |
| Meet in Chrome | `com.google.Chrome.helper` | 33 s, one stretch |

- Each call gave exactly one "microphone on" and one "microphone off". The author muted and unmuted about three times in each app, a few seconds apart: muting in the app does not release the microphone.
- The flag went off within about a second of leaving.
- The author started these calls himself, so there was no pre-join screen. What the flag does on a pre-join screen (joining someone else's meeting by a link) is not known yet.
- During the Teams call `systemsoundserverd` played three short sounds a few seconds apart, most likely the mute sounds. Not used: it is not tied to the app.
- In Chrome the microphone belongs to a helper process, the same for any web page that uses it. The browser has to be found from the helper, and the page checked.
- Teams plays its sounds from another process (`com.microsoft.teams2.helper`); only the microphone flag matters.

### 4.2 What phase 3 already gives

- `MeetingApps.scan` finds the call window by its mute button (`inCall`), the meeting name and the app. It walks the Accessibility tree for up to 2 s, too heavy to run all the time.
- `MeetingNames.repeating` gives a name for a repeating meeting when the app shows none (Zoom).
- `MuteWatch` already notices when the mute button disappears.

## 5. How it works

```
Core Audio: process P starts input ──▶ is P a call app? ──▶ candidate
candidate ──▶ Accessibility scan every 2 s ──▶ joined? ──▶ call(app, name)
call ──▶ offer panel ──▶ Start / automatic start ──▶ meeting session
P stops input for 3 s ──▶ call ended ──▶ stop panel ──▶ session stops
```

### 5.1 Watching the microphone (`Shepit/CallWatch.swift`)
- Listens to the process list and to `IsRunningInput` of each audio process. Event driven; if listeners prove unreliable, a 2 s poll of the same properties (the probe polls every second with no visible cost).
- A process is a candidate when its bundle ID starts with a known prefix:

  | prefix | app |
  |---|---|
  | `com.microsoft.teams2` | Teams |
  | `us.zoom.xos` | Zoom |
  | a browser's bundle ID, with or without `.helper` (Chrome, Edge, Brave, Arc, Safari's web content) | browser: Meet if a Meet page is found |

- Shepit's own microphone use, dictation, and every other app are ignored.
- Apps turned off in `callApps` are ignored.

### 5.2 Confirming the call
- While a candidate holds the microphone, `MeetingApps.scan(limit: 2)` runs off the main thread every 2 s for the first minute, then every 10 s. It stops when the call is confirmed or the microphone is released.
- **Joined** means: the scan finds that app's call window with a control to leave the call ("Leave", "Hang up", "End", "Leave call", «Покинути дзвінок»). The pre-join screen has a mute button too, but no way to leave a call. The exact labels are taken from a real call (§9, gate).
- For a browser, the window must show a Meet page (`MeetingTitle.meet`), so another site using the microphone gives no offer.
- The name is `scan.detected.title`, else `MeetingNames.repeating`, else none. Without a name the panel says "Teams call", "Zoom call" or "Meet call".

### 5.3 The decisions (`ShepitCore/CallOffer.swift`, pure logic with tests)
A small state machine fed with events (microphone on/off for an app, joined, button pressed, timer, session started/finished) and the settings. It returns what to show and what to start or stop.

- One call lasts from "joined" until the app has released the microphone for 3 s. A shorter gap (a device switch) is the same call.
- **Offer:** shown once per call, when joined, if `callOffer` is on and no meeting transcript is running or finishing.
- **Not this call / Don't record / the offer hides by time:** no more panels for this call. Start from the menu still works.
- **Automatic start** (`callAutoStart`): the same panel with the `callAutoStartSeconds` countdown; when it ends the transcript starts.
- **Shepit starts while a call is already running:** treated as a call that has just been joined.
- **A second call app takes the microphone during a call:** ignored until the first call ends.
- **Call ended while a transcript runs that belongs to this call:** the stop panel with the `callAutoStopSeconds` countdown; when it ends the session stops as if Stop was pressed. "Keep recording" keeps it, with no more stop panels for this session.
- A transcript belongs to a call when it was started from the panel, or started by hand while that call was running.
- A transcript with no call (started by hand for something else) is never stopped by this feature. The 30-minute silence stop and the 4-hour limit stay as they are.

### 5.4 Starting from the panel
- `startMeeting` gets a variant that takes the name, the app and the mute button from the watcher and skips the name dialog, whatever `meetingAskTitle` says. Everything after that is today's code.
- The name is saved to `meeting-names.json` as now.
- If the session can't start (model missing, folder error), the panel closes and the existing alert explains.

### 5.5 The panel (`Shepit/CallPanel.swift`)
A non-activating `NSPanel` with SwiftUI content in the top right corner of the screen with the mouse, above other windows, on all Spaces, also over full-screen apps. It never takes keyboard focus. States, texts and buttons: visual style §6. The "Transcript ready" state replaces today's notice after a meeting; its "Name people" button opens Rename speakers… until the main window exists.

### 5.6 Settings
The keys of visual style §5.7 Calls: `callOffer`, `callOfferSeconds`, `callAutoStart`, `callAutoStartSeconds`, `callAutoStopSeconds`, `callApps`. Validated like the other keys; shown in a Calls section of the current Settings window.

### 5.7 Statistics
One row per offer in `stats.sqlite`: time, app, and how it ended (started by click, started automatically, dismissed, hidden by time). No names.

## 6. Edge cases

| Situation | Behaviour |
|---|---|
| Accessibility not granted | No confirmation is possible: no offers. Settings → Calls says why |
| Microphone taken, call window never found (a Teams voice message, a test call screen) | No offer; scanning slows to every 10 s and stops when the microphone is released |
| The author joins muted | Works: the app holds the microphone while muted (§4.1) |
| Headphones switched mid-call | A gap under 3 s is the same call |
| Call ends during the offer | The panel closes |
| Call ends during "finishing" or "detecting speakers" | Nothing |
| Mac sleeps mid-call | On wake the state is read again; a released microphone ends the call |
| Two browsers, or a Meet tab in the background | The window showing Meet decides; a background tab has no call controls and gives no offer until shown |

## 7. Testing

- **Unit:** the `CallOffer` state machine with every row of §5.3 and §6; bundle ID → app; settings validation; leave-control labels as a pure function over sample labels.
- **Manual checklist additions:** an offer in each app within 5 s of joining; none on the pre-join screen; one click starts with the right name; hide by time, and 0; automatic start and "Don't record"; "Not this call" then no second panel; stop panel at the call's end, "Keep recording"; headphone switch mid-call; a Teams voice message gives no offer; another site using the microphone in Chrome gives no offer.

## 8. My calls (not confirmed one by one)

- "Joined" is read from a leave control in the call window.
- A 3 s gap rule for the end of a call.
- A transcript started by hand during a call is tied to that call and gets the stop panel.
- "Keep recording" silences the stop panel for the rest of the session.
- An offer row in statistics.
- The "Transcript ready" panel replaces the current notice.
- Until the main window exists, Calls settings live in the current Settings window.

## 9. To check before the plan (gate, with the author)

1. Joining an existing meeting by a link in each app, with a few seconds on the pre-join screen: when the microphone flag turns on, and which buttons the Accessibility tree shows before and after joining (labels only). This fixes the "joined" rule. The labels are read by a diagnostic command inside Shepit, which already has Accessibility; a script in the terminal would need its own permission.
2. How long after leaving each app releases the microphone when the meeting window stays open (Teams keeps a "call ended" screen).
3. Whether Core Audio property listeners fire for other processes' input, or a poll is needed.
