# Main window, part 1: the shell with Home and Settings

Date: 2026-11-13
Status: Draft, awaiting the author's review
Look and screens: `2026-11-11-visual-style/visual-style.md` ("the style spec") §3–5.1, §5.7, §7 and `mockups.html` screens 1, 8 and 10.
Settings file rules: `2026-10-18-native-app/04-settings.md` §1 (unchanged).

## 1. Intent

Today Shepit has a Settings window and a long menu. This part turns the Settings window into the one main window: a sidebar, a Home section for status and quick controls, and Settings as one of the sections. The menu shrinks to quick actions. The other sections (Meetings, Dictations, People) come in later parts and are placeholders until then.

## 2. Decided by the author

2026-11-11 (style spec §2): one window; the look of macOS System Settings; the menu keeps quick actions; a change saves at once; an Appearance section with a colour choice.

2026-11-13:
- Meetings, Dictations and People are in the sidebar from the start, as placeholders.
- Shepit shows a Dock icon while the window is open.
- The menu drops now what the window already has. The meeting items stay in the menu until the Meetings part.
- Ponytail style and the three end-of-branch reviews apply, as for the call offer.

## 3. Goals, non-goals, anti-goals

**Goals**
- One window with the sidebar of the style spec §4. It replaces the Settings window; there is no second window.
- Home as in mockup 1: dictation status and controls, the three engines, the meeting, the last dictations.
- Settings as a sidebar item with its own list of sections, plus the new Appearance section and the meeting hotkey.
- Dictionary and Statistics become sidebar items, with the content they have today.
- The menu as in §7 below.

**Non-goals**
- The content of Meetings, Dictations and People (their own parts). Meetings will be stored in a local database and changed in the window (name, people, merge, a line given to another person): that is the Meetings part, next after this one (`docs/future-ideas.md`).
- A new look for Dictionary and Statistics, and the new statistics numbers (their own parts).
- `rememberVoices` (the People part).
- A global hotkey for "Copy last dictation" (set aside in `docs/future-ideas.md`).
- An app icon. The Dock shows the generic icon until the author supplies one.

**Anti-goals**
- A setting that can be changed in the window but is not written to `settings.json`, or the other way round.
- The window or its Dock icon appearing on its own. It opens only when the author asks.
- The window slowing dictation: no work for the window while it is closed.
- Quitting dictation by closing the window.

## 4. The window

- The title bar shows the section's name, as System Settings does. Default size 980 × 640, minimum 760 × 480, resizable. It remembers its frame (a new autosave name, so the old Settings frame is not reused), the sidebar section and the Settings section. These three are window state in the app's preferences, not keys of `settings.json`.
- **Opened by:** the menu's Open Shepit (the section it had last), the menu's Settings… or ⌘, (Settings), launching the app again (the section it had last). The first time it opens on Home.
- **Dock:** opening the window makes Shepit a regular app (Dock icon, ⌘Tab, its own menu bar). Closing the window makes it a menu-bar app again. The red button and ⌘W close the window; dictation, the call watch and a running transcript go on.
- **Menu bar while the window is open:** Shepit (Settings… ⌘,, Quit Shepit ⌘Q), Edit (as today), Window (Minimize ⌘M, Close ⌘W). ⌘Q quits the whole app, with today's question during a meeting.
- **Problems banner** (settings file errors, refused writes) stays at the top of the content for every section, with today's rules: controls are read-only while `settings.json` has errors.

### 4.1 Sidebar

| item | in this part |
|---|---|
| *Recording card* | While a meeting transcript runs (recording, finishing, detecting speakers): red dot, "Recording" and the time, the name and the app under it. A click opens Home (the Meetings section later). |
| Home | §5 |
| Meetings | Placeholder: the title and "Meetings come in a later version. Until then they are in the menu." |
| Dictations | Placeholder: the title, "The full history comes in a later version." and Open history file. Built in part 3: `2026-11-16-dictations-dictionary-design.md`. |
| Dictionary | Today's Dictionary section, unchanged. Its new look is in part 3: `2026-11-16-dictations-dictionary-design.md`. |
| People | Placeholder: the title and "Saved voices come in a later version." |
| Statistics | Today's Statistics section, unchanged. Its "Typing speed" link opens Settings → History and privacy. |
| Settings | §6 |

