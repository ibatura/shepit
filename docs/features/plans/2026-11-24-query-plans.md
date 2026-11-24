# Every query on an index (query plans): implementation plan

**Goal:**
- Every query of `meetings.sqlite` that reads part of a table finds it through an index.
- The scan of every line for old meetings' words goes, with the fill it served.
- May also be in and the forgetting of old unnamed voices no longer run on the main thread.

**Architecture:**
- **Upgrade 3 of `meetings.sqlite`:** a third entry in `MeetingStore.upgrades` adds `meetings_start` and `people_person`. `SQLiteFile` already runs a numbered upgrade once, in a transaction, and an older Shepit skips a version it doesn't know.
- **The fill goes:** `MeetingStore.meetingsWithoutWords`, `fillWords`, `PeopleModel.fillWords` and `PeopleView`'s `.task` are removed.
- **Two reads on connections of their own:** two static async methods sit beside `MeetingStore.prints(in:except:)`, each opening a `MeetingStore` of its own in a detached task.
  - `suggestedVoices(in:for:)`: `PeopleModel.suggest()` awaits it, and the prints when its copy is out of date, in one task that a new choice or reload cancels.
  - `forgetUnnamedVoices(in:before:)`: `AppHost.forgetOldVoices()` starts it, one at a time.
- **A rule for new queries:** one line in the task reviewer's brief in `docs/process.md`.

**Spec:** `docs/features/specs/2026-11-24-query-plans-design.md` ("the spec"; section numbers refer to it), approved by the author on 2026-11-24.

**Branch:** `query-plans`. It holds the spec's commits.

## Execution notes

**This part's test data.**
- The plans and the times in the spec came from an empty file made from the code's schema, and from a synthetic year (800 meetings, 132,000 lines, 99,000 samples).
- Both were made by a script in the scratchpad, which is not committed.
- The author's files are read only with `sqlite3 -readonly`, and only for counts, the version and index names.

**Its own rule from the start.** Every query this branch adds or changes gets `EXPLAIN QUERY PLAN` (§7.4). In this branch that means only the plan tests' own queries; no store query changes its SQL.

**One gate,** Task 5: the author checks the installed build. Tasks 1–4 change nothing the author can see beyond speed.

## Global constraints

- **No change to what the stores return:** the same rows, in the same order, for every query that stays.
- **No new setting, no network, no new permission.**
- **Deleted voice samples are overwritten on every connection.** The schema's `PRAGMA secure_delete = ON` runs on every open, so a connection of its own has it too.
- **No new index beyond the two of §7.1**, and none dropped (§6.4).

## Review focus

1. **Upgrade 3 on a real file** (Tasks 1 and 4):
   - a version-2 file gets both indexes and keeps its rows;
   - a version-3 file opened by 0.4.0 still works;
   - the forget's own connection may be the first to open the file at launch and run the upgrade, while the main connection opens it a moment later (`SQLiteFile` reads the version again under the write lock).
2. **May also be in shows only a current read** (Task 3):
   - a read that returns after another person is chosen, after Remember voices is turned off, or after a reload started a newer read, is never shown;
   - a reload for the same person keeps the suggestions shown until the new read replaces them.
3. **Two connections writing** (Task 4): the forget's delete and a main-thread write (naming people after a meeting is listed, a rename) wait for each other within the 5 s busy timeout rather than fail.
4. **Nothing still calls the fill** (Task 2): no caller, test or doc of `meetingsWithoutWords`, `fillWords` or `wordsFilled` is left.

## File structure

