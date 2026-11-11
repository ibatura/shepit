# Shepit visual style: main window, panels, menu

Date: 2026-11-11
Status: Draft, awaiting review
Mockups: `mockups.html` in this folder (open it in a browser; made-up names and texts).

## 1. Intent

The phase 3 interface works, but every action is a menu item followed by a small dialog. The author wants a program to work in: one window with meetings, dictations, dictionary, statistics and settings, and a menu that keeps only quick actions. This spec fixes how all of it looks and what goes where. The features behind the screens get their own specs and plans:

1. Offer to record when a call starts (floating panels, §6).
2. The main window (§4–5).

## 2. Decided by the author (2026-11-11)

- The look is restrained, like macOS System Settings.
- One window. The current Settings window grows into it; there is no second window.
- The menu keeps quick actions. Everything else is in the window.
- The call running now is visible in the window, with Stop there.
- People of a meeting are named in the window. Two people can be merged into one. A single line can be given to another person.
- The transcript is read only in the window. Editing happens in Obsidian.
- No search across transcripts.
- Import takes names only.
- Voice prints are a setting, off by default. Saved voices can be seen and deleted.
- A meeting whose note was moved stays in the list, marked "note not found", with a way to point at the file.
- The offer panel hides after a number of seconds, set in Settings; 0 keeps it until a button is pressed.
- Settings get an Appearance section with a colour choice.

## 3. Principles

- **Native first.** SwiftUI with standard controls: `NavigationSplitView`, grouped `Form`, `Toggle`, `Picker`, SF Symbols, system fonts and materials. No custom-drawn controls where a standard one exists. Light and dark come from the system.
- **One accent colour**, used for the selected sidebar item, the main button of a view and progress bars. Red is kept for "recording".
- **A change saves at once.** No Save buttons, as in System Settings. Settings still live in `settings.json`; the window reads and writes that file (`2026-10-18-native-app/04-settings.md` §1 is unchanged).
- **One main button per view.**
- **Rows in groups**, label on the left, control on the right, one line of hint under the label where needed.
- **English labels**, sentence case.

## 4. The window

A sidebar on the left, content on the right. Default size about 980 × 640, resizable, remembers its size and section. Opened from the menu (Open Shepit, ⌘O), by ⌘, (opens on Settings), or by launching the app again. Shepit stays a menu-bar app; whether it shows a Dock icon while the window is open is left to the builder.

Sidebar, top to bottom:

| item | what |
|---|---|
| *Recording card* | Only while a meeting transcript runs: red dot, time, name, app. Click opens the live meeting. |
| Home | Status and quick controls |
| Meetings | List and one meeting |
| Dictations | History |
| Dictionary | Terms, replace rules, drop phrases |
| People | Saved voices |
| Statistics | As today, restyled |
| Settings | All settings sections |

## 5. Sections