A separator sits above Settings, as in the mockups. Icons are SF Symbols.

### 4.2 Keeping the window current

The window shows live state (status, meeting clock, last dictations). The app keeps one observable model for it and refreshes it when the state changes (the same moments the menu-bar title is refreshed) and once a second while a meeting runs. Nothing is refreshed while the window is closed; opening it refreshes once.

## 5. Home

Four groups, top to bottom (mockup 1).

**Dictation**
- Status: the menu's status line ("Ready — whisper.cpp large-v3", "Recording…", "Loading…", an error).
- A warning row for each of: hotkey problem, Accessibility not granted (button Allow…), microphone access denied (button Open System Settings). Same texts and actions as the menu's ⚠ lines.
- Mode, Language, Microphone: the same keys as in Settings (`mode`, `language`, `microphone`). A change here shows there and the other way round.
- Reload settings and Reload model, with the hint "Changes apply at once".

**Engines: which model does which job**
- Three rows: Dictation ("The text that gets pasted"), Live draft ("The preview in the panel while you speak"), Meetings ("Meeting transcripts").
- Each row is one picker of the downloaded engine and model pairs, written "whisper.cpp · large-v3". A configured pair that is not downloaded is shown, marked "(not downloaded)".
- The Dictation and Live draft pickers are off while a dictation runs; the Meetings picker is off while a transcript runs.
- A link "Download models…" opens Settings → Engines and models.

**Meeting**
- No call: "No call right now" and the hint "Shepit offers a transcript when a call starts" (or "Call offers are off" when `callOffer` is off), with Start transcript as the main button. Start does what the menu's Start does (name dialog when `meetingAskTitle` is on). When the meetings model is missing, the button is off and the row says what to download.
- A call detected and not recorded: the call's name (or "Zoom call") and app, with Start transcript; it starts with that name and no dialog, as the offer panel does. This also works after "Not this call".
- Recording: red dot, name, app, time, phrases waiting, and a red Stop.
- Finishing or detecting speakers: the state as text, no button.

**Last dictations**
- The newest 10 entries of the history file, whatever `historyMenuItems` says: text cut to two lines, the time (with the date when not today), Copy. Copy takes the whole text.
- The history file keeps no app name, so the "· Slack" of the mockup is left out.
- Empty: "No dictations yet", or "History is off (Settings → History and privacy)" when `saveHistory` is off.
- "All dictations" opens the Dictations section.

## 6. Settings

A second column lists the sections; the form is on the right (mockup 8). Order and names:

General, Hotkeys, Engines and models, Dictation, Overlay, Meetings, Calls, History and privacy, Appearance.

Contents are today's, with these changes:
- Dictionary and Statistics moved to the sidebar.
- "Engines & Models" and "History & Privacy" are renamed as above.
- Hotkeys gets the meeting hotkey.
- Appearance is new.

### 6.1 New keys

| key | default | allowed | meaning |
|---|---|---|---|
| `theme` | `"system"` | `"system"`, `"light"`, `"dark"` | Light or dark for the window, the call panels and the dialogs |
| `accentColor` | `"system"` | `"system"`, `"blue"`, `"purple"`, `"pink"`, `"red"`, `"orange"`, `"yellow"`, `"green"`, `"graphite"` | Accent colour; `system` follows macOS |
| `meetingHotkey` | none | as `hotkey`, or `null` | Starts a meeting transcript, or stops the running one |

