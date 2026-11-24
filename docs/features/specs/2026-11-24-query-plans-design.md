# Every query on an index, every index used

Date: 2026-11-24
Status: Complete, for the author's approval (2026-11-24), with the decisions in §2.
Build order: item 13 in `docs/future-ideas.md` ("Planned, in this order"), item 3 of "Next". Branch `query-plans`. The version is agreed with the author before the pull request.
Builds on: `2026-11-14-meetings-design.md` §4 (`meetings.sqlite`), `2026-11-17-voices-design.md` §4–§7 (persons, voice samples, `line_voices`), `2026-11-16-dictations-dictionary-design.md` §4 (`dictations.sqlite`), and `2026-11-17-statistics-design.md` (`stats.sqlite`, checked in that part).

## 1. Intent

The author asked for this on 2026-11-15 and widened it on 2026-11-17:

- check every query of the three databases with `EXPLAIN QUERY PLAN`;
- where a query scans a whole table or sorts in a temporary B-tree, add the index it needs;
- then go through every index and drop the ones no query uses, since they only slow writes.

`stats.sqlite` was checked in the Statistics part. This part checks `meetings.sqlite` and `dictations.sqlite`.

What was found:

- **`dictations.sqlite`** needs nothing.
- **`meetings.sqlite`** lacks two indexes:
  - on `meetings (start)`: the meetings list and Home's last 10 scan and sort every meeting;
  - on `people (person)`: every read of one person's meetings scans every `people` row, and naming someone builds a temporary index on each call.
- **Unused indexes:** none. Every index both files have is used, and each also enforces a key.

Timed on a year of meetings, every query except a few full reads takes a millisecond or less. Those full reads are listed in §6.3.

So the part is small:
- one upgrade of `meetings.sqlite`;
- the fill of old meetings' words goes, with its scan of every line;
- a rule for new queries;
- two reads that run on the main thread move off it.

## 2. Decided by the author

- **Where a query scans or sorts, the index it needs is added; an index no query uses is dropped** (the author, 2026-11-15 and 2026-11-17). For this part that is `meetings (start)` and `people (person)` (§7.1); nothing is dropped (§6.4).
- **Lines without words: the fill goes** (2026-11-24, recommended). `meetingsWithoutWords` and `fillWords` are removed, and with them the scan of every line (§7.2).
- **No index on `lines (meeting, current)`** (2026-11-24, recommended). Those queries already search an index; the gain is 6–23 ms after a year (§7.3).
- **Keeping it true: a rule for the task review** (2026-11-24, recommended). The task reviewer runs `EXPLAIN QUERY PLAN` on every new or changed query (§7.4).
- **The two heavy reads on the main thread move off it in this part** (2026-11-24; I had recommended leaving them for later). They are May also be in and the forgetting of old unnamed voices (§7.5). The dictation hotkeys are handled on the main thread too, so a 60–70 ms read there can delay one.

## 3. Goals, non-goals, anti-goals

**Goals.**
- A query that reads part of a table finds that part through an index.
- No index that no query uses.
- The stores behave exactly as before.

**Non-goals.**
- Making the full reads by design faster (§6.3); two of them only move off the main thread (§7.5).
- Moving other reads off the main thread: People's list (`summaries`, 33 ms a year) and one meeting's reads stay where they are.
- `ANALYZE` statistics: without them the planner already picks the indexes of §7.1.

**Anti-goals.**
- An index for a table of a few hundred rows. `persons` has 22 rows today and about 150 after a year; `declined` has none.
- An expression index on `name_key`. It is Shepit's own SQL function, so the file would need Shepit to be written, and `sqlite3` could no longer change those tables.

## 4. How it was checked

**The plans.**
- Every SQL statement in `MeetingStore` (`MeetingStore.swift`, `+People`, `+Voices`) and in `DictationStore` was run with `EXPLAIN QUERY PLAN`.
- They ran on SQLite 3.51.0, the copy in macOS that Shepit links.
- They ran against an empty file made from the schema and upgrades in the code, with the `line_voices` view.
- `name_key` was replaced by `lower`. Both are functions on the column, so neither can use an index and the plan is the same.
- Neither real file has `sqlite_stat1`, so the planner chooses the same plans on them.

