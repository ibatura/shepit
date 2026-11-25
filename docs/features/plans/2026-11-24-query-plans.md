# Every query on an index (query plans): implementation plan

**Goal:**
- Every query of `meetings.sqlite` that reads part of a table finds it through an index.
- The scan of every line for old meetings' words goes, with the fill it served.
- May also be in and the forgetting of old unnamed voices no longer run on the main thread.

**Architecture:**
- **Upgrade 3 of `meetings.sqlite`:** a second entry in `MeetingStore.upgrades` adds `meetings_start` and `people_person`. `SQLiteFile` already runs a numbered upgrade once, under `BEGIN IMMEDIATE`, and an older Shepit skips a version it doesn't know.
- **The fill goes:** `MeetingStore.meetingsWithoutWords`, `fillWords`, `PeopleModel.fillWords` and `PeopleView`'s `.task` are removed.
- **Transactions take the write lock first:** the outermost `SQLiteFile.transaction` begins with `BEGIN IMMEDIATE` instead of a deferred `SAVEPOINT`.
  - The problem: a deferred transaction that read first gets `SQLITE_BUSY` at once, without the busy timeout, when another connection holds a write.
  - The second writing connection of §7.5 makes this reachable.
- **Two reads on connections of their own:** two static async methods sit beside `MeetingStore.prints(in:except:)`.
  - `suggestedVoices(in:for:)`: `PeopleModel.suggest()` runs one such read at a time. When it ends, it checks the choice and the store, and reads again if either moved. The prints stay a read of their own (`readPrints()`, as today).
  - `forgetUnnamedVoices(in:before:)`: `AppHost.forgetOldVoices()` starts it, one at a time.
- **A rule for new queries:** one line in the task reviewer's brief in `docs/process.md`, committed with Task 1 so the reviewers of this branch get it.

**Spec:** `docs/features/specs/2026-11-24-query-plans-design.md` ("the spec"; section numbers refer to it), approved by the author on 2026-11-24.

**Branch:** `query-plans`. It holds the spec's commits.

## Execution notes

**This part's test data.**
- The plans and the times in the spec came from an empty file made from the code's schema, and from a synthetic year (800 meetings, 132,000 lines, 99,000 samples).
- Both were made by a script in the scratchpad, which is not committed.
- The author's files are read only with `sqlite3 -readonly`, and only for counts, the version and index names.

**Its own rule.** From Task 1 on, every query a task adds or changes gets `EXPLAIN QUERY PLAN` (§7.4). In this branch that means only the plan test's own queries; no store query changes its SQL.

**Task 2 is risky.** It changes `SQLiteFile.transaction`, which is shared code. Only `MeetingStore` calls it: `StatsDatabase` and `DictationStore` don't. Its reviewer reads every caller of `transaction`.

**One gate,** Task 6: the author checks the installed build. Tasks 1–4 change nothing the author can see beyond speed.

## Global constraints

- **No change to what the stores return:** the same rows, in the same order, for every query that stays.
- **No new setting, no network, no new permission.**
- **Deleted voice samples are overwritten on every connection.** The schema's `PRAGMA secure_delete = ON` runs on every open, so a connection of its own has it too.
- **No new index beyond the two of §7.1**, and none dropped (§6.4).

## Review focus

1. **Two connections writing** (Tasks 2 and 4):
   - a main-thread transaction that reads, then writes, waits for the forget's delete within the 5 s busy timeout instead of failing;
   - the forget's delete waits for a main-thread transaction;
   - a nested `transaction` (`change` inside `recognise`, `remove` inside `remove(_:trash:)`) still uses a savepoint and rolls back only its part.
2. **Upgrade 3 on a real file** (Tasks 1 and 4):
   - a version-2 file gets both indexes and keeps its rows;
   - a version-3 file opened by 0.4.0 still works;
   - the forget's own connection may be the first to open the file at launch and run the upgrade (`SQLiteFile` reads the version again under the write lock).
3. **May also be in shows only a current read** (Task 3):
   - a read that ends after another person is chosen, after the store changed, or after Remember voices was turned off, is not shown, and a read for what is chosen now follows;
   - choosing a person, or a change the section made itself (Name them, Delete voice…, Rename, Merge into…), empties the suggestions at once;
   - a plain reload (the window becomes active) keeps them until the new read replaces them;
   - the prints are read once per version, as today.
