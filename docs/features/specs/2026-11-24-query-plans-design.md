# Every query on an index, every index used

Date: 2026-11-24
Status: First draft, with the findings; §2 waits for the author's answers.
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

Timed on a year of meetings, every query except a few full reads takes a millisecond or less. Those full reads are listed in §6.3. So the part is small: one upgrade of `meetings.sqlite`, plus the decisions in §2.

## 2. Decided by the author

- **Where a query scans or sorts, the index it needs is added; an index no query uses is dropped** (the author, 2026-11-15 and 2026-11-17).
- Open, to ask in round 1:
  - **Lines without words** (§7.2):
    - drop the fill (recommended);
    - a partial index;
    - leave it as it is.
  - **An index on `lines (meeting, current)`** (§7.3):
    - not added (recommended);
    - added.
  - **Keeping it true** (§7.4):
    - a rule for the task review (recommended);
    - a test in `make test`;
    - nothing.
  - **The heavy reads on the main thread** (§6.3):
    - left for later (recommended);
    - taken into this part.

## 3. Goals, non-goals, anti-goals

**Goals.**
- A query that reads part of a table finds that part through an index.
- No index that no query uses.
- The stores behave exactly as before.

**Non-goals.**
- Making the full reads by design faster (§6.3).
- Moving reads off the main thread.
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

`suggestedVoices` and `forgetUnnamedVoices` run on the main thread, which also handles the dictation hotkeys. At a year they take 60–70 ms each, and more after that. Moving them off the main thread is a separate change (§2).

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

### 7.2 Lines without words (to decide)

**What it does now.**
- `meetingsWithoutWords` finds meetings listed before 2026-11-20, whose lines have no word counts, and `fillWords` counts them from the notes.
- This runs once per run of Shepit, when People first appears.
- To find them it scans every line: 132,000 rows a year, 5 ms.
- The author's file has no such line left, and every meeting added since Voices has its words.

**The choices.**
- **Drop the fill (recommended).** Remove `meetingsWithoutWords`, `fillWords`, `PeopleModel.fillWords` and their tests.
  - A version-1 file from before Voices would show those meetings' words as unknown, as it does today until People fills them.
  - Only the author's Mac had such files, and they are filled.
- **A partial index.** `CREATE INDEX lines_without_words ON lines (meeting) WHERE words IS NULL`, in upgrade 3.
  - It is empty in the author's file, and no write touches it, since every new line has words.
  - The scan goes and the code stays.
- **Leave it as it is.** The scan stays, at 5 ms once per run.

### 7.3 An index on `lines (meeting, current)` (to decide)

**What it would change.** Today a person's lines in a meeting are found by reading that meeting's lines (about 165) through the primary key. The index would find them directly. On a year:

| Query | Today | With the index |
|---|---|---|
| People's list (`summaries`) | 32 ms | 26 ms |
| May also be in (`suggestedVoices`) | 69 ms | 46 ms |

**The cost.**
- One index entry per line: the file grows by 1.6%.
- An index write for every line added, and every time a line is given to another person.

**Recommended: not added.** These queries already search an index, as the author's rule asks. The gain is 6–23 ms after a year.

### 7.4 Keeping it true (to decide)

- **A rule for the task review (recommended).** `docs/process.md`'s task reviewer runs `EXPLAIN QUERY PLAN` on every new or changed query, and reports a scan or a temporary sort that isn't a read by design.
- **A test in `make test`.**
  - `SQLiteFile` collects every statement the store tests prepare.
  - A test explains each one, and fails on a scan or a temporary sort that isn't on a list of reads by design.
  - It needs more code: a hook in `SQLiteFile`, and a list to keep up to date.
- **Nothing.** This part's own tests (§9) keep the two indexes in use.

## 8. Structure

- **In `ShepitCore`:**
  - `MeetingStore.upgrades` gets its second entry, which is upgrade 3;
  - with the recommended §7.2, `MeetingStore+People.swift` loses `meetingsWithoutWords` and `fillWords`.
- **In the app:** with the recommended §7.2, `PeopleModel.fillWords` and the `.task` in `PeopleView` that calls it go.
- **Nothing else changes:** no setting, no text in the window, no change to the README beyond the database version.

## 9. Tests and manual checks

**Tests.**
- A version-2 file, made with upgrade 2's layout and a few rows, opens as version 3. It has both indexes and keeps its rows.
- The plan of `meetings(limit:)` uses `meetings_start` with no temporary sort.
- The plan of `meetings(of:)` searches `people_person`.
- Both plan tests read `EXPLAIN QUERY PLAN` through the store's `SQLiteFile` (`@testable`).
- With the recommended §7.2, the tests of `meetingsWithoutWords` and `fillWords` go.

**Manual checks**, as Q1–Q2 in `docs/manual-test-checklist.md`:
- **Q1.** Install the build. On first launch, the author's `meetings.sqlite` becomes version 3 with `meetings_start` and `people_person`. Read it with `sqlite3 -readonly`: the version and the index names only.
- **Q2.** Home's recent meetings, Meetings, People (a person, Who talked how much, May also be in) and Delete voice… work as before.

## 10. My calls (not confirmed one by one)

**`keys(of:in:)` picks `people_person`.** For `meeting = ? AND person = ?`, the planner now reads every row of the person (for You, one per meeting) instead of the meeting's few. That is under 1 ms after a year, so it is left as it is. Making the planner pick the meeting's index would need statistics or a changed query.

**`EXPLAIN QUERY PLAN` runs on an empty file in the tests.** Without statistics the planner's choice doesn't depend on the number of rows.

**Database version only.** `meetings.sqlite` goes to version 3. `dictations.sqlite` stays as it is.