**The times.** They were taken on a synthetic year made by a script, with no real data:

| Table | Rows |
|---|---|
| meetings | 800 |
| people rows | 3,200 |
| persons | 151 |
| lines | 132,000 |
| samples | 99,000 (1 KB each) |

The file is 145 MB. Each time is the best of five runs, using `sqlite3`'s own timer.

**For scale, the author's files on 2026-11-24.** These are counts only, read with `sqlite3 -readonly`:

| File | Rows |
|---|---|
| `meetings.sqlite` | 64 meetings since 26 Oct; 238 people rows, 22 persons, 10,529 lines, 4,370 samples |
| `dictations.sqlite` | 6 dictations |

## 5. `dictations.sqlite`

| Query | Plan |
|---|---|
| `page`, the newest | walks `dictations_time` backwards, stops at the limit; no sort |
| `page(before:in:)`, `page(in:)` | searches `dictations_time` for the time range, in order; no sort |
| `delete` | the row id |
| `prune` | searches `dictations_time` (`time < ?`) |

`dictations_time` is used by `page` and `prune`. Nothing changes.

## 6. `meetings.sqlite`

### 6.1 What the two indexes change

| Query (where it runs) | Plan today | With `meetings_start` and `people_person` |
|---|---|---|
| `meetings()` (Meetings, People) and `meetings(limit:)` (Home, the 🎙 menu) | scans `meetings`, temporary B-tree for the order | walks `meetings_start` backwards; no sort |
| `meetings(of:)` (Rename and Merge into… in People) | scans `people` | searches `people_person` |
| `listed(person:)` (the back and forward arrows) | scans `people` | searches `people_person` |
| `presences` (Who talked how much) | reads every `people` row through the primary key | searches `people_person`, then sorts that person's meetings for the grouping |
| `personID(named:)` (a name given in a meeting) | builds an automatic index on `people.person` on every call | searches `people_person` |
| `dropUnlistedPersons` (after a name change or a removal) | scans `people` | reads `people_person` only (covering) |
| `suggestedVoices` (May also be in, when a person is chosen) | scans `lines`, and `people` for the `NOT IN` | starts from the people rows with no person; 85 → 69 ms a year |
| `deleteVoice` (Delete voice…) | scans `lines` | starts from the person's rows; 81 → 5 ms a year |
| `forgetUnnamedVoices` (at launch, after each meeting) | scans `meetings` for the date | searches `meetings_start` |

At a year's size, the reads that are not timed in the table take 1 ms or less, with or without the indexes. The indexes keep them that way as the store grows, and they bring the plans to the author's rule.

### 6.2 What stays as it is

- **One meeting's reads and changes**, and adding a meeting:
  - `people`, `lines`, `link`, `give`, `merge`, `reset`, `delete(lines:)`, `fillWords`, `add`;
  - each searches a primary key that starts with the meeting.
- **Small sorts:**
  - one meeting's people in the order they were added (`people`, `keys(of:in:)`), a few rows;
  - the persons that share a name in `personID(named:)`, usually one.
- **`persons`, scanned by its `you` flag or by `name_key`:**
  - `youID`, `person(named:except:)`, `personID(named:)`, and the You test in `line_voices`;
  - the table has 22 rows today and about 150 after a year.
- **`declined`, scanned by person** in Merge into…: it has no rows today.

### 6.3 Full reads by design

They read every row on purpose. An index can't make them read less.

| Query | Where it runs | A year |
|---|---|---|
| `knownNames` | every name, for the name fields | ≤ 1 ms |
| `summaries` | People's list | 33 ms |
| `voiceRows` / `prints` | every voice sample, read off the main thread | 130 ms |
| `suggestedVoices` | every unnamed voice, on the main thread | 69 ms with §7.1 |
| `forgetUnnamedVoices` | every old sample is checked, on the main thread | 60 ms once nothing is left to forget |
| `deleteAllVoices`, upgrade 2 | everything, once | |

`suggestedVoices` and `forgetUnnamedVoices` run on the main thread, which also handles the dictation hotkeys. At a year they take 60–70 ms each, and more after that. They move off the main thread (§7.5).

