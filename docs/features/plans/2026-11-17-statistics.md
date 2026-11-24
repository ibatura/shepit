# Main window, part 4 (Statistics): implementation plan

**Goal:** The Statistics section in mockup 7's look: a title row with Overview / Dictation / Meetings and a period menu shared with Dictations (plus Custom…), tiles and Words per day, and the new numbers: languages, speed over time, meetings by app and in detail, call offers. `stats.sqlite` keeps each meeting's app from now on.

**Architecture:** Everything that counts is in `ShepitCore` and unit-tested: a shared `Period` (the presets of Dictations' Show menu) and a `StatsPeriod` (a preset or a custom range) with the range, the previous range and the bucket unit; new pure `Stats` functions over plain rows; `StatsDatabase` with the app column, added through numbered upgrades in `SQLiteFile`. The app gets a `StatisticsModel` that reads the period's rows once per change, and a `StatisticsView` with one view per tab, replacing `StatisticsSection`.

**Spec:** `docs/features/specs/2026-11-17-statistics-design.md` ("the spec"; section numbers refer to it). Look: `docs/features/specs/2026-11-11-visual-style/` (`visual-style.md` §5.6; `mockups.html` screen 7).

**Branch:** `statistics`, cut from `main`. When it is ready: push it and open a pull request with a description, merged as one squashed commit; while `gh` is not logged in, merge it into `main` locally. Ask the author before merging either way.

## Execution notes

- **Style: Ponytail (full)** for every task (`~/.claude/skills/ponytail`): the smallest complete change, a test for every non-trivial branch, no options nobody asked for.
- **Review per task:** the task's diff is checked against the Ponytail rules; Tasks 2, 3 and 4 also get `/code-review` on their diff.
- **Review at the end (Task 8):** the author runs `/thermo-nuclear-code-quality-review` on the branch (only the author can start it); then `/code-review` and `/security-review` on the whole branch. Findings are shown to the author as a list; the author picks what to change.
- One task at a time, a commit per task with a short message, `make test` green after each (543 tests on 2026-11-17).
- Tests first for everything in `ShepitCore`. Tests use databases in temporary folders, never `~/.local/share/dictation`.
- The author's own `~/.config/dictation/settings.json` is not changed by code or tests. The author's statistics are private: when checking the real store, report counts only.
- Try a change with `scripts/install.sh`. From Task 4 on, look at each view next to mockup 7 (light and dark) before the commit; a scratch render test (an `NSHostingView` written to a PNG in the scratchpad, deleted before the commit) is the quick way.
- **Author gates: Task 4 (Overview and the period), Task 6 (Dictation and Meetings views) and Task 8.**

## Global constraints

- No text in `stats.sqlite`: the new column holds `CallApp`'s raw value (`Teams`, `Zoom`, `Meet`, as the `offers` table has) or nothing.
- Nothing is written with `collectStats` off; Clear statistics… deletes the file, as today.
- The section reads the database only while it is shown, and once per change of period (and on appear), not on every redraw.
- An upgrade of an older `stats.sqlite` keeps every row; a failed upgrade changes nothing and is tried again on the next open.
- Standard SwiftUI controls, Swift Charts and SF Symbols; English labels in sentence case; texts as in the spec and the mockup. Colour never carries meaning alone (labels, legends, "▲ 12%" text).
- No network, no new permission, no new setting. The view and the period are window state in `UserDefaults`, like Dictations' period.

## Review focus

1. **Numbers are right:** every period's range and previous range (DST days, month ends, a custom range of one day), the buckets, and each aggregation against hand-made rows. The Overview tiles match the old section's for the same days. Tasks 1, 3.
2. **The upgrade is safe:** an older file keeps its rows and gets the column; a new file has it; a failure leaves the file as it was. Task 2.
3. **Privacy:** only the app's raw value is added; nothing with `collectStats` off; nothing read while the section isn't shown. Tasks 2, 4.
4. **Cost:** one read of dictations, meetings and offers per period change (two with the previous period); charts fed from the model, not from `body`. Task 4.
5. **Nothing lost:** every number of today's section is still somewhere (Overview or Dictation), the hover tooltip of Words per day included. Tasks 4, 5.

## File structure

```
app/Sources/ShepitCore/
  Period.swift               new: Period (from DictationPage.Period) and StatsPeriod: range, previous, buckets, titles (Task 1)
  DictationPage.swift        Period moves out (Task 1)
  SQLiteFile.swift           numbered upgrades after the schema (Task 2)
  StatsDatabase.swift        meetings.app, the upgrade to version 2, offers index (Task 2)
  MeetingSession.swift       MeetingRecord.app; the session passes its app (Task 2)
  Stats.swift                StatsPeriod and range/previous/bucketUnit go to Period.swift; new aggregations (Tasks 1, 3)
app/Sources/Shepit/
  Window/StatisticsModel.swift       new: view, period, rows for the period and the previous one (Task 4)
  Window/StatisticsView.swift        new: title row, view switch, period menu, Custom… popover, states (Task 4)
  Window/StatisticsOverview.swift    new: tiles, Words per day (Task 4)
  Window/StatisticsDictation.swift   new: speed, apps, heatmap, languages, dictionary, failures (Task 5)
  Window/StatisticsMeetings.swift    new: tiles, by app, length, speaker detection, offers (Task 6)
  Window/StatisticsSection.swift     goes (Task 4; its charts move into the new files)
  Window/DictationsModel.swift / DictationsView.swift   use the shared Period (Task 1)
  Window/WindowActions.swift         statistics and meetingStatistics go: the model reads StatsDatabase (Task 4)
  AppHost.swift / MainWindow.swift / MainView.swift     the model wired like DictationsModel (Task 4)
```

---

### Task 1: The shared period

- Tests first, with a fixed calendar (Europe/Kyiv) and now:
  - `Period` keeps Dictations' titles, raw values and `since` (DictationPageTests' period test moves to a `PeriodTests`).
  - `StatsPeriod.preset(_)` and `.custom(from:through:)`: `range(now:)` from the start of the first day to now (custom: from the start of `from` to the end of `through`); nil for All history.
  - `previous(now:)`: the same span right before, up to the same moment: Today against yesterday until this time; Last 7 days against the 7 days before; Last month against the month before; a custom range against as many days before it; across a DST change and a month end; nil for All history.
  - `bucket(now:)`: hour for Today or a one-day custom range, day up to 31 days, week up to 26 weeks, month beyond (All history: month).
  - `title`: the preset's title; a custom range "12 Nov – 16 Nov 2026", "16 Nov 2026" for one day, the years when they differ.
