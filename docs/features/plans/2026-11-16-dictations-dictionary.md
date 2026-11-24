# Main window, part 3 (Dictations and Dictionary): implementation plan

**Goal:** Dictations are kept in a local database (`dictations.sqlite`) that also knows the app each one went to, instead of `history.log`. The Dictations section shows the whole kept history by day, loaded as it scrolls, with Copy, a click to open a long text, and Delete. The Dictionary section gets the look of mockup 5: terms and drop phrases as chips, replace rules edited in place, Add word.

**Architecture:** The store and what the Dictations section shows are built in `ShepitCore` and unit-tested: a `DictationStore` over the shared `SQLiteFile` like `MeetingStore`, and a pure `DictationPage` that turns entries into day groups and row texts. `AppHost` writes to the store before pasting and builds `AppSnapshot.history` from it, so Home and the menu follow. `Shepit` gets `DictationsModel` and `DictationsView` in `Window/`, and a rewritten `DictionarySection`.

**Spec:** `docs/features/specs/2026-11-16-dictations-dictionary-design.md` ("the spec"; section numbers refer to it). Look: `docs/features/specs/2026-11-11-visual-style/` (`visual-style.md` §5.3–5.4; `mockups.html` screens 4 and 5).

**Branch:** `dictations-dictionary`, cut from `main`. When it is ready: push it and open a pull request with a description, merged as one squashed commit; while `gh` is not logged in, merge it into `main` locally. Ask the author before merging either way.

## Execution notes

- **Style: Ponytail (full)** for every task (`~/.claude/skills/ponytail`): the smallest complete change, a test for every non-trivial branch, no options nobody asked for.
- **Review per task:** the task's diff is checked against the Ponytail rules; Tasks 1, 3 and 5 also get `/code-review` on their diff.
- **Review at the end (Task 7):** the author runs `/thermo-nuclear-code-quality-review` on the branch (only the author can start it); then `/code-review` and `/security-review` on the whole branch. Findings are shown to the author as a list; the author picks what to change.
- One task at a time, a commit per task with a short message, `make test` green after each (523 tests on 2026-11-16).
- Tests first for everything in `ShepitCore`. Tests use databases in temporary folders, never `~/.local/share/dictation`.
- The author's own `~/.config/dictation/settings.json` is not changed by code or tests. The author's dictations are private: when checking the real store, report counts only, never texts.
- Try a change with `scripts/install.sh`. From Task 4 on, look at each screen next to its mockup before the commit.
- **Author gates: Task 4 (Dictations), Task 5 (Dictionary) and Task 7.**

## Global constraints

- A result is written to the store before it is pasted. A failed write shows a message and never stops the paste.
- Nothing is written with `saveHistory` off.
- Dictated text goes only to `dictations.sqlite`: not to `stats.sqlite`, logs or messages.
- A deleted entry and a cleared history leave no text behind (`secure_delete`; Clear history… deletes the file).
- Nothing runs for Dictations while the window is closed, apart from the write after a dictation.
- `dictionary.json` is changed only through today's `SettingsModel` and `DictionaryStore` writes; a dictionary Shepit could not read keeps the section read only.
- Standard SwiftUI controls and SF Symbols; English labels in sentence case; texts as in the spec and the mockups.
- No network, no new permission, no new setting.

## Review focus

1. **No dictation is lost:** the write comes before the paste; a store that fails (locked, disk full, deleted under the app) gives a message and the paste still happens. Task 3.
2. **Privacy:** `secure_delete` is on for every connection; Delete and Clear history… remove the text; `saveHistory` off writes nothing; no text in `stats.sqlite`, logs or the overlay's error messages. Tasks 1, 3 and 4.
3. **Cost:** a dictation adds one INSERT; the section reads pages of 200; nothing for Dictations while the window is closed. Tasks 3 and 4.
4. **Nothing lost from the menu and Settings:** Recent, Copy last dictation and Clear history… keep working; Open history is gone everywhere, the README included (spec §7).
5. **`dictionary.json` is safe:** drag, edit and remove change only what the author touched; a refused rule keeps the old one; the file's order of terms is the order on screen. Task 5.

## File structure