### 6.4 The indexes the file has

These are the five indexes SQLite makes for `PRIMARY KEY` and `UNIQUE`. Each is used, and each enforces a key, so none can go:

| Index | Used by |
|---|---|
| `meetings (path)`, unique | `meeting(path:)`, and `add`'s `INSERT OR IGNORE` |
| `people (meeting, key)` | one meeting's people, every change of a meeting's person |
| `lines (meeting, timestamp, ord)` | one meeting's lines, `give`, `delete(lines:)`, the `line_voices` join |
| `samples (meeting, timestamp, ord)` | the `line_voices` join, `delete(lines:)`, `forgetUnnamedVoices` |
| `declined (meeting, key, person)` | `suggestedVoices`' `NOT EXISTS`, `nameSuggested`'s `INSERT OR IGNORE` |

## 7. The changes

### 7.1 Upgrade 3 of `meetings.sqlite`

```sql
CREATE INDEX meetings_start ON meetings (start);
CREATE INDEX people_person ON people (person)
```

**Why an upgrade and not the schema.** `people.person` came with upgrade 2, and the schema runs first. The schema stays version 1's layout (`SQLiteFile`).

**Older files and older Shepit.**
- A version-2 file gets both indexes when Shepit next opens it, in the same transaction as the version.
- An older Shepit that opens a version-3 file runs no upgrade. SQLite keeps the two indexes up to date for it.

The names follow `dictations_time` and `offers_time`.


### 7.2 Lines without words: the fill goes

**What it does now.**
- `meetingsWithoutWords` finds meetings listed before 2026-11-20, whose lines have no word counts, and `fillWords` counts them from the notes.
- This runs once per run of Shepit, when People first appears.
- To find them it scans every line: 132,000 rows a year, 5 ms.
- The author's file has no such line left, and every meeting added since Voices has its words.

**What goes** (the author, 2026-11-24):
- `MeetingStore.meetingsWithoutWords` and `fillWords`;
- `PeopleModel.fillWords`, with its `wordsFilled` flag;
- the `.task` in `PeopleView` that calls it;
- their tests.

A version-1 file from before Voices would show those meetings' words as unknown, as it did before People filled them. Only the author's Mac had such files, and they are filled.

The partial index `lines (meeting) WHERE words IS NULL` was the other way. It would have removed the scan and kept the code.

### 7.3 No index on `lines (meeting, current)`

**What it would have changed.** Today a person's lines in a meeting are found by reading that meeting's lines (about 165) through the primary key. The index would find them directly. On a year:

| Query | Today | With the index |
|---|---|---|
| People's list (`summaries`) | 32 ms | 26 ms |
| May also be in (`suggestedVoices`) | 69 ms | 46 ms |

**What it would have cost.**
- One index entry per line: the file grows by 1.6%.
- An index write for every line added, and every time a line is given to another person.

**Not added** (the author, 2026-11-24): these queries already search an index, as the author's rule asks.

### 7.4 Keeping it true: a rule for the task review

`docs/process.md` §7, the task reviewer's brief, gains this line:

> Run `EXPLAIN QUERY PLAN` on every SQL statement the task adds or changes, against a file made from the store's schema and upgrades, and report a scan of a whole table or a temporary B-tree that the code doesn't call a read by design.

**Where "by design" is written.** A query that reads everything on purpose says so in its doc comment, as `knownNames` and `prints` already do.

A test in `make test` was the other way. It was left out because it needs a hook in `SQLiteFile` and a list of allowed scans to keep up to date.

### 7.5 Two reads off the main thread

Both follow `prints(in:except:)`, which already runs on a connection of its own, off the main thread. Each connection opens the file with the schema, so it has `secure_delete` and the `line_voices` view. Both connections wait up to 5 s for each other (`sqlite3_busy_timeout`).

**May also be in (`suggestedVoices`).**
- `PeopleModel` reads the unnamed voices for the chosen person off the main thread. It reads the prints there too when its copy is older than the store, so the read and the prints become one step.
- A read that comes back after the choice changed, or after the store changed, is dropped. A newer read for the person chosen now is under way by then.
- Until a read is back, the person shows no suggestions. This is what happens today while the prints are being read.

