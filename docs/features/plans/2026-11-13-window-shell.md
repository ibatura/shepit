# Main window, part 1 (shell with Home and Settings): implementation plan

**Goal:** The Settings window becomes the one main window: a sidebar (Home, Meetings, Dictations, Dictionary, People, Statistics, Settings), a Home section with status and quick controls, Settings with its own section list plus Appearance and a meeting hotkey. The menu shrinks to quick actions. Meetings, Dictations and People are placeholders.

**Architecture:** What Home and the menu show is built as data in `ShepitCore` from one input (`MenuView`, extended) and unit-tested. `Shepit` gets `MainWindow` in place of `SettingsWindow`, a root view with the sidebar, and one observable model that `AppHost` refreshes only while the window is open. Settings controls keep writing one key each through `SettingsModel`; Home uses the same bindings.

**Spec:** `docs/features/specs/2026-11-13-window-shell-design.md` ("the spec"; section numbers refer to it). Look: `docs/features/specs/2026-11-11-visual-style/` (`visual-style.md` §3–5.1, §5.7, §7; `mockups.html` screens 1, 8, 10).

**Branch:** `window-shell`, cut from `main`. Ask the author before merging into `main` and before pushing.

## Execution notes

- **Style: Ponytail (full)** for every task (`~/.claude/skills/ponytail`): the smallest complete change, a test for every non-trivial branch, no options nobody asked for.
- **Review per task:** the task's diff is checked against the Ponytail rules; Tasks 4, 5 and 6 also get `/code-review` on their diff.
- **Review at the end (Task 9):** the author runs `/thermo-nuclear-code-quality-review` on the branch (only the author can start it); then `/code-review` and `/security-review` on the whole branch. Findings are shown to the author as a list; the author picks what to change.
- One task at a time, a commit per task, `make test` green after each (454 tests on 2026-11-13).
- Tests first for everything in `ShepitCore`.
- The author's own `~/.config/dictation/settings.json` is not changed by code or tests.
- Try a change with `scripts/install.sh`. From Task 4 on, look at each screen next to its mockup before the commit.
- **Author gates: Task 7 (the accent colour probe) and Task 9.**

## Global constraints

- One window. `SettingsWindow` is replaced, not kept beside the new one.
- Every control writes exactly one key through `SettingsModel` (or `dictionary.json` through its store). Window state (frame, sections) lives in the app's preferences, never in `settings.json`.
- While `settings.json` has errors, Home's controls are read-only like the Settings sections.
- No timer, file read or device lookup for the window while it is closed.
- The window and the Dock icon never appear on their own.
- Standard SwiftUI controls and SF Symbols; English labels in sentence case; texts as in the spec and the mockups.
- No network, no new permission.

## Review focus

1. **One source of truth:** a value changed on Home, in Settings, in the menu or in the file by hand shows the same everywhere within the 2 s poll.
2. **Nothing is lost from the menu:** every removed item has a place in the window (spec §7).
3. **App mode:** regular only while the window is open; closing it never stops dictation, the call watch or a transcript; the call panel and the dictation overlay still don't take focus.
4. **Idle cost:** nothing runs for the window while it is closed. Tasks 4 and 5.
5. **The meeting hotkey** can't shadow the dictation or add-word hotkey, and does nothing harmful while a transcript is finishing. Task 6.

## File structure

```
app/Sources/ShepitCore/
  Settings.swift / SettingsValidation.swift / SettingsStore.swift   + theme, accentColor, meetingHotkey; removing a key (Task 1)
  MenuModel.swift            the menu of spec §7 (Task 2)
  HomeModel.swift            Home's rows as data (Task 3)
  CallOffer.swift            + the current call's name and app (Task 3)
app/Sources/Shepit/
  Window/MainWindow.swift    the window, Dock policy, menu bar, remembered state (Task 4)
  Window/MainView.swift      sidebar, recording card, placeholders, problems banner (Tasks 4, 5)
  Window/WindowModel.swift   observable state fed by AppHost (Task 5)
  Window/HomeSection.swift   (Task 5)
  Settings/SettingsView.swift            the section list and form, from SettingsWindow.swift (Task 4)
  Settings/AppearanceSection.swift       (Task 7)
  Settings/SettingsSections.swift        + meeting hotkey recorder (Task 6)
  HotkeyCenter.swift         + meeting hotkey (Task 6)
  AppHost.swift / AppDelegate.swift      openers, actions, refresh (Tasks 2, 4, 5)
```

---

### Task 1: Settings keys

- Tests first: defaults (`theme` and `accentColor` are `"system"`, `meetingHotkey` is nil); allowed values of spec §6.1 accepted, others rejected with the key named; `meetingHotkey` validated like `hotkey`, and `null` accepted as none; a file without the keys loads; unknown keys are kept on update.
- `SettingsStore`: a way to remove one key from the file (for the meeting hotkey), with a test that the other keys and unknown keys stay.
- `examples/settings.json` and the README table get the three keys (the README examples test stays green).
- Commit `Shepit: theme, accent colour and meeting hotkey settings`.

### Task 2: The menu

- Tests first for `MenuModel.build`, one per rule of spec §7: the order; Open Shepit with ⌘O; "Copy last dictation" copies the newest entry and is off with an empty or hidden history; the engine item is named "Dictation engine"; the recording line "⏺ Recording · name · 12:34" with and without waiting phrases, and the finishing and detecting lines; the meeting items still present; the removed items absent; ⚠ lines unchanged.
- `MenuView` gets the meeting's name. `MenuAction` gets `openWindow`; cases no menu item sends any more are removed when nothing else uses them.
- `AppHost.perform`: `openWindow` opens the Settings window for now (Task 4 gives it the real window).
- Commit `Shepit: the menu keeps quick actions`.

### Task 3: Home as data