```
app/Sources/ShepitCore/
  DictationStore.swift       new: dictations.sqlite (Task 1)
  DictationPage.swift        new: day groups, row texts, "Kept for …" (Task 2)
  Paths.swift                historyFile goes (Task 3)
  History.swift              → FailedAudio.swift: WAV and FailedAudio stay, the history.log code goes (Task 3)
  Controller.swift           appendHistory gets the app (Task 3)
  AppSnapshot.swift          history: [DictationStore.Entry]; openHistory goes (Task 3)
  HomeModel.swift / MenuModel.swift   read store entries; Home shows the app (Task 3)
  Dictionary.swift           + the number of terms that fit the prompt (Task 5)
app/Sources/Shepit/
  AppHost.swift / AppHost+Window.swift   write, prune, clear, snapshot from the store (Task 3)
  Settings/SettingsSections.swift        Open history goes; hints (Task 3)
  Window/DictationsModel.swift           new: pages, open rows, delete and clear questions (Task 4)
  Window/DictationsView.swift            new: the section (Task 4)
  Window/DictionarySection.swift         rewritten (Task 5)
  Window/MainView.swift                  Dictations instead of the placeholder; Dictionary out of the Form (Tasks 4, 5)
```

---

### Task 1: The dictations store

- Tests first for `DictationStore` on a temporary file:
  - A new file gets the schema and a version; reopening keeps the data.
  - `add(text:app:at:)` stores time, app name and bundle ID (both optional), text and words (split on white space, as `Controller` counts them for statistics) and returns the id.
  - `page(before:limit:)` gives the newest entries, or the next older ones after a given entry, ordered by time and then id, so entries in one second neither repeat nor go missing across pages.
  - `delete(id)` removes one entry; `prune(before:)` removes older entries and returns how many; `clear()` deletes the file, and the next `add` starts a new one.
  - The text of a deleted or pruned entry is not left in the file. macOS's SQLite defaults to `secure_delete = FAST`, which leaves freed overflow pages as they were, so the store sets it `ON` in its schema statements (run on every open); the test uses long texts that reach overflow pages.
- Open lazily, as `MeetingStore` does. The app opens it at `Paths.dataDir/dictations.sqlite` in Task 3, as it does `meetings.sqlite`; no `Paths` entry.
- Commit `Shepit: dictations store`.

### Task 2: The Dictations section as data

- Tests first for `DictationPage` with a fixed calendar, time zone and now:
  - Day groups: Today, Yesterday, "13 November", "13 November 2025" for another year; entries keep their order inside a group; a page that ends mid-day continues the same group when the next page comes.
  - Row detail: "14:02 · Slack · 7 words", "14:02 · 1 word" without an app.
  - "Kept forever" for `historyDays` 0, "Kept for 1 day", "Kept for 30 days".
- Commit `Shepit: Dictations section as data`.

### Task 3: The app writes and reads the store

- `ControllerHost.appendHistory` takes the result's app (`recording.app`); `AppHost` adds to the store when `saveHistory` is on and shows today's "Could not write history" message on failure. `ControllerTests` check that the app is passed and that the write still comes before the paste.
- `AppSnapshot.history` holds store entries; Home shows "14:02 · Slack" (the time with the date when not today, then the app when there is one); Recent and Copy last dictation read the same entries. `HomeModelTests` and `MenuModelTests` updated.
- At launch `historyDays` prunes the store instead of `history.log`. Clear history… clears the store and the failed audio, as before.
- `history.log` is no longer written or read: `Paths.historyFile`, the `History` file code and its tests, `AppAction.openHistory` and Settings → History and privacy's Open history go. The Dictations placeholder keeps its text without the button until Task 4. `History.swift` becomes `FailedAudio.swift` with `WAV` and `FailedAudio`.
- The hint of Save history in Settings says "history", not `history.log`.
- Every database is opened in `databasesFolder` (default `~/.local/share/dictation`), one setting for all of them, read at launch; a row in Settings → History and privacy → Databases. The exception is written into the storage rule in `CLAUDE.md` (the author, 2026-11-16).
- Install; dictate into two apps; `sqlite3` on the real store shows two more rows with app names (counts and app names only); Home and Recent show them; `history.log` is unchanged.
- Commit `Shepit: dictations go to dictations.sqlite with their app`.

### Task 4: GATE — the Dictations section (with the author)

