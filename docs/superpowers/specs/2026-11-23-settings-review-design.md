# Main window, part 8: Settings review

Date: 2026-11-23
Status: Approved by the author on 2026-11-23. Every decision in §2 is the author's (2026-11-23).
Build order: item 10 in `docs/future-ideas.md` ("Planned, in this order"), next after back and forward (the author, 2026-11-23). Branch `settings-review`. The version is agreed with the author before the pull request (0.4.0 proposed).
Builds on: `2026-11-13-window-shell-design.md` (Settings, Home, the 🎙 menu), `2026-11-12-call-offer-design.md` (the offer panel, automatic start and stop), `2026-11-17-statistics-design.md` (the period menu), and the author's remarks under "Every setting reviewed" in `docs/future-ideas.md` (2026-11-16, 2026-11-19, 2026-11-22).

## 1. Intent

Settings grew page by page, and some things ended up where nobody looks for them: the dictation language in General, the detection models in Meetings, the dictation panel on a page of its own, meetings and calls on two pages that don't refer to each other. Home and the 🎙 menu repeat settings that live elsewhere. The calls' switches don't say what on means, and there is one automatic start for all apps.

This part puts every setting where it is looked for, makes each page say what it is for, turns Home into a status page and the 🎙 menu into groups, gives each call app its own behaviour with rules by meeting name, and makes the period menu one control in every section.

## 2. Decided by the author (2026-11-23)

Asked with drawings, in three rounds; "recommended" marks where the author took my proposal.

**The part**
- One branch and one release, not three: "not that much work". Built in this order inside the branch: Settings pages, Home and the 🎙 menu; then calls per app and rules; then the same controls.
- The plan has a task that checks every key of `settings.json` is still read by something, and drops those that aren't.

**Settings pages** (recommended)
- Overlay goes into Dictation as its "Panel" part, its look included; the Overlay page goes. The dictation language moves from General to Dictation.
- One Meetings page with Calls, Notes and Transcript parts; the Calls page goes.
- Every model is in Engines and models, the voice and speaker detection models included, each saying what it is for and whether anything uses it. Meetings only says what it needs, with a link.
- History and privacy is split into parts named after what they keep: Dictations, Statistics, Voices, Databases.
- Every page starts with a line on what it is for.
- Reload settings goes to General → Files, next to Open settings file. Reload model goes: a change of engine already loads the new one.

