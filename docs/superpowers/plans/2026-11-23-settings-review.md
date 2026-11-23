# Main window, part 8 (Settings review): implementation plan

**Goal:** every setting where it is looked for, each page saying what it is for; Home as a status page and the 🎙 menu in groups; Auto, Offer or Off for each call app with rules by meeting name; one period menu in every section.

**Architecture:**
- **Pages** stay SwiftUI `Form` sections in `app/Sources/Shepit/Settings/`. `SettingsModel.Section` goes from nine cases to seven, and its `keys` stay the one list of which page edits which key.
- **Calls** get two keys, `callModes` and `callRules`, read by a pure `CallRules` in ShepitCore. `CallOffer` asks it once the call's name is known.
- **Home and the menu** keep being built from `AppSnapshot` by `HomeModel` and `MenuModel` (ShepitCore); the snapshot gains the recent meetings.
- **The period menu** is Statistics' `PeriodMenu`, moved to `Controls.swift` and used by three sections.

**Spec:** `docs/superpowers/specs/2026-11-23-settings-review-design.md` ("the spec"; section numbers refer to it), approved by the author on 2026-11-23.

**Branch:** `settings-review`. It holds the docs commits of 2026-11-23 and the spec. When it is ready, ask the author whether to open the pull request; push the branch and open it only after they say yes. The author merges it in GitHub; Claude never merges.

## Execution notes

- **Style: Ponytail (full)** for every task (`~/.claude/skills/ponytail`): the smallest complete change, a test for every non-trivial branch, and no options nobody asked for.
- **Review per task:** check each task's diff against the Ponytail rules. Tasks 5 and 6 also get `/code-review` on their diff: the settings file and the call decision.
- **Review at the end (Task 10):**
  - The author runs `/thermo-nuclear-code-quality-review` on the branch; only the author can start it.
  - Then `/code-review` and `/security-review` on the whole branch.
  - Show the findings to the author as a list; the author picks what to change.
- **One task at a time,** with a commit per task and a short message. `make test` must be green after each task (669 tests on 2026-11-22).
- **Tests first** for `CallRules`, the call keys and the `CallOffer` changes.
- **Test data:** settings files, stores and notes in temporary folders, `UserDefaults` suites of their own; never `~/.config/dictation`, `~/.local/share/dictation`, the author's meetings folder or Shepit's own preferences.
- **Settings:** the author's own `~/.config/dictation/settings.json` is not changed by code or tests. An "old file" check uses a copy in a temporary folder.
- **Ask before installing:** it restarts Shepit, and a transcript may be running.
- **Gates** (marked GATE) end with the author looking at the installed app before the next task.

## Global constraints

- **No setting nobody asked for.** The only new keys are `callModes` and `callRules` (spec §7.2).
- **Shepit never rewrites `settings.json` on its own.** It writes only on a change in the window, one key at a time, as today; the first change on the Calls part also removes the three old call keys in that same write.
- **Old files keep working:** a file with `callOffer`, `callAutoStart` and `callApps` behaves as before until the Calls part is changed; a file with a dropped key loads with no error.
- **No network, no new permission.**
- **Controls:** standard SwiftUI in a grouped `Form`, as the pages are today; the segmented control is `Picker(...).pickerStyle(.segmented)`; English texts of the spec (§4, §7.3).

## Review focus

1. **No setting is lost in the move** (Tasks 2–3): every key of `Settings` is on exactly one page, or named as shown elsewhere (`rememberVoices` in People), or dropped by Task 1.
2. **The call decision** (Task 6): an app set to Off is not watched; the choice waits for the name, 5 s at most; the first matching rule decides for Auto and Offer; a rule's Off shows nothing; no name means the app's choice.
3. **The old call keys** (Task 5): read while `callModes` is missing, exactly as `CallOffer` used them; removed only with the first write of `callModes`.
4. **Home and the menu** (Task 4): nothing that left Home or the menu was the only way to do something (Mode is in Hotkeys, the engines in Engines and models, the microphone in Dictation).

## File structure