- `DictationPage.Period` moves to `Period.swift`; Dictations' model and view use it, with no change on screen. `StatsPeriod` of today (day, week, month, year, all), `Stats.range`, `Stats.previous` and `Stats.bucketUnit` go; `Stats.wordsPerBucket` takes the bucket unit. The old section keeps working on the new period until Task 4 replaces it.
- Commit `Shepit: one period for Dictations and Statistics`.

### Task 2: stats.sqlite keeps the meeting's app

- Tests first for `SQLiteFile` upgrades: a file at version 1 runs upgrade 2 once and is at 2; a new file runs the schema and every upgrade; an upgrade that fails rolls back, leaves the version, and the next open tries again; reopening runs nothing.
- `SQLiteFile(file:schema:upgrades:)`: after the schema, each upgrade above `schema_version` runs in one transaction with the version bump.
- `StatsDatabase`: upgrade 2 adds `meetings.app TEXT`; `CREATE INDEX IF NOT EXISTS offers_time ON offers (time)` in the schema. `MeetingRecord.app: CallApp?`, written and read back (an unknown value reads as nil). Tests: a version-1 file with two meetings keeps them, with no app; a new meeting keeps its app.
- `MeetingSession` passes `config.app` into the record; `MeetingSessionTests` check it.
- Commit `Shepit: stats.sqlite keeps each meeting's app`.

### Task 3: The new numbers

