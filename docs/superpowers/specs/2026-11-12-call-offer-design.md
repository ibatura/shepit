# Offer to record when a call starts: design

Date: 2026-11-12, revised the same day (calls are detected by the microphone only)
Status: Approved in discussion; the plan is `../plans/2026-11-12-call-offer.md`
Look of the panels and the settings keys: `2026-11-11-visual-style/visual-style.md` §5.7 (Calls) and §6, `mockups.html` screens 8 and 9.

## 1. Intent

Today a meeting transcript starts only when the author opens the menu and presses Start, so calls get missed. Shepit should notice a call in Teams, Zoom or Google Meet and show a small panel with the call's name and a Start button. When the call ends, it should stop the transcript by itself after a short countdown.

## 2. Decided by the author

2026-11-11:
- A floating panel, not a macOS notification.
- With a name: the panel shows it and Start; one click starts, no name dialog. Without a name: "Zoom call" and the same button.
- The panel hides after `callOfferSeconds` (default 15; 0 keeps it until a button is pressed).
- Automatic start is a setting, off by default: the panel counts down and the transcript starts unless "Don't record" is pressed.
- When the call ends, a panel counts down and the transcript stops unless "Keep recording" is pressed.
- A dismiss applies to this call only.
- Apps: Teams, Zoom, Meet now. Slack and Teams in a browser after their own probe. FaceTime and Telegram if possible, later.

2026-11-12:
- **A call is detected by the microphone only**, the way other note takers do it: a meeting app holding the microphone is a call. Shepit does not read the app's window to decide that.
- So the panel may appear on the pre-join screen, when the app turns the microphone on there (Teams does). This replaces the earlier "only after joining".

## 3. Goals, non-goals, anti-goals

**Goals**
- A call in Teams, Zoom or Meet gives one offer panel within a few seconds.
- One click starts a transcript named after the call.
- The transcript stops by itself when the call ends, unless the author keeps it.
- Watching for calls costs nothing noticeable while no call runs.