```
app/Sources/ShepitCore/
  MeetingStore.swift          upgrade 3: meetings_start, people_person (Task 1)
  MeetingStore+People.swift   meetingsWithoutWords and fillWords go (Task 2)
  MeetingStore+Voices.swift   suggestedVoices(in:for:), forgetUnnamedVoices(in:before:) (Tasks 3, 4)
app/Sources/Shepit/
  Window/PeopleModel.swift    fillWords goes (Task 2); suggest() reads off the main thread, readPrints() goes (Task 3)
  Window/PeopleView.swift     its .task goes (Task 2)
  AppHost.swift               var forgetting: Task<Void, Never>? (Task 4)
  AppHost+Meetings.swift      forgetOldVoices() off the main thread (Task 4)
app/Tests/ShepitCoreTests/
  MeetingStoreTests.swift     the upgrade and the two plans (Task 1)
  MeetingVoicesTests.swift    the fill's part goes (Task 2); the reads of their own (Tasks 3, 4)
app/Tests/ShepitTests/
  PeopleModelTests.swift      the fill's test goes (Task 2); suggestions read off the main thread (Task 3)
docs/process.md               the task reviewer's line (Task 6)
```

---

### Task 1: Upgrade 3, the two indexes (spec §7.1)

- **Tests first** in `MeetingStoreTests`:
  - **`version2GetsTheIndexesAndKeepsItsRows`.**
    - Make a version-2 file: `SQLiteFile(file:schema: MeetingStore.schema, upgrades: [MeetingStore.upgrades[0]])`, then one meeting, one person and one line.
    - Open it with `MeetingStore(file:)` and read a meeting, which opens the file.
    - `schema_version` is 3.
    - `sqlite_master` has `meetings_start` and `people_person`.
    - The meeting, its person and its line read back as written.
  - **`theListAndAPersonsMeetingsUseTheirIndexes`.** On a store with one meeting, `store.sqlite.rows("EXPLAIN QUERY PLAN …")` reads column 3. The SQL is the same as `meetings(limit:)` and `meetings(of:)` build:
    - the list's plan says `USING INDEX meetings_start` and has no `TEMP B-TREE`;
    - a person's meetings search `people_person`.
- **The change.** `MeetingStore.upgrades` gets a second string, `CREATE INDEX meetings_start ON meetings (start); CREATE INDEX people_person ON people (person)`. Its doc comment says version 3 and points to query plans design §7.1.
- Commit `Meetings store: indexes on meetings (start) and people (person), version 3`.

### Task 2: The fill of old meetings' words goes (spec §7.2)

- **Remove:**
  - `meetingsWithoutWords` and `fillWords` from `MeetingStore+People.swift`;
  - `PeopleModel.fillWords` and `wordsFilled`;
  - the `.task { await model.fillWords() }` in `PeopleView`.
- **Tests:**
  - remove `wordsOfOlderMeetingsAreFilledOnce` in `PeopleModelTests`;
  - remove the block from "A meeting listed before words were kept" to the end of its test in `MeetingVoicesTests`. Its first half, presences' words, seconds and meeting words, stays.
- **Docs:** grep `docs/`, the README and the code comments for "fill" and the two method names, and drop what describes the fill (the voices design keeps its history as written).
- Commit `People: the fill of old meetings' words goes, with its scan of every line`.

### Task 3: May also be in off the main thread (spec §7.5)

- **Tests first:**
  - **`MeetingVoicesTests.suggestedVoicesReadOnAConnectionOfTheirOwn`:** `MeetingStore.suggestedVoices(in:for:)` gives what `store.suggestedVoices(for:)` gives, on the store of `suggestedVoicesLeaveOutThePersonsMeetingsNamedPeopleAndDeclinedOnes`.
  - **`PeopleModelTests.suggestionsForTheChosenPersonWhileRememberVoicesIsOn`** is changed:
    - after choosing Olena again, `await model.reading?.value`, then the suggestion is there;
    - the `reading == nil` check for "read once" goes, since the unnamed voices are read every time.
  - **A new test:** with Remember voices on, choose Olena, keep `model.reading`, and set `selection = nil` before awaiting it. After `await` the kept task, `suggestions` is empty: the cancelled read showed nothing.