- `HomeModel.build(view) -> Home` in `ShepitCore`, from the same `MenuView` the menu uses (extended where needed: the detected call, the newest 10 history entries, the downloaded pairs). `Home` holds: the status text; warning rows (kind, text, button title); the three engine rows (title, hint, choices with titles like "whisper.cpp · large-v3", the current one, "(not downloaded)", enabled); the meeting row (one of: no call, detected call, recording, finishing, detecting, model missing; with its texts and button); the dictation rows (text, time with the date when not today) and the empty text.
- `CallOffer` exposes the current call's name and app once it counts as a call (also after a dismiss), nil otherwise.
- Tests first, one per state of spec §5: each status; each warning; pickers off while their job runs; a configured pair that is not downloaded; the meeting row in each of its six states, including "Call offers are off"; 10 newest rows, today and earlier, empty history, `saveHistory` off; the current call before the hold, after it, after a dismiss, after release.
- Commit `Shepit: Home rows as data`.

### Task 4: The window shell

- `MainWindow` replaces `SettingsWindow`: title, sizes and the new frame autosave name of spec §4; the sidebar section and the Settings section remembered in the app's preferences; `show(section)` for the three openers (menu Open Shepit, Settings… and ⌘,, launching again).
- App mode: regular when the window opens, accessory when it closes (also resumes hotkeys, as today's close does). The menu bar of spec §4 (Shepit, Edit, Window).
- `MainView`: `NavigationSplitView` with the sidebar of spec §4.1 (SF Symbols, a separator above Settings), the problems banner above every section, and the three placeholders with their texts (Dictations with Open history file).
- Dictionary and Statistics become sidebar sections with today's views. `SettingsModel.Section` loses them and takes the order and names of spec §6 (Appearance is added in Task 7). Settings shows its section list as a second column. The Statistics "Typing speed" link opens Settings → History and privacy.
- The test that every settings key belongs to exactly one section is updated; a test for the remembered-section values (unknown stored value → Home).
- Install; by hand: W1, W2, W3 of spec §9; the call panel (`Shepit panel-test`) and the dictation overlay still don't take focus while the window is open.
- Commit `Shepit: main window with sidebar in place of the Settings window`.

### Task 5: Home and the recording card

- `WindowModel` (observable): holds the current `Home` and the recording card's content. `AppHost` rebuilds it where it refreshes the menu-bar title, in the 2 s poll, and once a second while a meeting runs; all three only while the window is open. Opening the window rebuilds it once.
- `HomeSection` draws `Home` as the four groups of mockup 1. Mode, Language and Microphone use the `SettingsModel` bindings; the engine pickers use `setEngine`; buttons call the existing actions (reload settings, reload model, start and stop meeting, copy, grant Accessibility, microphone settings). Start for a detected call passes its name and app, with no dialog.
- The recording card at the top of the sidebar while a transcript runs; a click opens Home. "All dictations" opens Dictations. "Download models…" opens Settings → Engines and models.
- Install; by hand: W4–W6 and W8; W7 as far as a call to yourself allows.
- Commit `Shepit: Home section and recording card`.

### Task 6: Meeting hotkey

- Tests first in `HotkeyCenterTests`: registered when set; not registered when none; a clash with the dictation or add-word hotkey is reported and the meeting hotkey is not registered; re-applied after a settings change; removed.
- `HotkeyCenter` gets the fourth hotkey and `onMeeting`. `AppHost` wires it: start as the menu's Start, stop as the menu's Stop, "Transcript is finishing" otherwise.
- Hotkeys section: the recorder for it with a Remove button; a clash is shown inline and not saved.
- Install; by hand: W10.
- Commit `Shepit: hotkey to start and stop a meeting transcript`.

### Task 7: GATE — Appearance (with the author)

- **Step 1, probe:** try the per-app accent setting of macOS and SwiftUI's tint on the installed app: which of sidebar selection, main buttons, switches, pickers, the call panel's bar and the charts follow each, and whether a restart is needed. Show the author both; the author picks. Record the choice in the commit message.
- `theme` sets the app's appearance at start and on change (window, call panels, dialogs).
- `AppearanceSection`: the Theme picker ("Same as macOS", "Light", "Dark") and the row of colour dots; the restart hint only if the chosen way needs it.
- Install; by hand: W9.
- Commit `Shepit: Appearance settings`.

### Task 8: Docs

- README: the window (how to open it, the sections, what is a placeholder), the shorter menu, the meeting hotkey, Appearance.
- `docs/manual-test-checklist.md`: W1–W10 from spec §9.
- `04-settings.md` §3 gets one line pointing to the spec (the window it describes was replaced).
- Commit `Docs: main window shell`.

### Task 9: GATE — the author's checks and reviews

- W1–W10 with the author on the installed app, W7 on a real call. In part: W3, and parts of W2, W7 and W9 on 2026-11-13; on 2026-11-14 the author clicked through the window and found it working, without going through the list.
- The end-of-branch reviews from the execution notes, and the whole diff against the Review focus list; fix what the author picks. 2026-11-14: thermo-nuclear (all applied), `/code-review max` (15 findings, all fixed), `/security-review` (nothing found).
- Update `docs/future-ideas.md` and "Where things stand" in `CLAUDE.md`. Ask the author before merging into `main`.

---

## Open questions to raise when the task starts (not blockers)

- Task 4: whether SwiftUI's own selection restoring is enough for the remembered sections, or they are stored by hand.
- Task 4: with the window in front, where a dictation is pasted (W3). If it can't go anywhere sensible, write the limit into the README.
- Task 5: whether `NavigationSplitView` can hold the recording card above the list, or the sidebar is a plain list with the card as its first row.
- Task 7: whether changing the theme needs the dictation overlay or the call panel to be rebuilt.