### 5.1 Home
- **Dictation group:** status line (as the menu's first line today), Mode, Language, Microphone, and the buttons Reload settings and Reload model.
- **Engines group:** one row per job, each with one picker "engine · model" and a hint saying what the job is: Dictation (the text that gets pasted), Live draft (the preview in the panel while you speak), Meetings (meeting transcripts).
- **Meeting group:** "No call right now" with Start transcript, or the running call with Stop.
- **Last dictations:** the newest 10, each with Copy, and a button to the Dictations section.

### 5.2 Meetings
Two columns: the list (grouped by week; name, day and time, duration, app) and the chosen meeting.

A finished meeting shows:
- Name (editable), app, date, duration. A new name is written to the database and the note's front matter, and the note file is renamed too: the `meetingFileName` template is filled again with the new name, in the same folder, with ` (2)` added if that name is taken. A missing note changes only the database.
- Buttons: Copy, Open note, Import names….
- **People:** one row per person with a colour, a name field, the share of words, and "Merge into" with the other people. Typing a name renames that person in the note. Merge gives all lines of one person to another.
- **Transcript**, read only. Clicking a line opens a small list "Give this line to" with the meeting's people.
- A meeting whose note is missing shows "note not found" in the list, and "Locate note…" and "Remove from list" instead of the transcript.

The running meeting is the first item of the list, with a red dot. It shows time, words, phrases waiting, the microphone's mute state, the live transcript, and Stop. People appear after Stop.

All changes to the note keep the phase 3 rule: only header lines are rewritten, via temp file + rename.

### 5.3 Dictations
The history by day: text, time, app, word count, Copy. The section shows the whole kept history, loaded as the list scrolls. A long text shows its first two lines and "…"; a click opens the whole text in place. Copy always takes the whole text. At the bottom: how long history is kept, Open history file, Clear history….

### 5.4 Dictionary
Terms as chips, replace rules as a two-column list, drop phrases as chips, and an Add word button (the same dialog as ⌃⌥D).

### 5.5 People
The "Remember voices" switch with its explanation, the list of saved voices (name, number of meetings, last seen, Delete), and "Delete all voices…".

### 5.6 Statistics
The same tiles and charts as today (`2026-10-18-native-app/05-statistics.md`), in this style. Added (decided 2026-11-11):

From numbers `stats.sqlite` already has:
- **Languages:** share of Ukrainian and English, and how often the detected language differs from the chosen one.
- **Speed:** wait time per second of audio, by engine and model, over time.
- **Dictionary:** how many replacements were made and which terms most often.
- **Failures:** share of "nothing recognized" and cancelled dictations.
- **Meetings:** the author's share of words against the others, number of people, duration, failed chunks.

New numbers to collect:
- Meetings by app (Teams, Zoom, Meet).
- Offers to record: accepted, dismissed, hidden by time.
- **Words per saved person**, when Remember voices is on. `stats.sqlite` holds no names, so these counts live in the meetings database next to the saved voices and are deleted with them.

### 5.7 Settings
A second column lists the sections: General, Hotkeys, Engines and models, Dictation, Overlay, Meetings, Calls, History and privacy, Appearance. Contents are as in `04-settings.md` §3, minus what moved to its own sidebar item (Dictionary, Statistics).

New sections:

**Calls**

| key | default | allowed | meaning |
|---|---|---|---|
| `callOffer` | `true` | `true`, `false` | Show a panel when a call starts |
| `callOfferSeconds` | `15` | `0`, or 5–120 | Seconds until the offer panel hides; `0` keeps it until a button is pressed |
| `callAutoStart` | `false` | `true`, `false` | Start the transcript when the countdown ends |
| `callAutoStartSeconds` | `5` | 3–60 | Length of that countdown |
| `callAutoStopSeconds` | `10` | 3–120 | Seconds from the call's end to the transcript's stop |
| `callApps` | Teams, Zoom, Meet on | list of app names | Apps that get an offer |

**Appearance**

| key | default | allowed | meaning |
|---|---|---|---|
| `theme` | `"system"` | `"system"`, `"light"`, `"dark"` | Light or dark |
| `accentColor` | `"system"` | `"system"`, `"blue"`, `"purple"`, `"pink"`, `"red"`, `"orange"`, `"yellow"`, `"green"`, `"graphite"` | Accent colour; `system` follows macOS |

**People:** `rememberVoices`, default `false`.

## 6. Floating panels

One panel style for everything Shepit shows on its own: a small rounded card in the top right corner of the screen with the call's name, one line of status, a thin progress bar when time is running, one main button and one plain button. It doesn't take keyboard focus. The dictation overlay keeps its own place and settings.

| state | text | bar | buttons | when the time ends |
|---|---|---|---|---|
| Call started, automatic start off | name (or "Zoom call"), app, "hides in N s" | `callOfferSeconds`; none when 0 | Start transcript · Not this call | The panel hides. The call counts as dismissed |
| Call started, automatic start on | name, app, "transcript starts in N s" | `callAutoStartSeconds` | Start now · Don't record | The transcript starts |
| Call ended while recording | "Call ended", "transcript stops in N s" | `callAutoStopSeconds` | Keep recording · Stop now | The transcript stops |
| Transcript ready | name, duration, people | none | Name people · Close | Hides after a few seconds |

- "Not this call", "Don't record" and a hidden offer apply to this call only. A transcript can still be started from the menu or the window.
- Start from the panel doesn't open the name dialog. The name shown in the panel is used; it can be changed later in the window.
- "Name people" opens the window on that meeting.

## 7. The menu

Quick actions only (mockup 10): status line, Open Shepit, Start or Stop meeting transcript, Copy last dictation, Recent, Add word…, Mode, Language, Dictation engine, Settings…, Quit. While recording, the status line shows the red dot, the name and the time.

Gone from the menu, now in the window: Rename speakers (both), Copy last meeting transcript, Open meetings folder, Edit dictionary, Reload settings, Reload model, Statistics.

## 8. My calls (shown to the author, not confirmed one by one)

- A Home section for status and quick controls.
- A People section in the sidebar for saved voices, instead of a place inside Settings.
- `callOfferSeconds` default 15; the author suggested a minimum of 5. A hidden offer counts as a dismiss for that call.
- `callAutoStartSeconds` 5 and `callAutoStopSeconds` 10.
- Slack is listed in Calls → Apps but off until research shows its calls can be detected.
- Accent colour defaults to the macOS accent. The colour list is the macOS one.
- Start from the panel skips the name dialog. `meetingAskTitle` then applies only to Start from the menu or the window.
- Per-person word counts are kept with the saved voices, not in `stats.sqlite`, so the rule "no names in statistics" stays true.
- Renaming a meeting renames its note file (the author's decision). Links to the note from other Obsidian notes are not updated: Obsidian only does that for renames made inside it.
- Home shows the last 10 dictations; a long dictation is cut to two lines until clicked.
- The menu's Engine item is the dictation engine and is named so. The other two engines are changed in the window.
- A "Transcript ready" panel with a "Name people" button.
- Panels sit in the top right corner.

## 9. Not in this spec

- How a call is detected, and what Slack, Teams in a browser, FaceTime and Telegram show: research in the offer-to-record spec.
- The meetings database, voice prints and import formats: the main window spec. The Meet `.txt` format waits for a sample from the author and is done last.
- Calendar names (EventKit): `docs/future-ideas.md`.