4. **Nothing still calls the fill** (Task 1): no caller or test of `meetingsWithoutWords`, `fillWords` or `wordsFilled` is left.

## File structure

```
app/Sources/ShepitCore/
  MeetingStore.swift          upgrade 3: meetings_start, people_person (Task 1)
  MeetingStore+People.swift   meetingsWithoutWords and fillWords go (Task 1)
  SQLiteFile.swift            the outermost transaction begins IMMEDIATE (Task 2)
  MeetingStore+Voices.swift   suggestedVoices(in:for:) (Task 3), forgetUnnamedVoices(in:before:) (Task 4)
app/Sources/Shepit/
  Window/PeopleModel.swift    fillWords goes (Task 1); suggest() reads off the main thread (Task 3)
  Window/PeopleView.swift     its .task goes (Task 1)
  AppHost.swift               private var forgettingVoices = false (Task 4)
  AppHost+Meetings.swift      forgetOldVoices() off the main thread (Task 4)
app/Tests/ShepitCoreTests/
  MeetingStoreTests.swift     the upgrade and the two plans (Task 1)
  MeetingVoicesTests.swift    the fill's part goes (Task 1); the forget through its own connection (Task 4)
  SQLiteFileTests.swift       a transaction waits for another connection's write (Task 2)
app/Tests/ShepitTests/
  PeopleModelTests.swift      the fill's test goes (Task 1); suggestions read off the main thread (Task 3)
docs/process.md               the task reviewer's line (Task 1)
```

---

### Task 1: Upgrade 3 with the two indexes; the fill goes; the review rule (spec §7.1, §7.2, §7.4)

- **Test first,** in `MeetingStoreTests`: `version2GetsTheIndexesAndItsPlansUseThem`.
  - Make a version-2 file with `SQLiteFile(file:, schema: MeetingStore.schema, upgrades: Array(MeetingStore.upgrades.dropLast()), functions: ["name_key": Names.key])`. Upgrade 2 calls `name_key`, which SQLite refuses at prepare time without the function. Then `run` one meeting, one `people` row with `person = 1` and one line, which creates the file.
  - Open it with `MeetingStore(file:)` and read the meeting back, which opens the file and runs upgrade 3.
  - `schema_version` is 3.
  - `sqlite_master` has `meetings_start` and `people_person`.
  - The meeting, its person and its line read back as written.
  - **The plans,** read through `store.sqlite.rows("EXPLAIN QUERY PLAN …")`, column 3:
    - `SELECT id, path, title, app, start, duration, you FROM meetings ORDER BY start DESC, id DESC LIMIT ?` uses `meetings_start` with no `TEMP B-TREE`;
    - `… FROM meetings WHERE id IN (SELECT meeting FROM people WHERE person = ?) ORDER BY start DESC, id DESC` searches `people_person`.
- **The change.** `MeetingStore.upgrades` gets a second string, `CREATE INDEX meetings_start ON meetings (start); CREATE INDEX people_person ON people (person)`. Its doc comment says version 3 and points to query plans design §7.1.
- **The fill goes:**
  - `meetingsWithoutWords` and `fillWords` in `MeetingStore+People.swift`;
  - `PeopleModel.fillWords` and `wordsFilled`;
  - the `.task { await model.fillWords() }` in `PeopleView`;
  - `PeopleModelTests.wordsOfOlderMeetingsAreFilledOnce`.
  - In `MeetingVoicesTests`, `presencesCountWordsAndTalkTimeAndOlderMeetingsGetTheirWords` loses the block from "A meeting listed before words were kept" to its end, and becomes `presencesCountWordsAndTalkTime`. `MeetingPage.pair` stays: `MeetingPage` uses it three times.
  - No live doc names the fill. Only the voices spec and plan do, as history, and they stay.
- **`docs/process.md` §7,** the task reviewer's brief: the line of spec §7.4.
- Commit `Meetings store: indexes on meetings (start) and people (person), version 3; the fill of old words goes`.

### Task 2: A transaction takes the write lock first (risky)

