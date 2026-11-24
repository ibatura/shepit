# How Shepit fits together

The code, part by part, and the numbers settled along the way. Read the part you are changing. Each part's spec and plan are in `docs/features/`; what it left open is in `docs/future-ideas.md` under "<Part>: left open"; its manual checks are in `docs/manual-test-checklist.md`.

## Packages

A SwiftPM package in `app/`:

- `ShepitCore`: pure logic with tests (settings, dictionary, meeting session and notes, meeting names, language choice, the stores, every section's page as data).
- `ShepitEngines`: whisper.cpp, WhisperKit, Parakeet, Apple Speech.
- `Shepit`: the app (menu, hotkeys, overlay, audio, call tap, the window, Accessibility scan of meeting apps in `MeetingApps.swift`).

`scripts/`: build, sign, install, uninstall, model downloads (pinned SHA-256 in `scripts/models/`). A plain `swift build --package-path app` on a fresh clone needs `scripts/build-whisper-lib.sh` first.

## Data

- `settings.json` in `~/.config/dictation/`; every output has a path setting with a local default under `~/.local/share/dictation/`.
- The SQLite databases share one setting, `databasesFolder`, read at launch: `stats.sqlite` (version 2), `meetings.sqlite` (version 3), `dictations.sqlite`. `SQLiteFile` creates a missing file only on a write and runs numbered upgrades in one transaction. A transaction takes the write lock first (`BEGIN IMMEDIATE`), so it waits for another connection's write instead of failing.
- Every query reads part of a table through an index, or reads it all on purpose and says so (query plans design, 2026-11-24). A new or changed query gets `EXPLAIN QUERY PLAN` in its task's review.
- `dictionary.json`, `meeting-names.json` (remembered names of repeating meetings), the meeting notes in their folder.
- `CallApp.rawValue` is what files keep; `CallApp.title` is the name on screen ("Google Meet").

## Debug commands

- `Shepit call-watch`: which app holds the microphone, and the call's name.
- `Shepit panel-test`: the call panel.
- `Shepit voices-check`: how voice recognition does on the stored samples, in counts only.

## Parts

| Part | Merged | Release | Spec and plan (`docs/features/`) |
|---|---|---|---|
| Dictation, settings, statistics, meeting transcripts (phases 1–3) | 2026-10 | | `specs/2026-10-04-dictation-tool-design.md`, `specs/2026-10-17-meeting-transcription-design.md`, `specs/2026-10-18-native-app/` |
| Visual style | 2026-11-11 | | `specs/2026-11-11-visual-style/` |
| Call offer | 2026-11-13 | | `2026-11-12-call-offer` |
| Window shell | 2026-11-14 | | `2026-11-13-window-shell` |
| Meetings | 2026-11-16 | | `2026-11-14-meetings` |
| Dictations and Dictionary | 2026-11-17 | | `2026-11-16-dictations-dictionary` |
| Statistics | 2026-11-17 | | `2026-11-17-statistics` |
| Voices and People | 2026-11-20 | | `2026-11-17-voices` |
| Import names, version and About | 2026-11-21 | v0.2.0 | `2026-11-20-import-names` |
| Back and forward | 2026-11-22 | v0.3.0 | `2026-11-22-back-forward` |
| Settings review | 2026-11-24 | v0.4.0 | `2026-11-23-settings-review` |

### Meeting transcripts and names

- A meeting's name: the Teams window title, the Meet tab title or page bar, or the name remembered for a repeat (`meeting-names.json`). Zoom shows no topic. Mute state is read from all three apps.

### Call offer

- `CallWatch` polls which app holds the microphone; `CallOffer` (ShepitCore) decides; `CallPanel` shows the panel; `AppHost+Calls.swift` wires them.
- A call's end is the app releasing the microphone for 3 s. Teams, Zoom and Meet in Chrome keep it while muted (checked on calls, 2026-11-13 and 2026-11-23).
- A call that starts while the last transcript is finishing gets its offer once it has (`CallOffer`'s held phase).
- Each app's choice (Auto, Offer, Off) and the rules by name: see Settings review.

### Window shell

- `AppHost.snapshot()` builds an `AppSnapshot` (ShepitCore) from live state plus cached `Lookups` (devices, downloads, history, permissions; gathered when the menu or window opens and by the 2-s poll).
- `MenuModel` builds the menu and `HomeModel` builds Home from it; `MainWindow` pulls Home through a closure. Actions are `AppAction`.
- Window code: `app/Sources/Shepit/Window/` and `AppHost+Window.swift`.

### Meetings

- `meetings.sqlite` lists every transcript: meetings, their people and who said each line, no transcript text.
- `MeetingNote` reads notes and pairs headers with stored lines by `Place` (timestamp and order in that second).
- `MeetingStore` (ShepitCore) changes the store and the note's headers together (`change`, `rename`, `remove`, `add(note:)`, `delete`). It is in three files: the meetings list and notes (`MeetingStore.swift`), persons and People's reads (`+People`), voices (`+Voices`).
- `MeetingPage` turns them into list rows, people and transcript rows.
- In the app, `MeetingsModel` is the section's state and `MeetingsView` draws it. The running transcript is `AppSnapshot.meeting` (`LiveMeeting`); `AppHost.addToMeetings` lists a finished one.

### Dictations and Dictionary

- Every dictation goes to `dictations.sqlite` with its app; `history.log` is no longer written or read.
- `DictationStore` (ShepitCore) keeps the entries and reports every change to `AppHost.refreshHistory`, which refreshes Home, Recent and the open section. `DictationPage` builds the section's lines, periods and texts.
- `DictionaryStore.change` edits `dictionary.json` as the file is now, with the edits on `DictionaryFile`.
- In the app, `DictationsModel` / `DictationsView` and `DictionarySection` in `Window/`.

### Statistics

- `Stats` (ShepitCore) computes the numbers from `Stats.Rows`; `StatisticsPage` turns them into each view's tiles, bars, lines and texts. `stats.sqlite` keeps each meeting's call app.
- `StatsPeriod` is a `Period` preset or a custom range of days, shared with Dictations and People.
- In the app, `StatisticsModel` reads the rows and builds the pages (on appear, on a change of period, after every `AppHost.recordStats` write and past midnight); `StatisticsView` and its three views only draw them.

### Voices and People

- With Remember voices on (People; off by default) every transcript line keeps a voice sample in `meetings.sqlite`: 256 numbers from speaker detection, no audio. The author's first 10 minutes of speech on the microphone give their own.
- A person's print is the mean of the samples of the lines they have now, so naming, merging, giving a line and reset change it with nothing else to update.
- When a transcript is ready, an unnamed Person N is named by a print (threshold 0.7, margin 0.1, at least 3 samples) and marked "recognised by voice".
- Samples go with their meeting, with Delete voice and Delete all voices, and after 30 days for a person with no name; `secure_delete` is on.
- The temporary view `line_voices`, made on every open, is each sample with its line's person now; every voice read goes through it.
- `Voices` (ShepitCore) makes prints, recognises and suggests; `PeoplePage` builds the section's list, a person, their talk and meetings.
- Prints are read off the main thread with a connection of their own (`MeetingStore.prints(in:)`): at Stop, and by `PeopleModel`, which keeps them until the store's `version` changes.
- So are the two other reads of every sample:
  - May also be in (`suggestedVoices(in:for:)`), one read at a time. A read that ends after the choice, the store or Remember voices changed reads again.
  - Forgetting old unnamed voices (`forgetUnnamedVoices(in:before:)`), at launch and after each meeting is listed. It deletes only samples that belong to nobody named, so the prints don't change.
- In the app, `PeopleModel` / `PeopleView`; `EditableTitle` (Controls) is a person's and a meeting's name, saved with Save or Enter.
- **Settled:** the microphone's 10 minutes and recognition (mean, 0.7, margin 0.1; your voice only from the microphone) with `Shepit voices-check`. On 2026-11-20 it gave 11 recognised, 0 wrong, 2 missed at 0.7, so 0.7 stays until more people are in several meetings. A Teams `.vtt` of one call agreed with Shepit's speakers on 79–98% of each one's time. These numbers stay fixed, not settings (settings review, 2026-11-23).

### Import names

- Import names… in a finished meeting reads a Teams or Zoom `.vtt` the author picks, finds where it sits in the meeting by trying every whole-second shift (it must clearly beat every shift a minute away), and shows a sheet. Apply names makes one `MeetingStore.change`. Nothing of the file is kept.
- `SpeakerTranscript` (ShepitCore) reads cues (start, end, speaker) and drops the text.
- `NameImport.align` lines them up with `MeetingStore.lines` (timed by `timed`: seconds, or half a second per word) and matches people; `NameImport.sheet` builds the `Sheet`, which is also what the author edits (`clashes`, `canApply`, `changes`).
- In the app, `MeetingsModel.importNames` / `applyNames`, `ImportNamesSheet` in `Window/`; `NameField` reports each edit with `changed`.
- **Settled:** the numbers in the spec's §11, on the author's meetings.

### Version and About

- `app/Resources/Info.plist` holds the version; `scripts/build-app.sh` writes the commit as `CFBundleVersion`; About Shepit is in the 🎙 menu and the app menu.
- `.github/workflows/release.yml` makes the tag and the release when a merge into `main` raises the version.

### Back and forward

- `BackForward` (ShepitCore) is the history: visit, back, forward, peek, replace; 50 steps, in memory while Shepit runs.
- `WindowPlace` and `WindowNavigation` (`Window/WindowNavigation.swift`) build the place from the section and the Meetings and People choices, and record every change of it themselves (Observation, read on the main actor's next turn, so a change made in one go is one step). They also apply a step and give the hints.
- Whether a step is alive, and its name in a hint, come from the sections: `MeetingsModel.describe` and `PeopleModel.describe`, which ask the store (`store.meeting`, `MeetingStore.listed(person:)`).
- `MainWindow.meetingAdded` turns the running transcript's steps into the meeting's; the end of every transcript (`onFinished` in `AppHost+Meetings`) drops what is left of them.
- In `MainView`: `SectionList` is the sidebar list, icons only when collapsed; `WindowButtons` holds the sidebar button and the arrows; `RecordingDot` stands for the recording card when collapsed.

### Settings review

- `SettingsModel.Section` is the seven pages: each one's `line` and `keys` (a test checks every key of the file is on exactly one). A remembered Overlay or Calls page opens Dictation or Meetings.
- **Calls:** `CallRules.swift` (ShepitCore) has `CallMode`, `CallRule` and, on `Settings`, `callMode(for:)`, `hasCallRules(for:)` and `callChoice(app:name:)`.
  - `validateSettings` reads an old file's `callApps`, `callOffer` and `callAutoStart` into `callModes`, and `model` and `previewModel` into `engines`, so `Settings` has none of them.
  - `CallOffer` waits for the call's name (`naming`, 5 s at most) only while the app has a rule with text; last time's name of a repeating meeting (`.remembered`) shows until the app's, and decides at the end of the wait.
  - `CallsSection` draws the part; `SettingsModel.setCallMode` writes every app's choice, so the store drops `callOffer`, `callAutoStart` and `callApps` on the first change.
- **Home and the menu:** `HomeModel` and `MenuModel` from `AppSnapshot`, which has `meetingModels` and `recentMeetings`; the actions `setLanguage`, `setMeetingLanguage` and `openModels`.
- **Engines and models:** `EnginesSection`, the models by kind; `EngineTask.title` and `MeetingModel.job` name the jobs.
- **Controls** (`Window/Controls.swift`): `SettingField` (a text setting with Save, Enter and Esc; `axis: .vertical` for the style prompt; its unsaved draft kept in `SettingsModel.drafts` while the page is not shown), `NumberMenu` (a number as a menu of set values), `Hinted`, `ChoicePicker`.
- `Window/PeriodMenu.swift`: `PeriodMenu` and how each section keeps its `StatsPeriod` in the app's preferences. `DictationStore.page(in:)` and `MeetingStore.presences(of:in:)` take a range with an end.