- **The changes:**
  - `MeetingStore.suggestedVoices(in file: URL, for person: Int) async throws` reads on a `MeetingStore(file:)` of its own in `Task.detached`, as `prints(in:except:)` does.
  - **`PeopleModel.suggest()`:**
    - It cancels `reading`.
    - Without a chosen person other than You, or with Remember voices off, it empties `suggestions`. Otherwise it empties them only when the person differs from the one they were read for, kept in an ignored `suggestedFor`.
    - It starts `reading = Task { … }`. That task awaits `suggestedVoices(in:for:)`, then, when there are unnamed voices and `prints` is not at the store's version, awaits `prints(in:)` and keeps it with the version read at the start.
    - After each `await`, if `Task.isCancelled`, it returns without touching anything.
    - At the end it sets `suggestions` as today (`Voices.suggestions`, then `PeoplePage.suggestions`), `suggestedFor`, and `reading = nil`.
    - A failed read logs and empties `suggestions`, as today.
  - `readPrints()` goes; its job is in this task.
- Commit `People: May also be in is read off the main thread`.

### Task 4: Forgetting old unnamed voices off the main thread (spec §7.5)

- **Test first:** `MeetingVoicesTests.forgetOnAConnectionOfItsOwnOverwritesTheSamples`. It is `deletedVoicesLeaveNoTraceInTheFile`'s forget step, through `try await MeetingStore.forgetUnnamedVoices(in:before:)`. The unnamed sample is gone from `unnamedVoices`, and its bytes are not in the file.
- **The changes:**
  - `MeetingStore.forgetUnnamedVoices(in file: URL, before date: Date) async throws`, on a `MeetingStore(file:)` of its own in `Task.detached`.
  - `AppHost` gets `var forgetting: Task<Void, Never>?`.
  - **`forgetOldVoices()`:**
    - it returns when `forgetting` isn't nil;
    - otherwise it takes the file and the date on the main thread and starts `forgetting = Task { … }`;
    - the task awaits the delete, logs a failure as today, and sets `forgetting = nil`.
- **No version bump:** the main connection's `version` doesn't see the delete (spec §7.5). Prints and People's counts read only named samples, which the forget leaves.
- Commit `Voices: old unnamed voices are forgotten off the main thread`.

### Task 5: GATE: the installed build (spec §9, Q1–Q3, with the author)

- Run `make test`, then ask before installing: it restarts Shepit, and a transcript may be running. Then install.
- **Q1.** After first launch, read the author's `meetings.sqlite` with `sqlite3 -readonly`. Report the version and the index names only: version 3, `meetings_start`, `people_person`.
- **Q2 and Q3 with the author:**
  - Home's recent meetings, Meetings and People, with a person, Who talked how much and May also be in;
  - after the next meeting is listed, dictation by hotkey at once.
- Fix the author's remarks in this task.

### Task 6: Docs and version

- **`docs/process.md`:** the task reviewer's line of spec §7.4.
- **`docs/architecture.md`:**
  - `meetings.sqlite` is version 3;
  - May also be in and the forget read on connections of their own, as the prints do.
- **`docs/manual-test-checklist.md`:** a "Query plans" section with Q1–Q3 and their results from Task 5.
- **`docs/future-ideas.md`:**
  - item 13 built on `query-plans`;
  - "Next" without it;
  - "Query plans: left open": `keys(of:in:)` (spec §10), `summaries` on the main thread, `lines (meeting, current)` not added.
- **`CLAUDE.md`:** "Now", and the test count.
- **README:** only if it names `meetings.sqlite`'s version or the fill.
- **Version:** agreed with the author. I propose 0.4.1, since nothing new shows. It goes in `CFBundleShortVersionString` and `docs/releases/<version>.md`.
- Commit `Docs: query plans; version <version>`.

### Task 7: End-of-branch reviews and the pull request

- Follow `docs/process.md` §5.3–§6:
  - Claude runs the code reviewer and the security reviewer at the same time.
  - Claude gives its opinion on each finding, the author picks, and Claude fixes what was picked.
  - Then the author runs the thermo-nuclear review.
  - Each manual check is marked.
  - Claude asks "open the PR?".

## Open questions to raise when the task starts (not blockers)

- **Task 3:** if `PeopleView` shows May also be in with a heading even while `suggestions` is empty, the block blinks when a new person is chosen. If so, show the author before changing the view.
- **Task 6:** the version (0.4.1 proposed).

## Progress

- 2026-11-24: the spec approved (c5440a9).