- **Test first,** in `SQLiteFileTests`: `aTransactionWaitsForAnotherConnectionsWrite`.
  - A second connection, opened with `sqlite3_open` (as `DictationStoreTests` does), runs `BEGIN IMMEDIATE` and an insert.
  - It commits from `DispatchQueue.global().asyncAfter` 0.2 s later.
  - The file's `transaction { rows(…); run(insert) }` then succeeds and both rows are there. Today it throws "database is locked" at once.
- **The change.** In `SQLiteFile.transaction`:
  - when the connection is in autocommit (`sqlite3_get_autocommit`; no file open yet counts as autocommit), it begins with `BEGIN IMMEDIATE` and ends with `COMMIT`, or `ROLLBACK` on a throw;
  - inside another transaction it keeps `SAVEPOINT change`, `RELEASE` and `ROLLBACK TO`.

  A one-line comment says why: a deferred transaction that read first gets `SQLITE_BUSY` with no wait.
- **Read every caller of `transaction`,** in the three stores. The existing tests of a failed change (`aFailedChangeLeavesTheDatabaseAsItWas`, and the notes that are put back) must stay green.
- **The spec:** one line in §7.5, "added after the plan review", says a transaction takes the write lock first, which is what makes the two connections wait for each other.
- Commit `SQLite: a transaction takes the write lock first, so it waits for another connection's write`.

### Task 3: May also be in off the main thread (spec §7.5)

- **Tests first,** in `PeopleModelTests`:
  - **A helper** `settle(_ model:)` awaits `model.suggesting` and `model.reading` until both are nil.
  - **`suggestionsForTheChosenPersonWhileRememberVoicesIsOn`** is changed:
    - after `reload()` with Remember voices on, the suggestions are empty until `await settle(model)`; then they are `["Person 1"]`;
    - choosing Olena again empties them at once. After `await model.suggesting?.value`, they are `["Person 1"]` and `model.reading` is nil: the prints were not read again;
    - after `name(…)`, they are empty at once, and still empty after `settle`.
  - **New: `aReadThatEndsAfterTheChoiceChangedShowsNothing`.** Choose Olena with Remember voices on, set `selection = nil` before the read ends, then `settle`. The suggestions are empty.
- **The change** in `MeetingStore+Voices.swift`: `public static func suggestedVoices(in file: URL, for person: Int) async throws -> [Int: [String: [VoiceSample]]]`, which is `Task.detached { try MeetingStore(file: file).suggestedVoices(for: person) }.value`, as `prints(in:except:)` is.
- **The change** in `PeopleModel`:
  - **`selection`'s `didSet`** empties `suggestions` before `suggest()`. So does `apply`, before its `reload()`.
  - **`suggest()`:**
    - Without a chosen person other than You, or with Remember voices off, it empties `suggestions` and returns.
    - While `suggesting` isn't nil, it returns: the read under way checks the choice when it ends.
    - Otherwise it takes the person, `store.version` and `store.file`, and starts `suggesting = Task { … }`.
  - **The task:**
    - It awaits `suggestedVoices(in:for:)`, logging a failure as today.
    - It sets `suggesting = nil`.
    - If the chosen person, `store.version` or Remember voices changed meanwhile, it calls `suggest()` and returns.
    - Otherwise it goes on as today's `suggest()`: no unnamed voices, or prints not at this version, gives no suggestions and, when there are unnamed voices, calls `readPrints()`. Otherwise `Voices.suggestions`, then `PeoplePage.suggestions`.
  - `readPrints()` stays as it is: one prints read at a time, kept at the version it started with, and then `suggest()`.
- Commit `People: May also be in is read off the main thread`.

### Task 4: Forgetting old unnamed voices off the main thread (spec §7.5)

- **Test first:** `MeetingVoicesTests.deletedVoicesLeaveNoTraceInTheFile` becomes `async`, and its forget step becomes `try await MeetingStore.forgetUnnamedVoices(in: dir.appending(path: "meetings.sqlite"), before: start + 30 * 86_400)`.
  - Its byte checks then prove that a connection of its own overwrites the samples (`secure_delete` from the schema). This replaces the spec's `PRAGMA secure_delete` check.
  - The sync method stays, for `unnamedVoicesGoAfterThirtyDays` and for the static one.