```
app/Sources/ShepitCore/
  Settings.swift             callModes, callRules, callMode(for:); dropped keys gone (Tasks 1, 5)
  SettingsValidation.swift   the new keys' checks; dropped keys ignored (Tasks 1, 5)
  SettingsStore.swift        update(_:_:removing:) for the first write of callModes (Task 5)
  CallRules.swift            new: the choice for an app and a name (Task 5)
  CallOffer.swift            Off not watched; a naming phase; the choice from CallRules (Task 6)
  HomeModel.swift            needs attention, recent meetings; pickers and quick settings gone (Task 4)
  MenuModel.swift            four groups, two languages; Mode and engine gone (Task 4)
  AppSnapshot.swift          recent meetings in the snapshot (Task 4)
app/Sources/Shepit/Settings/
  SettingsModel.swift        seven sections, their keys and lines; old page names mapped (Task 2)
  SettingsView.swift         the page line above each page (Task 2)
  SettingsSections.swift     General, Hotkeys, Dictation (with the panel), History and privacy (Task 2)
  OverlaySection.swift       its parts become Dictation's panel parts (Task 2)
  MeetingsSection.swift      Calls, Notes, Transcript; its Models part leaves (Tasks 2, 7)
  CallsSection.swift         becomes the Calls part of Meetings (Tasks 2, 7)
  EnginesSection.swift       every model, what it is for and what uses it (Task 3)
  ModelDownloads.swift       the detection models' rows, shared with the engines' (Task 3)
app/Sources/Shepit/Window/
  HomeSection.swift          draws the new Home (Task 4)
  Controls.swift             PeriodMenu, moved from StatisticsView (Task 8)
  DictationsView.swift, StatisticsView.swift, PeopleView.swift   the shared period menu (Task 8)
app/Sources/Shepit/
  AppHost.swift, AppHost+Calls.swift, MenuController.swift       recent meetings, the call decision, the menu (Tasks 4, 6)
```

`SettingsSections.swift` has 265 lines and gains Dictation's panel parts. If it passes about 400, Dictation moves to its own `DictationSection.swift`.

---

### Task 1: Every setting still used (the author, spec §2)

- [ ] For each key `validateSettings` accepts, find what reads it beyond `Settings`, `SettingsValidation` and the Settings pages (`grep` the property in `app/Sources`). Write the list in the commit message: key, what reads it.
- [ ] Known to look at first: `serverPort`, `previewModel` and `model` (the old engine keys that `engines` replaced: are they still a fallback for an old file?).
- [ ] A key nothing reads: remove it from `Settings`, its check and its `assign` case, from README and `examples/settings.json`. An old file that has it still loads with no error (unknown keys are skipped today; a test keeps it so).
- [ ] A key that is still a fallback for old files stays, with a comment saying so.
- [ ] If a key is read but no page shows it and it isn't a fallback, show the author before deciding.
- [ ] Commit `Shepit: settings nothing reads are dropped`.

### Task 2: GATE: seven Settings pages (spec §4)