**Home** (recommended, with the author's change)
- Home is a status page: Needs attention (only when something is wrong), Dictation, Meeting, Recent dictations, Recent meetings.
- Recent meetings (the author): the last few, as many as the dictations, each with its name, app and length; a click opens it in Meetings.
- Mode, Language, Microphone, the engine pickers, Download models… and the two Reload buttons leave Home.

**The 🎙 menu** (recommended, with the author's change)
- Groups, each led by its state as a line that can't be clicked: ⚠ problems, Meeting, Dictation, Shepit.
- Mode and Dictation engine leave the menu.
- Both languages stay (the author): "Meeting language ▸" in the meeting group and "Dictation language ▸" in the dictation group.

**Calls**
- Teams, Zoom and Google Meet each get Auto, Offer or Off (the author's words): start a transcript on its own, offer one in the panel, or do nothing.
- They are picked with macOS's segmented control, three joined buttons in each app's row. The author chose it over a pop-up menu.
- Rules by meeting name: each rule is an app, a way to match, a text and what to do (Auto, Offer or Off). A rule can be written for any of the three apps; Zoom gives no name today, but may later.
- A rule matches when the call's name contains its text, or is it exactly; contains is the default. Case is ignored.
- The app's choice comes first: for an app set to Off, its rules are ignored. For Auto or Offer, the first rule in the list that matches decides.
- No name found: the app's choice decides.
- The delays (start after, hide the panel after, stop after the call ends) stay one setting each for all apps.
- Old settings files keep working: while the new keys are missing, the old ones are read. Shepit doesn't rewrite the file on its own.
- The "Call ended" and "Transcript ready" panels don't show for an app set to Off.
- Why the author saw no offer for Google Meet in Chrome is looked into in this branch, on a real Meet call (§8).

**The same controls** (recommended)
- The period menu is one control in Dictations, Statistics and People: on the right of the section's top bar, with the same periods and Custom… in all three.

**Voice numbers** (recommended)
- The threshold, margin, samples, microphone minutes and 30 days stay fixed, not settings.

## 3. Goals, non-goals, anti-goals

- **Goals:** every setting in one place, where it is looked for; each page and each call choice says what it does; Home and the 🎙 menu hold what is used often and what needs attention; each call app behaves as the author set it, with rules for meetings that repeat.
- **Non-goals:** a new look for the dictation panel itself (its own idea under "New ideas"); naming Zoom calls (put off, "Call offer: left open"); calendars; settings for the voice numbers; a search in Settings.
- **Anti-goals:** a setting nobody asked for; a key in `settings.json` with no page; any change to the author's own `settings.json` by code or tests; Shepit rewriting the settings file without a change in the window.

## 4. Settings pages

Seven pages, in this order. Each starts with a line in secondary text. What moves is marked "from …".

- **General**: "Shepit itself: starting at login, sounds, and its files." Launch at login, Sounds; Files: Open settings file, Open data folder, Reload settings (from Home).
- **Hotkeys**: "The keys that start dictation and meetings." As today: Mode, Dictation hotkey, Cancel key, Add-word hotkey, Meeting transcript hotkey.
- **Dictation**: "How you dictate: language, microphone, pasting, and the panel shown while you speak."
  - Dictation: Language (from General), Microphone, Max recording length.
  - Text: Style prompt, Paste into the original app, Restore clipboard.
  - Panel (from Overlay): Show panel, Live draft, Preview.
  - Panel look (from Overlay → Look, Meter): position, width, font size, opacity, colours; meter, bars, meter colour.
  - Panel texts and timing (from Overlay → Texts, Timing): the three titles, timer; final text, notices.
- **Meetings**: "Meeting transcripts: when they start, where the notes go, how they are transcribed."
  - Calls (from Calls): Teams, Zoom, Google Meet, each Auto · Offer · Off; Rules by meeting name; Start after (Auto), Hide the panel after (Offer), Stop after the call ends; the Accessibility warning for Meet, as today.
  - Notes: Folder, File name, Ask for the meeting name, Open meetings folder.
  - Transcript: Your name, Language, Block dictation during a meeting (from its own part), Recognition, with "Voice and speaker detection: installed" or what is missing, and a link to Engines and models.
- **Engines and models**: "Which engine does each job, and every model on this Mac."
  - Jobs: Dictation, Live draft, Meetings, each with its engine, model and a line on what the job is; then Voice detection and Speaker detection, each with its one model in a menu, so it shows as the chosen one (the author, 2026-11-23: a second model would go there). One line under each name, a warning in its place when the model is missing.
  - Unload models when idle: a menu (Never, after 5, 15, 30 minutes, 1, 2, 4, 8 hours), not a stepper (the author, 2026-11-23).
  - The models on this Mac, by kind: Speech recognition models, Voice detection models, Speaker detection models. Each says what it is for (speed, accuracy, memory, languages, from "What each engine is for"), what uses it, "Not used: can be deleted" when nothing does, and Download, Cancel or Delete…, as today.
- **History and privacy**: "What Shepit keeps on this Mac, for how long, and how to clear it."
  - Dictations (today's History): Save history, Keep for, Recent menu items, Keep failed audio, Clear history….
  - Statistics: Collect statistics, Typing speed, Clear statistics….
  - Voices: the pointer to People, as today.
  - Databases: the folder.
- **Appearance**: "How Shepit's window looks." Theme, Accent colour.

A page remembered from before (Overlay, Calls) opens as the page its settings went to (Dictation, Meetings). The panel's look stays in Dictation, so Appearance keeps the window only.

## 5. Home

Top to bottom:

- **Needs attention**, only while something is wrong, each line with one button: the hotkey problem, Accessibility (Allow…), microphone access (Open System Settings), and a model a job uses that isn't downloaded (Download…, which opens Engines and models). The first three are today's warnings; the missing model is new.
- **Dictation:** the status line ("Ready — whisper.cpp large-v3-turbo").
- **Meeting:** as today: no call, a call found with Start transcript, recording with Stop, finishing.
- **Recent dictations:** the last 10, Copy, All dictations, as today.
- **Recent meetings:** the last 10 listed meetings, each with its name ("Teams call" when it has none), app and length; a click opens it in Meetings; All meetings opens the section. Nothing when there are none.

## 6. The 🎙 menu

Top to bottom, groups split by separators:

1. ⚠ lines, as today, each opening its fix.
2. Meeting: its state as a line that can't be clicked (as today), Start or Stop meeting transcript, Meeting language ▸.
3. Dictation: "Dictation: Ready — whisper.cpp large-v3-turbo" (a line that can't be clicked), Copy last dictation, Recent dictations ▸, Add word to dictionary…, Dictation language ▸.
4. Shepit: Open Shepit ⌘O, Settings… ⌘,, About Shepit, Quit Shepit ⌘Q.

Mode ▸ and Dictation engine ▸ leave. While a job runs, its language is greyed out, as Language is today.

## 7. Calls

### 7.1 What happens when a call starts

1. An app holds the microphone for 3 s (as today). An app set to Off is not watched: its call counts for nothing, as an app with its switch off today. A transcript started by hand during it is an ordinary transcript, with no "Call ended" countdown and no "Transcript ready" panel.
2. For Auto or Offer, Shepit looks for the call's name (as today), and decides when the answer comes: the first rule of that app that matches the name; if none, the app's choice.
3. Auto shows the panel with its countdown and starts on its own; Offer shows the offer panel; a rule's Off shows nothing. Home still shows the call with Start, as it does today when offers are off.

Today the panel shows first and the name fills in when found. With rules the choice waits for the name, which took about a second on the author's calls (M20: 1.2 s). If no answer comes within 5 s, the app's choice decides with no name.

### 7.2 The settings file

- `callModes`: an object from app to choice, `{"Teams": "offer", "Zoom": "off", "Meet": "auto"}`. The app keys are `CallApp` raw values. An app missing from it is Off.
- `callRules`: a list of `{"app": "Teams", "match": "contains", "text": "Daily scrum", "then": "auto"}`, in order. `match` is `contains` or `is`; `then` is `auto`, `offer` or `off`. An empty text matches nothing.
- While `callModes` is missing, it is read from the old keys: an app in `callApps` gets `auto` with `callAutoStart`, else `offer` with `callOffer`, else `off`; an app not in `callApps` gets `off`. The first change on the Calls part writes `callModes` and removes the three old keys.
- Validation, as for every key: an unknown app, choice or match is an error shown in the window, and the controls go read-only until the file is fixed.

### 7.3 The controls

- Each app: its name and the segmented control Auto · Offer · Off, with a hint on each choice: "Starts a transcript on its own after N s", "Shows a panel with the call's name and a Start button", "Does nothing".
- Rules by meeting name: a list with + and − below it, as macOS lists have. Each row: app (pop-up), match (pop-up: contains, is), text (field), then (pop-up: Auto, Offer, Off). Rows move by dragging; the first match wins. A rule of an app set to Off is greyed, with "Ignored: Teams is Off" as its hint.
- The delays as today, each saying which choice it is for.

## 8. Google Meet in Chrome

On 2026-11-17 the author saw no offer during a Meet call in Chrome. `stats.sqlite` has a Meet offer at 11:01 that day and two on 2026-11-20, each recorded as hidden: the call was found and the offer timed out with no click. So the panel was shown somewhere the author didn't see, or not drawn. The panel goes to the top right of the screen with the mouse, above full-screen apps on every Space.

A task of the plan, with the author on a real Meet call in Chrome: `Shepit call-watch` and Shepit's log while the offer should show; then the fix; then the check again on a call. If the cause is outside Shepit, the finding goes to "Call offer: left open".

## 9. The period menu

Today Dictations has "Show: Last month" on the left of its top bar, Statistics an unlabelled menu with Custom… on the right, and People its own on the right. All three get Statistics' menu, on the right of the top bar: the period's name as its title, the presets, Custom…. Dictations and People gain Custom…, which `StatsPeriod` already covers. Each section still remembers its own period.

Then every section is looked through for other controls that differ (top bars, buttons at the bottom, empty states, questions and alerts); each difference found is fixed or written under "left open".

## 10. Structure

- **ShepitCore**
  - `Settings`: `callModes` and `callRules` with their validation; `callMode(for:)` reads the old keys while `callModes` is missing; the old three keys stay readable only for that.
  - `CallRules` (new, pure): the choice for an app and a name, from `callModes` and `callRules`.
  - `CallOffer`: an app set to Off is not watched (in place of `callApps`); a call waits for its name before the choice (a `naming` phase, 5 s at most); then Auto, Offer or nothing.
  - `HomeModel`: needs attention, dictation, meeting, recent dictations and recent meetings; the pickers, Mode, Language and Microphone go, with the job titles and hints they kept apart from `EnginesSection`.
  - `MenuModel`: the four groups and the two languages; Mode and Dictation engine go.
  - `AppSnapshot` and `Lookups` get the recent meetings, read with the other lookups.
- **The app**
  - `SettingsModel.Section` loses `overlay` and `calls`; a remembered "Overlay" or "Calls" maps to Dictation or Meetings.
  - `OverlaySection`'s parts move into `DictationSection`; `CallsSection` becomes the Calls part of `MeetingsSection`; the Models part of `MeetingsSection` moves to `EnginesSection`, which lists every model.
  - Every page's line; History and privacy's parts renamed.
  - `PeriodMenu` moves from `StatisticsView` to `Controls.swift`, and the three sections use it.
  - `AppAction.reloadModels` goes if nothing else uses it; Reload settings moves to General.
- **Docs:** README (Settings, Home, the menu, calls), `examples/settings.json` (`meetingHotkey`, `callModes`, `callRules`), the manual checks.

## 11. Tests and manual checks

- **Tests:** `CallRules` (contains and is, case, the first match, an app set to Off ignores its rules, no name, an empty text); `Settings` (the new keys, validation, the old keys read while the new are missing, the first change writing the new and removing the old); `CallOffer` (an app set to Off isn't watched, the choice waits for the name and for 5 s at most, a rule's Off shows nothing, a rule's Auto starts); `HomeModel` (needs attention with a missing model, recent meetings); `MenuModel` (the groups, both languages); every key is on exactly one page (the old test checks "at most one"); every key is read by something.
- **Manual checks** (numbered in the checklist when the plan is written): each page with its line and no setting left behind; a remembered Overlay page opens Dictation; Home with a missing model and with recent meetings; the 🎙 menu's groups and both languages; a Teams call with Teams set to Offer, then a rule Off for its name, then Auto; Zoom set to Off during a Zoom call; an old `settings.json` copy (in a test folder, not the author's) read without a change; the period menu in the three sections; the Meet panel in Chrome (§8).

## 12. My calls (not confirmed one by one)

- The choice waits for the call's name 5 s at most (§7.1).
- An app set to Off isn't watched at all, so Home doesn't show its call either; a rule's Off still lets Home show the call with Start (§7.1).
- The keys `callModes` and `callRules`, and the first change on the Calls part removing `callOffer`, `callAutoStart` and `callApps` (§7.2).
- Recent meetings shows 10, as Recent dictations does (§5).
- Dictations and People gain Custom… with the shared period menu (§9).
- A remembered Overlay or Calls page opens Dictation or Meetings (§4).
- A rule of an app set to Off is greyed, with a hint saying why (§7.3).

## 13. Settings today (2026-11-23)

- **General:** Launch at login, Sounds, Language (dictation); Files: Open settings file, Open data folder.
- **Hotkeys:** Mode, Dictation hotkey, Cancel key, Add-word hotkey, Meeting transcript hotkey.
- **Engines and models:** the engine and model for Dictation, Live draft and Meetings; Unload when idle; Models on this Mac (engines only).
- **Dictation:** Microphone, Style prompt, Paste into the original app, Restore clipboard, Max recording length.
- **Overlay:** Show panel, Live draft, Preview; Look (position, width, font size, opacity, colours); Texts (three titles, timer); Meter (meter, bars, colour); Timing (final text, notices).
- **Meetings:** Notes (folder, file name, ask for the meeting name, open the folder); Dictation (block dictation during a meeting); Transcript (your name, language, recognition); Models (voice detection, speaker detection).
- **Calls:** Offer (offer, hide the panel after); Automatic start and stop (start automatically, start after, stop after the call ends); Apps (Teams, Zoom, Google Meet switches).
- **History and privacy:** History (save history, keep days, Recent menu items, keep failed audio, Clear history…); Statistics (collect, typing speed, Clear statistics…); Voices (a pointer to People); Databases (folder).
- **Appearance:** Theme, Accent colour.
- **Home:** Status, Mode, Language, Microphone, Reload settings, Reload model; Engines (three pickers, Download models…); Meeting; Last dictations.
- **The 🎙 menu:** the meeting's state, Start or Stop meeting transcript; Open Shepit; Copy last dictation, Recent ▸, Add word…, Mode ▸, Language ▸, Dictation engine ▸; About Shepit, Settings…, Quit Shepit.
- In `settings.json` but on no page: `serverPort`, `previewModel`; the check of every key (§2) starts with them.
- Found in the docs (the author asked to go through every idea, 2026-11-23): besides the review's own item, automatic start per app and rules by name, only "What each engine is for" (in §4) and three points of "Window shell: left open" that this part settles (the job titles differ between Home and Engines and models, `engines` is written in two places, Home greys out controls Settings keeps editable). No other idea asks for a new switch.