- **The changes:**
  - `public static func forgetUnnamedVoices(in file: URL, before date: Date) async throws`, which is `Task.detached { try MeetingStore(file: file).forgetUnnamedVoices(before: date) }.value`.
  - `AppHost` gets `private var forgettingVoices = false`.
  - **`forgetOldVoices()`:**
    - it returns when `forgettingVoices` is set;
    - otherwise it sets the flag, takes the file and the date, and starts a `Task` on the main actor;
    - that task awaits the static method, logs a failure as today, and clears the flag.
- **No version bump:** the main connection's `version` doesn't see the delete (spec §7.5). Prints and People's counts read only named samples, which the forget leaves.
- Commit `Voices: old unnamed voices are forgotten off the main thread`.

### Task 5: Docs and version

- **`docs/architecture.md`:**
  - line 18: `meetings.sqlite` (version 3);
  - line 90: May also be in and the forget read on connections of their own, as the prints do;
  - `SQLiteFile`'s transaction takes the write lock first.
- **`docs/manual-test-checklist.md`:** a "Query plans" section with Q1–Q3 of spec §9.
- **`docs/future-ideas.md`:**
  - item 13 built on `query-plans`;
  - "Next" without it;
  - "Query plans: left open":
    - `keys(of:in:)` (spec §10);
    - `summaries` on the main thread;
    - `lines (meeting, current)` not added;
    - a main-thread write still waits for a long read on another connection (the prints, May also be in), now only when the two meet;
    - the plan tests copy the SQL of two queries.
- **`CLAUDE.md`:** "Now", and the test count.
- **README** and **`examples/settings.json`:** nothing. The README names `meetings.sqlite` but not its version or the fill, and no key changes.
- **Version:** agreed with the author. I propose 0.4.1, since nothing new shows. It goes in `CFBundleShortVersionString` and `docs/releases/<version>.md`.
- Commit `Docs: query plans; version <version>`.

### Task 6: GATE: the installed build (spec §9, Q1–Q3, with the author)

- Run `make test`, then ask before installing: it restarts Shepit, and a transcript may be running. Then install.
- **Q1.** After first launch, read the author's `meetings.sqlite` with `sqlite3 -readonly`. Report the version and the index names only: version 3, `meetings_start`, `people_person`.
- **Q2 and Q3 with the author:**
  - Home's recent meetings, Meetings and People, with a person, Who talked how much and May also be in;
  - after the next meeting is listed, dictation by hotkey at once.
- Mark each check in the checklist; fix the author's remarks in this task.

### Task 7: End-of-branch reviews and the pull request

- Follow `docs/process.md` §5.3–§6:
  - Claude runs the code reviewer and the security reviewer at the same time.
  - Claude gives its opinion on each finding, the author picks, and Claude fixes what was picked.
  - Then the author runs the thermo-nuclear review.
  - Each manual check is marked.
  - Claude asks "open the PR?".

## Open questions to raise when the task starts (not blockers)

- **Task 3:** if `PeopleView` shows May also be in with a heading even while `suggestions` is empty, the block blinks when a new person is chosen. If so, show the author before changing the view.
- **Task 5:** the version (0.4.1 proposed).

## Progress

- 2026-11-24: the spec approved (c5440a9).
- 2026-11-24, the plan review. Of the critic's findings, these were taken:
  - transactions wait for another writer (Task 2, new, after a check with two connections);
  - the test fixture's `name_key`;
  - suggestions emptied after the section's own changes;
  - one read at a time that checks the store and Remember voices when it ends, with the prints kept as their own read;
  - the review rule from Task 1;
  - the docs before the gate.

  Of the improver's suggestions, these were taken:
  - Tasks 1 and 2 as one;
  - one test for the upgrade and the plans;
  - no separate store tests for the two reads;
  - the forget's test folded into the existing one;
  - a flag for the forget;
  - the doc lines to edit.

  Not taken:
  - `MeetingPage.pair`'s removal, since it has three other callers;
  - a shared SQL constant for the plan tests, which would add an API for a test. The review rule covers a changed query.
- 2026-11-24, **Task 1** done (898589e). `make test`: 676 tests (one added, one removed).
  - The task review found the README still promising the fill ("counted from their notes the first time People opens"). That sentence goes. The plan's "no live doc names the fill" had missed it, since the README describes the fill without naming it.
  - `meetings(of:)` still sorts after its search, but only one person's meetings. Its doc comment now says so.