**Non-goals**
- Telling the pre-join screen from the call.
- Slack, Teams in a browser, FaceTime, Telegram, Meet in Safari or Firefox (need probes first).
- Calendar names (`docs/future-ideas.md`).
- The main window. Until it exists, the Calls settings get a section in the current Settings window.
- A hotkey for Start and Stop (comes with the window's Hotkeys section).

**Anti-goals**
- Recording that starts without a click while `callAutoStart` is off.
- An offer because of dictation, or because another app or another web page uses the microphone.
- A second offer for a call the author dismissed.
- Stopping a transcript while the call still runs (a headphone switch).
- Anything leaving the Mac.

## 4. Facts

### 4.1 Probes on real calls (`tools/call-probe/probe.swift`)

Core Audio lists the processes that use audio (`kAudioHardwarePropertyProcessObjectList`) and tells for each whether it runs input (`kAudioProcessPropertyIsRunningInput`). No permission is needed.

2026-11-11, calls the author started himself:

| app | process that held the microphone | held for |
|---|---|---|
| Teams | `com.microsoft.teams2.modulehost` | 35 s, one stretch |
| Zoom | `us.zoom.xos` | 36 s, one stretch |
| Meet in Chrome | `com.google.Chrome.helper` | 33 s, one stretch |

- Each call gave exactly one "microphone on" and one "microphone off". The author muted and unmuted about three times in each app: muting in the app does not release the microphone.
- The flag went off within about a second of leaving.

2026-11-12, a scheduled Teams meeting with about 10 s on the pre-join screen:
- The microphone turned on when the pre-join screen opened, about 11 s before joining. So in Teams the offer comes on the pre-join screen.
- Zoom and Meet with a pre-join screen are not probed yet.

Also seen: in Chrome the microphone belongs to a helper process, the same for any web page; the desktop app the author dictates into held the microphone several times; Chrome and Teams play sounds from other processes. None of these may give an offer.

### 4.2 What phase 3 already gives

- `MeetingApps.scan` reads window and tab titles and gives the meeting name and the app. It needs Accessibility, which Shepit has for pasting.
- `MeetingNames.repeating` gives a name for a repeating meeting when the app shows none (Zoom).

## 5. How it works

```
Core Audio: process P holds the microphone for 3 s ──▶ P is Teams, Zoom or a browser?
   Teams, Zoom ──▶ call          browser ──▶ a Meet tab is open? ──▶ call
call ──▶ look up the name ──▶ offer panel ──▶ Start / automatic start ──▶ meeting session
P releases the microphone for 3 s ──▶ call ended ──▶ stop panel ──▶ session stops
```

### 5.1 Watching the microphone (`Shepit/CallWatch.swift`)
- Reads the process list and `IsRunningInput` of each audio process, and reports "app took the microphone" and "app released it". Listeners if they fire for other processes' input; otherwise a poll once a second, as the probe does.
- Bundle ID to app, by prefix (pure logic in `ShepitCore`):

  | prefix | app |
  |---|---|
  | `com.microsoft.teams2` | Teams |
  | `us.zoom.xos` | Zoom |
  | `com.google.Chrome`, `com.microsoft.edgemac`, `com.brave.Browser`, `company.thebrowser.Browser`, `org.chromium.Chromium` | browser |

- Every other process is ignored, Shepit itself included.
- Apps turned off in `callApps` are ignored.

### 5.2 From microphone to call
- The app must hold the microphone for 3 s without a break. This drops short uses.
- **Teams, Zoom:** that is a call.
- **Browser:** one look at the titles of that browser's windows and tabs; it is a call only if one reads as Meet (`MeetingTitle.meet`). If none does, look again every 10 s while the microphone is held. Without Accessibility there are no Meet offers.
- **Name:** one `MeetingApps.scan(limit: 2)` off the main thread, repeated up to 5 times a second apart while the name is missing (as Start does today); else `MeetingNames.repeating`; else none. The panel is shown at once and the name fills in when found. Without a name it says "Teams call", "Zoom call" or "Meet call".

### 5.3 The decisions (`ShepitCore/CallOffer.swift`, pure logic with tests)
A state machine fed with events (app took or released the microphone, Meet found, name found, button pressed, time passed, session started or finished) and the settings. It returns what the panel shows and whether to start or stop a session.

- One call lasts from the 3 s mark until the app has released the microphone for 3 s. A shorter gap (a device switch) is the same call.
- **Offer:** shown once per call, if `callOffer` is on and no meeting transcript is running or finishing.
- **Not this call / Don't record / the offer hides by time:** no more panels for this call. Start from the menu still works.
- **Automatic start** (`callAutoStart`): the same panel with the `callAutoStartSeconds` countdown; when it ends the transcript starts.
- **Shepit starts while a call is already running:** treated as a call that has just begun.
- **A second call app takes the microphone during a call:** ignored until the first call ends.
- **Call ended while a transcript runs that belongs to it:** the stop panel with the `callAutoStopSeconds` countdown; when it ends the session stops as if Stop was pressed. "Keep recording" keeps it, with no more stop panels for this session.
- A transcript belongs to a call when it was started from the panel, or started by hand while that call was running.
- A transcript with no call is never stopped by this feature. The 30-minute silence stop and the 4-hour limit stay as they are.

### 5.4 Starting and ending a session
- `startMeeting` gets a variant that takes the name and the app from the watcher and skips the name dialog, whatever `meetingAskTitle` says. Everything after that is today's code, mute watch included.
- The name is saved to `meeting-names.json` as now.
- If the session can't start (model missing, folder error), the panel closes and the existing alert explains.
- **A transcript that belongs to a call and ends without a single entry is removed:** the note file is deleted, `last-meeting` is not changed, no statistics row. This covers Start on a pre-join screen that was then closed.

### 5.5 The panel (`Shepit/CallPanel.swift`)
A non-activating `NSPanel` with SwiftUI content in the top right corner of the screen with the mouse, above other windows, on all Spaces, also over full-screen apps. It never takes keyboard focus. States, texts and buttons: visual style §6. The "Transcript ready" state replaces today's notice after a meeting; its "Name people" button opens Rename speakers… until the main window exists.

### 5.6 Settings
The keys of visual style §5.7 Calls: `callOffer`, `callOfferSeconds`, `callAutoStart`, `callAutoStartSeconds`, `callAutoStopSeconds`, `callApps`. Validated like the other keys; shown in a Calls section of the current Settings window.

### 5.7 Statistics
One row per offer in `stats.sqlite`: time, app, and how it ended (started by click, started automatically, dismissed, hidden by time). No names. Shown later, in the main window's Statistics.

## 6. Edge cases and known limits

| Situation | Behaviour |
|---|---|
| Pre-join screen | The offer may already appear there (Teams). Start works; if the author doesn't join, the app releases the microphone, the stop panel runs, and the empty note is removed |
| A Teams or Zoom microphone test, or a voice message, longer than 3 s | Gives an offer. Known limit of detecting by the microphone |
| Another web page uses the microphone in Chrome while a Meet tab is open | Gives an offer. Known limit |
| Accessibility not granted | Teams and Zoom offers work, without names. No Meet offers |
| The author joins muted | Works: the app holds the microphone while muted |
| Headphones switched mid-call | A gap under 3 s is the same call |
| Call ends during the offer | The panel closes |
| Call ends during "finishing" or "detecting speakers" | Nothing |
| Mac sleeps mid-call | On wake the state is read again; a released microphone ends the call |

## 7. Testing

- **Unit:** the `CallOffer` state machine with every rule of §5.3 and every row of §6 it decides; bundle ID → app; settings validation; offer rows in the statistics database.
- **Manual checklist additions:** an offer in each app within 5 s; one click starts with the right name; hide by time, and 0; automatic start and "Don't record"; "Not this call" then no second panel; stop panel at the call's end, "Keep recording"; headphone switch mid-call; dictation into another app gives no offer; Start on a pre-join screen that is then closed leaves no note.

## 8. My calls (not confirmed one by one)

- 3 s to count as a call, 3 s of released microphone to count as its end.
- A transcript started by hand during a call is tied to that call and gets the stop panel.
- "Keep recording" silences the stop panel for the rest of the session.
- A call's transcript with no entries is removed.
- The panel shows at once and the name fills in.
- Only Chromium browsers for Meet now; Safari and Firefox after a probe.
- An offer row in statistics.
- The "Transcript ready" panel replaces the current notice.
- Until the main window exists, Calls settings live in the current Settings window.

## 9. Still to probe (not blocking)

- Zoom and Meet joined by a link, with time on the pre-join screen: when the microphone turns on.
- Slack huddles, Teams in a browser, FaceTime, Telegram: which process holds the microphone.