- [ ] **`SettingsModel.Section`:** General, Hotkeys, Dictation, Meetings, Engines and models, History and privacy, Appearance, in that order; `overlay` and `calls` go. Their keys move: `language`, `overlay`, `livePreview`, `overlayStyle` to Dictation; the call keys to Meetings.
- [ ] **A line on every page** (spec §4's texts): a `line` per section, shown by `SettingsView` above the page's `Form` in secondary text.
- [ ] **Dictation:** parts Dictation (Language, Microphone, Max recording length), Text, Panel, Panel look, Panel texts and timing; `OverlaySection`'s views move in, Preview included.
- [ ] **Meetings:** parts Calls (today's `CallsSection` controls for now; Task 7 replaces them), Notes, Transcript (Your name, Language, Block dictation, Recognition). Its Models part stays until Task 3 moves it.
- [ ] **General:** Launch at login, Sounds; Files with Reload settings next to Open settings file.
- [ ] **History and privacy:** the part History is named Dictations.
- [ ] **Remembered page:** `WindowNavigation` maps a stored "Overlay" to Dictation and "Calls" to Meetings; a back step to them does the same.
- [ ] **Tests** (`SettingsModelTests`): the seven sections in order; every key of `Settings` is on exactly one page, except `rememberVoices` (People); the old names map; extend `theWindowRemembersItsSections`.
- [ ] `make test`, ask before installing; the author looks through the seven pages (R1, R2).
- [ ] Commit `Shepit: Settings in seven pages, each saying what it is for`.

### Task 3: GATE: every model in Engines and models (spec §4, "What each engine is for")

- [ ] **Models on this Mac** lists the engine models and the voice and speaker detection models (`ModelCatalog`'s `vad` and `diarization`), with one row view for both kinds (Download, Cancel, Delete…).
- [ ] **Each row says** what the model is for, in one line: speed, accuracy, memory or size, languages; what uses it ("Used for: Dictation, Meetings", "Needed to start a meeting", "Tells call voices apart"); "Not used: can be deleted" when no job uses an engine model. The texts are written from `ModelCatalog` and what the earlier specs measured; the author reads them at the gate.
- [ ] **Jobs:** each of Dictation, Live draft, Meetings keeps its picker and gets its line ("The text that gets pasted", …), the same text Home used to have; Home's copy goes in Task 4.
- [ ] **Meetings → Transcript → Recognition:** "Voice and speaker detection: installed", or what is missing, with a link that opens Engines and models.
- [ ] `make test`, ask before installing; the author reads the rows (R3).
- [ ] Commit `Shepit: every model in Engines and models, each saying what it is for`.

### Task 4: GATE: Home and the 🎙 menu (spec §5, §6)

- [ ] **`AppSnapshot`** gets `recentMeetings`: the last 10 listed meetings (name, app, duration, id), read with the other lookups from `MeetingStore.meetings()`.
- [ ] **`HomeModel`, tests first** (`HomeModelTests`):
  - Needs attention: today's warnings, plus a model a job uses that isn't downloaded, with "Download…" opening Engines and models;
  - Recent meetings: name ("Teams call" with none), app title, length; none when empty;
  - gone: Mode, Language, Microphone, the engine rows, Reload settings, Reload model.
- [ ] **`HomeSection`** draws it; a click on a meeting opens it in Meetings (`navigation.section = .meetings`, `sections.meetings.selection = .meeting(id)`), All meetings opens the section.
- [ ] **`MenuModel`, tests first** (`MenuModelTests`): ⚠ lines; Meeting (state, Start or Stop, Meeting language ▸); Dictation (state line, Copy last dictation, Recent dictations ▸, Add word to dictionary…, Dictation language ▸); Shepit (Open Shepit ⌘O, Settings… ⌘,, About Shepit, Quit Shepit ⌘Q). Mode ▸ and Dictation engine ▸ go; each language greyed while its job runs.
- [ ] **`AppAction`:** `.reloadModels` and the menu's engine action go if nothing else uses them; a meeting language action sets `meetingLanguage`.
- [ ] `make test`, ask before installing; the author checks Home and the menu (R4, R5).
- [ ] Commit `Shepit: Home shows status and recent meetings; the 🎙 menu in groups`.

### Task 5: The call keys and CallRules (spec §7.2)

- [ ] **Tests first** (`SettingsTests`, new `CallRulesTests`):
  - `callModes` and `callRules` read and validated: an unknown app, choice, match or a rule missing a field is an error; an empty text is allowed and matches nothing;
  - `callMode(for:)` with no `callModes`: from `callApps`, `callAutoStart`, `callOffer`, as spec §7.2 says, for each combination today's `CallOffer` handles;
  - `CallRules.choice(app:name:settings:)`: Off ignores the rules; contains and is, case ignored; the first matching rule; no name; a rule of another app.
- [ ] **`Settings`:** `callModes: [CallApp: CallMode]?` (nil when the file has none) and `callRules: [CallRule]`; `CallMode` is `auto`, `offer`, `off`; `CallRule` is app, match, text, then.
- [ ] **`SettingsStore.update(_:_:removing:)`:** writes one key and removes others in one write; `SettingsModel` uses it for the first write of `callModes` (removing `callOffer`, `callAutoStart`, `callApps`).
- [ ] `/code-review` on the task's diff.
- [ ] Commit `Shepit: Auto, Offer or Off per call app, and rules by meeting name, in the settings`.

### Task 6: The call decision (spec §7.1)

- [ ] **Tests first** (`CallOfferTests`):
  - an app set to Off: no call, no panel, no stop countdown; a transcript started by hand stays ordinary;
  - Auto or Offer: after the 3 s hold, `.lookForName` and no panel; `.named` then gives the panel of the choice; a rule's Off gives none (Home's `current` still has the call);
  - no answer within 5 s: the app's choice, with no name;
  - the existing tests keep passing with `callModes` built from today's defaults.
- [ ] **`CallOffer`:** `callApps` replaced by `callMode(for:) != .off`; a `naming(since:)` phase between the hold and the offer; the choice from `CallRules` on `.named`; `callAutoStart` replaced by the choice in `advance` and `currentPanel`.
- [ ] **`AppHost+Calls`:** the name lookup as today; nothing else should need to change. Check `HomeModel`'s call hint ("Call offers are off") against the new modes.
- [ ] `/code-review` on the task's diff.
- [ ] Commit `Shepit: each call app's choice and the rules decide the offer`.

### Task 7: GATE: the Calls part (spec §7.3)

- [ ] **Each app:** a row with its name and `Picker` Auto · Offer · Off, `.pickerStyle(.segmented)`, a hint per choice.
- [ ] **Rules by meeting name:** a list with + and − below (a SwiftUI `List` or `Table` with `.onMove`), each row app, match, text, then; a rule of an app set to Off greyed with "Ignored: Teams is Off". A text field saves on Enter or when it loses focus, as `NameField` and `EditableTitle` do.
- [ ] **Delays:** Start after (Auto), Hide the panel after (Offer), Stop after the call ends.
- [ ] `make test`, ask before installing; with the author on calls: R6 (Teams: Offer, a rule Off, then Auto), R7 (Zoom Off), R8 (an old settings file copy in a test folder, read by a test build or `Shepit` pointed at it, not the author's file).
- [ ] Commit `Shepit: the Calls part with Auto, Offer, Off and rules`.

### Task 8: GATE: the period menu (spec §9)

- [ ] **`PeriodMenu`** moves to `Controls.swift`, taking a binding to the period and Custom…'s sheet.
- [ ] **Dictations, Statistics, People:** the menu on the right of each top bar; Dictations' "Show" picker goes; Dictations and People gain Custom….
- [ ] **The rest of the window:** go through every section for controls that differ (top bars, buttons at the bottom, empty states, questions and alerts). Fix the small ones; show the author a list of the others before changing them.
- [ ] `make test`, ask before installing; the author checks R9.
- [ ] Commit `Shepit: one period menu in Dictations, Statistics and People`.

### Task 9: GATE: the Google Meet panel in Chrome (spec §8, with the author)

- [ ] With the author on a Meet call in Chrome: `Shepit call-watch` in a terminal, and Shepit's log (`log show --predicate 'process == "Shepit"'`) while the offer should show. Note where the panel is (screen, Space), whether it is drawn, and what `stats.sqlite` records.
- [ ] Fix what is found; check again on a call (R10).
- [ ] If the cause is outside Shepit, write it under "Call offer: left open".
- [ ] Commit `Shepit: <what was found> for the Meet panel` (or `Docs: …` if nothing changes in code).

### Task 10: Docs, version and the author's reviews

- [ ] **README:** Settings' pages, Home, the menu, Auto/Offer/Off and rules.
- [ ] **`examples/settings.json`:** `meetingHotkey`, `callModes`, `callRules`; without the dropped keys.
- [ ] **`docs/manual-test-checklist.md`:** "Main window: Settings review" with R1–R10:
  - R1 each page has its line, no setting missing; R2 a remembered Overlay page opens Dictation;
  - R3 Engines and models: every model, what it is for, "Not used";
  - R4 Home with a missing model and with recent meetings, a click opens one; R5 the 🎙 menu's groups and both languages;
  - R6 Teams Offer, then a rule Off, then Auto; R7 Zoom Off during a Zoom call; R8 an old settings file copy;
  - R9 the period menu in three sections; R10 the Meet panel in Chrome.
- [ ] **`docs/future-ideas.md`:** item 10 built on `settings-review`; "Automatic start per app", "Rules by meeting name", "What each engine is for" and the three "Window shell: left open" points marked done; what is left under "Settings review: left open".
- [ ] **`CLAUDE.md`:** "Where things stand" with how it fits together; the Next list; the test count.
- [ ] **Version:** agreed with the author (0.4.0 proposed); `CFBundleShortVersionString` in `app/Resources/Info.plist`; `docs/releases/<version>.md`.
- [ ] Commit `Docs: the settings review; version <version>`.
- [ ] **Reviews:** the author runs `/thermo-nuclear-code-quality-review`; then `/code-review` and `/security-review` on the branch; the findings go to the author as a list, and the author picks what to fix.
- [ ] **Pull request:** ask the author whether to open it. Its description says what changed and how it was checked.

## Open questions to raise when the task starts (not blockers)

- **Task 1:** if `model` or `previewModel` turn out to be the only way an old file names its engines, keep them as fallbacks and say so to the author.
- **Task 4:** whether "Download…" on Home downloads at once or opens Engines and models (the spec says it opens it).
- **Task 6:** a transcript started by hand during a call of an app set to Off ends with the dictation panel's short "Transcript ready" notice, as every transcript started by hand does today; the spec says no "Transcript ready" panel for such an app. Ask the author whether that notice stays.
- **Task 7:** if `.onMove` in a grouped `Form` looks wrong, show the author ↑ ↓ buttons in each row instead.
- **Task 8:** if Custom… doesn't fit Dictations' list (a day-by-day list), ask before adding it there.

## Progress

- **Task 1** (2026-11-23, 979bb03): only `serverPort` was read by nothing, and it is dropped; `model` and `previewModel` stay as fallbacks for old files.
- **Task 2** (2026-11-23, 2293a1d): the author looked through the seven pages on the installed app: "all good" (R1, R2).