- 2026-11-24, **Task 2** done (f9d4aa8). `make test`: 677 tests. Before the change, the new test failed at once with "database is locked".
  - The task review found no bug in the transaction.
  - Its test closed the second connection while the delayed commit could still use it. It now waits for the commit before closing.
  - It noted that only `MeetingStore` calls `transaction`, which the execution notes now say.
  - A main-thread change can now wait up to 5 s for another connection's write, where it used to fail. Task 4's forget is one short `DELETE`.
- 2026-11-24, **Task 3** done (0d37ac9). `make test`: 677 tests.
  - **Different from the plan:**
    - The dropped-read check is in the existing suggestions test, not a new test.
    - `PeopleView` needs no change: May also be in shows only while there are suggestions, so no empty heading blinks. That settles the open question. The row now appears a moment after a person is chosen (about 70 ms after a year), which Q3 shows the author.
  - **The task review found no bug.** On its first finding, the test now also covers a read that ends after Remember voices was turned off. Removing that check now fails the test.
  - **Not covered by a test:**
    - The `store.version` check: in a test the read starts only after the test's own write, so it sees the new data either way. Testing it would need a hook inside the read.
    - Emptying on a switch from one named person to another: the test has only one named person besides You.
  - Assigning the same person again (as back and forward may) empties the row and reads it again. Left as it is.
- 2026-11-24, **Task 4** done (a3b4fc6). `make test`: 677 tests.
  - The task review found no bug: the two connections wait for each other, the flag can't stay set, and nothing cached by `version` goes stale.
  - On its one finding, the test now checks that the bytes are gone right after the forget, before the main connection removes a meeting.
  - `forgettingVoices` is an internal `var`, since `AppHost+Meetings.swift` uses it.
- 2026-11-24, **Task 5** done (cb9910f). Version 0.4.1, agreed with the author.
- 2026-11-24, **Task 6**: 0.4.1 (cb9910f) installed.
  - Q1 passed: version 3, both indexes, and the same row counts as before the install.
  - The author checked Q2 and Q3: "everything is ok".
- 2026-11-24, **Task 7**, the code and security reviews. Nothing blocking; nine minor findings. The author took Claude's advice:
  - upgrade 3 uses `CREATE INDEX IF NOT EXISTS`, so an index made by hand can't lock the store out;
  - the data's permissions are noted as a new idea;
  - the write lock taken on every open, and a failed `COMMIT` after notes were rewritten, are noted under "Query plans: left open".

  The rest were left with reasons: harmless, older than the branch, or accepted in the spec. One proposed fix, `journal_mode = TRUNCATE` or `PERSIST`, was wrong, since neither overwrites the journal's pages.
- 2026-11-25, **Task 7**, the author's thermo-nuclear review. The author took all three points:
  - **May also be in in one step**, as spec §7.5 and §8 had it. The plan review had kept the prints as a read of their own, so after every change of the store the unnamed voices were read, then the prints, then the unnamed voices again. Now `MeetingStore.suggestions(in:for:prints:)` reads the unnamed voices and, only when there is one to compare and `PeopleModel`'s prints are older than the store, the prints, then runs `Voices.suggestions`, all off the main thread. `readPrints()` and `reading` go. A failed read no longer keeps empty prints for that version, so the next reload tries again.
  - **The suggestions test split in two**, as Task 3 had planned: `aReadThatEndsAfterTheChoiceOrRememberVoicesChangedShowsNothing` is its own test. That the given prints are used as they are is checked in the store's test (`suggestionsInOneStepReadThePrintsOnlyWhenNeeded`).
  - **No flag for the forget.** `AppHost.forgettingVoices` goes: a second run waits for the first on SQLite's lock and finds nothing. The only overlap is a launch that lists an interrupted transcript.

  Looked at and left: one helper for `BEGIN IMMEDIATE` in `transaction` and `upgrade` (it would hold the connection across the body, which `transaction` takes again for each statement), one generic helper for the static reads, and the SQL copied in the plan test (spec §7.4).
- 2026-11-25: a3682cb installed; the author checked Q3 again: "everything is ok". The store is still version 3 with both indexes.