- Tests first for each new `Stats` function, with small hand-made rows:
  - `languages(_:)`: dictations per detected language, most used first, with names ("uk+en" as "Ukrainian + English"). No mismatch: with a language chosen the engines report the chosen one, so it would always be 0% (spec §5.2).
  - `speedOverTime(_:unit:)`: per engine and model, per bucket, the median wait per 10 s of audio; buckets with fewer than 3 dictations of that engine left out; audio of 0 s ignored.
  - `meetingsByApp(_:)`: count and hours per app, nil app as Unknown, in a fixed order (Teams, Zoom, Google Meet, Unknown) with empty apps left out.
  - `yourShare(_:)`: your words ÷ all words; nil with no words.
  - `peoplePerMeeting(_:)`: the average of the speakers found, meetings with none left out.
  - `lengths(_:)`: average, longest, and counts under 15 min, 15–30, 30–60, over 60 (edges: 15 min exactly is 15–30).
  - `speakerDetection(_:)`: meetings where it ran, its median seconds, failed chunks in total and in how many meetings.
  - `offers(_:)`: counts per outcome, in total and per app.
  - The failures of `quality` get counts next to the shares.
- Commit `Shepit: statistics for languages, speed over time, meetings and offers`.

### Task 4: GATE — Overview and the period (with the author)

- `StatisticsModel` (`@Observable`, `@MainActor`): the view (Overview, Dictation, Meetings) and the period, both remembered (`statisticsView`, `statisticsPeriod`, a custom range as two dates); the rows of dictations, meetings and offers for the period and for the previous one, read from `StatsDatabase` on appear and on every change of period, not in `body`. Tests in `ShepitTests` with a temporary database: a period change reads again; the choice survives a new model; a custom range is kept.
- `StatisticsView`: the title row (Statistics, the segmented view switch, the period menu with Custom… under a separator), the Custom… popover (start and end in graphical calendars, Show; the end not before the start or after today), the `collectStats`-off note with its button to Settings → History and privacy, and the empty texts (spec §5.4).
- Overview (spec §5.1): the four tiles with their changes and "at N wpm" linking to the typing-speed setting; Words per day by the period's bucket, with today's stacked bars, colours and hover tooltip; the time-saved line.
- `StatisticsSection` goes; `WindowActions.statistics` and `.meetingStatistics` go; `AppHost` gives the model `stats` and `settings`, wired through `MainWindow` and `MainView` like `DictationsModel`.
- Settle spec §11's questions on the custom popover and on one fetch for all views; write the answers in the commit message.
- Install; show the author Overview next to mockup 7 and the period menu with Custom…; change what the author asks before going on.
- Commit `Shepit: Statistics overview and period`.

### Task 5: The Dictation view

- Spec §5.2: the speed table of today and Speed over time (a line per engine and model, by the period's bucket, with a legend); Pasted into, When you dictate, Dictionary and Failures moved from today's section in the new style; Languages (shares).
- Settle spec §11's question on many speed lines (all, or the most used 4); write the answer in the commit message.
- Commit `Shepit: Statistics dictation view`.

### Task 6: GATE — the Meetings view (with the author)

- Spec §5.3: the tiles (Meetings, Hours, Your share of words, People per meeting) with their changes; By app (bars with count and hours); Length; Speaker detection; Call offers (outcomes in total and per app).
- Install; show the author the Dictation and Meetings views next to the mockup's style; change what the author asks before going on.
- Commit `Shepit: Statistics meetings view`.

### Task 7: Docs

- README: the Statistics section (Overview, Dictation, Meetings; the period menu and Custom…), and under privacy that a meeting's row in `stats.sqlite` now keeps its app.
- `docs/manual-test-checklist.md`: S1–S8 from spec §9.
- `05-statistics.md` gets one line pointing to the spec for its §2; the shell spec's Statistics row too.
- Commit `Docs: Statistics`.

### Task 8: GATE — the author's checks and reviews

- S1–S8 with the author on the installed app.
- The end-of-branch reviews from the execution notes, and the whole diff against the Review focus list; fix what the author picks.
- Update `docs/future-ideas.md` and "Where things stand" in `CLAUDE.md`.
- Push the branch and open the pull request with a description (or, while `gh` is not logged in, merge locally); ask the author before merging into `main`.

---

## Open questions to raise when the task starts (not blockers)

- Task 2: whether `MeetingStore` (meetings.sqlite) moves to numbered upgrades too, or stays on `CREATE … IF NOT EXISTS` until it needs a column.
- Task 4: whether the Custom… popover remembers the last custom range when another period is picked in between.
- Task 6: whether Call offers belongs in Meetings or in its own small view, if the Meetings view gets long.