- `DictationsModel`: the first page when the section opens; the next when the last rows appear; the open (expanded) rows; a new dictation at the top while the section shows (from `refreshHistory`); Delete… and Clear history… with their questions (spec §5).
- `DictationsView` (mockup 4): day groups, rows with two lines and "…", the detail on the right, Copy (`copyText`), the right-click menu, the empty texts and the button to Settings → History and privacy, the bottom bar with "Kept for …" and Clear history….
- The placeholder goes; All dictations on Home opens the section, as now.
- Settle spec §11's question on paging a long `List` with a test home of a few thousand made-up entries (a short `sqlite3` script; the app started with `DICTATION_HOME` while the installed one is quit); write the answer in the commit message. Answer: one flat `List` of day titles and rows, each page adding its own lines (a grouped `Form` built every row and loaded all 5000 entries; day sections built every row to count them).
- A "Show" menu at the top limits the list to a period: Today, Last 7 days, Last month (the default), Last 3, 6 and 9 months, Last year, All history; pages of 200 stay inside it. Remembered like the window's section (the author, 2026-11-16, after scrolling through 5000 entries felt slow).
- Install; show the author the section next to mockup 4; change what the author asks before going on. The author's design remarks are set aside under "Minor ideas" in `docs/future-ideas.md`.
- Commit `Shepit: Dictations section`.

### Task 5: GATE — the Dictionary section (with the author)

- Tests first: `DictionaryRules` gives the number of terms that fit the prompt with a style prompt, without one, and with a term longer than the whole limit; `buildPrompt` uses the same count and keeps its tests.
- Chips in a small wrapping `Layout`; "+ add" turns into a field, Enter adds at the end (a term already there is ignored); × on hover removes; drag changes the order through `setTerms`; terms past the limit are dimmed, with the hint.
- Replace rows: two fields with → and −, sorted by what is heard; saved on Enter or when the focus leaves the row through `setRule(replacing:)`, which now refuses a heard phrase another rule has; a refusal puts the fields back and its reason shows in the window's banner at the top (as every refused write does), not under the row; the empty last row with +.
- Drop phrases as chips with "+ add" and ×, no order.
- Add word in the title row opens today's dialog with nothing selected: the window's button does not read the selection (`Paster.readSelection` would press ⌘C in Shepit itself).
- Read only when `dictionaryIsReadOnly`, as now. Shorter hints under each label (spec §6). The grouped `Form` stays: its sections are mockup 5's label and group; Add word sits in a bar above it, like Dictations' Show menu.
- Settle spec §11's questions on the chip layout with drag and on the Add word dialog; write the answers in the commit message.
- Install; show the author the section next to mockup 5; change what the author asks before going on. The author went on without changes (2026-11-16).
- Commit `Shepit: Dictionary section in the new look`.

### Task 6: Docs

- README: the Dictations section, Delete and Clear history…, `dictations.sqlite` under privacy and in the file list (and that `--purge` deletes it), "Lost text" pointing at Dictations, `history.log` from older versions can be deleted, the `saveHistory` row without `history.log`; a `databasesFolder` row, and that `--purge` keeps databases in a custom `databasesFolder` (as it keeps a custom `meetingsFolder`).
- `docs/manual-test-checklist.md`: D1–D9 from spec §9; D3 also goes through the Show menu's periods.
- The shell spec's Dictations and Dictionary rows get one line pointing to this spec.
- Commit `Docs: Dictations and Dictionary`.

### Task 7: GATE — the author's checks and reviews

- D1–D9 with the author on the installed app. D3 done (2026-11-16); the rest left open (`docs/future-ideas.md`).
- The end-of-branch reviews from the execution notes, and the whole diff against the Review focus list; fix what the author picks. The author picked points 1–4 of the thermo-nuclear review (commit b669249); the rest is in `docs/future-ideas.md`.
- Update `docs/future-ideas.md` and "Where things stand" in `CLAUDE.md`.
- Push the branch and open the pull request with a description (or, while `gh` is not logged in, merge locally); ask the author before merging into `main`. `gh` was not logged in: merged locally as one squashed commit, as the author agreed (2026-11-17).

---

## Open questions to raise when the task starts (not blockers)

- Task 3: whether `AppSnapshot.history` keeps only the newest entries Home and Recent need (as today), with the section reading its own pages from the store.
- Task 4: whether a click that opens a long text keeps the list's scroll position steady.
- Task 5: whether × on hover is enough for keyboard users, or a chip also needs Delete when focused. Still open for Task 7: the hidden × can be reached with Full Keyboard Access.