**Forgetting old unnamed voices (`forgetUnnamedVoices`).**
- `AppHost` runs it off the main thread, at launch and after each meeting is listed, as it does now on the main thread.
- One run at a time: a second request while one runs is skipped. The next meeting runs it again.
- It deletes only samples that belong to nobody named. That means the prints, and People's counts of voices, don't change, so the main connection's `version` needs no bump.
- A main-thread write that comes while it runs waits for it, up to the delete's own time (60 ms a year). Today that time blocks the main thread on every run.

## 8. Structure

**In `ShepitCore`:**
- `MeetingStore.upgrades` gets its second entry, which is upgrade 3 (§7.1).
- `MeetingStore+People.swift` loses `meetingsWithoutWords` and `fillWords` (§7.2).
- `MeetingStore+Voices.swift` gets `suggestedVoices(in:for:)` and `forgetUnnamedVoices(in:before:)`. These are static and async, beside `prints(in:except:)`, each on a `MeetingStore` of its own.

**In the app:**
- `PeopleModel.suggest()` reads off the main thread and replaces `readPrints()`; `PeopleModel.fillWords` goes.
- `PeopleView` loses its `.task`.
- `AppHost.forgetOldVoices()` runs its delete off the main thread.

**Docs:**
- the task reviewer's line in `docs/process.md` (§7.4);
- `meetings.sqlite` (version 3) and the reads off the main thread in `docs/architecture.md`;
- Q1–Q3 in `docs/manual-test-checklist.md`.

Nothing changes in settings, in the window's texts or in the README beyond the database version.

## 9. Tests and manual checks

**Tests.**
- **The upgrade.** A version-2 file, made with upgrade 2's layout and a few rows, opens as version 3. It has both indexes and keeps its rows.
- **The plans.** These read `EXPLAIN QUERY PLAN` through the store's `SQLiteFile` (`@testable`):
  - `meetings(limit:)` uses `meetings_start` with no temporary sort;
  - `meetings(of:)` searches `people_person`.
- **The reads of their own.**
  - `suggestedVoices(in:for:)` gives what `suggestedVoices(for:)` gives.
  - `forgetUnnamedVoices(in:before:)` deletes what the method on the store deletes. It also overwrites the deleted samples: `secure_delete` is on for that connection, checked with `PRAGMA secure_delete`.
- **People.**
  - `PeopleModelTests` shows suggestions once the read is back.
  - A suggestion read for one person that returns after another person is chosen shows nothing for the new one.
- **What goes.** The tests of `meetingsWithoutWords` and `fillWords`.

**Manual checks**, as Q1–Q3 in `docs/manual-test-checklist.md`:
- **Q1.** Install the build. On first launch, the author's `meetings.sqlite` becomes version 3 with `meetings_start` and `people_person`. Read it with `sqlite3 -readonly`: the version and the index names only.
- **Q2.** Home's recent meetings, Meetings, People (a person, Who talked how much) and Delete voice… work as before.
- **Q3.** With Remember voices on, choosing a person in People shows May also be in as before. After a meeting is listed, dictation by hotkey works at once.

## 10. My calls (not confirmed one by one)

**`keys(of:in:)` picks `people_person`.** For `meeting = ? AND person = ?`, the planner now reads every row of the person (for You, one per meeting) instead of the meeting's few. That is under 1 ms after a year, so it is left as it is. Making the planner pick the meeting's index would need statistics or a changed query.

**`EXPLAIN QUERY PLAN` runs on an empty file in the tests.** Without statistics the planner's choice doesn't depend on the number of rows.

**Database version only.** `meetings.sqlite` goes to version 3. `dictations.sqlite` stays as it is.

**The forget's skip.** A second forget while one runs is skipped, not queued. The next meeting, or the next launch, runs it again, and a sample kept a day longer than 30 days does no harm.

**People's suggestions are dropped, not merged.** A read that came back after a change is not shown, even when it would have been right. The read the change started shows a moment later.

**`summaries` stays on the main thread.** It takes 33 ms after a year and is read when People appears. The author's pick covered the two reads named in the question.