- **Theme** applies at once to everything Shepit draws with system colours. The dictation overlay keeps its own colours (`overlayStyle`).
- **Accent colour** is shown as a row of colour dots (mockup 8). It colours the selected sidebar item, main buttons, switches, progress bars of the call panels and the charts. It is applied through the per-app accent setting of macOS (`AppleAccentColor` in Shepit's own preferences): tried on 2026-11-13, it colours everything including the sidebar selection. macOS reads it when an app starts, and again when it gets the system notification `AppleAquaColorVariantChanged`, so Shepit sends that after a change and the colour applies at once. The notification is undocumented; if it stops working, the colour applies at the next start, and the row's hint says to restart. SwiftUI's tint is not used: it leaves the sidebar selection in the old colour.
- **Meeting hotkey:** the recorder of the other hotkeys, plus a way to remove the shortcut. Pressing it does what the menu's Start or Stop does at that moment; while a transcript is finishing it only shows "Transcript is finishing". A clash with the dictation or add-word hotkey is shown inline and refused. The key is absent from `settings.json` until set; removing the shortcut removes the key.

`examples/settings.json` and the README table get the three keys.

## 7. The menu

Top to bottom after this part:

1. Status line. While a transcript runs, a second line: "⏺ Recording · name · 12:34" (with "· N phrases waiting" when there are any), or the finishing and detecting texts of today.
2. ⚠ lines as today (settings errors, hotkey, Accessibility, microphone).
3. Open Shepit (⌘O).
4. Start or Stop meeting transcript. Until the Meetings part, also: Copy last meeting transcript, Rename speakers…, Rename speakers in another note…, Open meetings folder.
5. Copy last dictation (off when the history is empty), Recent, Add word….
6. Mode, Language, Dictation engine (today's Engine, renamed).
7. Settings… (⌘,), Quit Shepit (⌘Q).

Gone from the menu: Microphone (Home, Settings → Dictation), Edit dictionary (Dictionary), Statistics (sidebar), Reload config and Reload models (Home), Open history and Clear history… (Settings → History and privacy).

## 8. Structure

- `ShepitCore` (pure, tested): the three keys and their validation; the menu model of §7; the texts Home shows (status, engine pair titles, meeting row, dictation rows) as data built from the same inputs as the menu; the current call's name and app from `CallOffer`.
- `Shepit`: `MainWindow` (the window, Dock policy, menu bar) replaces `SettingsWindow`; a root view with the sidebar; `HomeSection`; placeholders; `AppearanceSection`; the meeting hotkey in `HotkeyCenter`; the observable window model fed by `AppHost`.
- The settings sections keep their files and the `SettingsModel` binding (one key per control). Home's controls use the same bindings.

## 9. Tests and manual checks

Unit tests: the new keys (defaults, allowed values, a file without them loads, unknown keys kept, `meetingHotkey` set and removed); the menu model; Home's texts for each state; the meeting hotkey in `HotkeyCenter` (registered, clash refused, removed); every settings key still belongs to exactly one Settings section.

Manual (added to `docs/manual-test-checklist.md` as W1–W10):
- W1 Open from the menu, by ⌘, and by launching again; the right section each time; frame and sections remembered after a restart of Shepit.
- W2 Dock icon and ⌘Tab only while the window is open; closing keeps dictation working.
- W3 Dictate while the window is open and in front: the text goes to the app that was in front before, as today, or the limit is written down.
- W4 Home status follows a dictation (recording, transcribing, ready) and a model reload.
- W5 Mode, Language, Microphone changed on Home show in Settings and in `settings.json`; a hand edit of the file shows on Home within a few seconds.
- W6 Engines pickers change the engine for each job; off while that job runs.
- W7 Meeting group through a real call: detected call with its name, Start, the recording card, Stop.
- W8 Last dictations: a new dictation appears; Copy; a long text is cut.
- W9 Theme and accent colour: window, call panel (`Shepit panel-test`), dialogs.
- W10 Meeting hotkey: start, stop, clash with the dictation hotkey, remove.

## 10. My calls (not confirmed one by one)

- ⌘Q quits the whole app even though the window looks like a normal app; closing the window is ⌘W.
- The window opens on the section it had last, except through Settings….
- The recording card and "All dictations" lead to Home and to the Dictations placeholder until their parts exist.
- The Dictations placeholder has Open history file, because the menu loses it.
- The Meeting group knows about a detected call, so "No call right now" is not shown during one.
- The menu keeps Add word, Mode, Language and Dictation engine during a meeting (the mockup's second menu leaves them out): dictation still works then.
- The meeting clock line in the menu changes to "⏺ Recording · name · time".
- "Copy last dictation" has no global hotkey.
- Last dictations show no app name.
- No app icon in this part.
- `theme` covers dialogs and call panels too, not only the window.
- A meeting hotkey that clashes is refused, not just warned about. The dictation and add-word recorders refuse the meeting hotkey's keys the same way.
- Mode and Language on Home are off while a dictation runs, and Microphone also while a transcript runs, as the menu items they replace were.

## 11. Open questions for the plan

- Whether a dictation started while the window is the front app can be pasted anywhere sensible (W3). Today's Settings window has the same case.
