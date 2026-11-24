# Main window, part 4: Statistics

Date: 2026-11-17
Status: Approved by the author (2026-11-17)
Look and screens: `2026-11-11-visual-style/visual-style.md` ("the style spec") §5.6, and `mockups.html` screen 7.
What is shown today: `2026-10-18-native-app/05-statistics.md` ("the old spec"); this spec replaces its §2.

## 1. Intent

The Statistics section today is a settings-style form: one long page of tiles, charts and tables with Day / Week / Month / Year / All buttons. The author rejected that UI as a whole (CLAUDE.md: "don't polish it piece by piece"). This part rebuilds the section in the window's style (mockup 7), picks the period the way Dictations does, splits the numbers into Overview, Dictation and Meetings, and adds the numbers the style spec asked for: languages, speed over time, meetings in detail (by app, your share of words, people, length) and the call offers.

## 2. Decided by the author

2026-11-11 (style spec §5.6): the same tiles and charts as today in the new style, plus languages, speed over time, dictionary, failures, meetings (your share of words, people, duration, failed chunks), meetings by app, call offers by outcome. Words per saved person needs voice prints (part 7).

2026-11-17:
- **Period:** a menu as in Dictations, plus **Custom…**, which picks a start and an end date in a calendar.
- **Meetings come from `stats.sqlite`.** Each new meeting row also keeps its app (Teams, Zoom, Meet); older rows show as "Unknown". Everything stays under `collectStats` and Clear statistics…, as today.
- **Layout:** Overview, Dictation and Meetings, switched at the top.
- **New numbers in this part:** languages, speed over time, meetings in detail, call offers.

## 3. Goals, non-goals, anti-goals

**Goals**
- The section as in mockup 7: a title row with the period menu, tiles, Words per day.
- Overview, Dictation and Meetings views, with every number of §5.
- A period menu shared with Dictations, plus Custom….
- `stats.sqlite` keeps each meeting's app from now on.

**Non-goals**
- Words per person (part 7, voice prints).
- Model load time and memory (`model_events` is kept as it is; not shown).
- Statistics from `meetings.sqlite` or from notes added with Add notes….
- Filling in the app of meetings recorded before this version.
- Exporting the numbers.

**Anti-goals**
- Any text in `stats.sqlite`: no dictated text, no meeting or call names, no person names. The new column is the app's fixed name (`Teams`, `Zoom`, `Meet`, as in `offers`).
- Anything written while `collectStats` is off.
- Reading the database while the window is closed or another section is shown.
- Colour carrying meaning on its own: every chart has labels or a legend, and the change against the previous period is text ("▲ 12%"), not red or green.

## 4. The period

One menu at the right of the title row, as in mockup 7, with the same choices as Dictations' Show menu: Today, Last 7 days, Last month, Last 3 months, Last 6 months, Last 9 months, Last year, All history; and, below a separator, **Custom…**. Last month by default; the choice is remembered, apart from Dictations' choice.

- A period runs from the start of its first day to now (as in Dictations).
- **Custom…** opens a small popover with a graphical calendar for the start and one for the end, and **Show**. Whole days, both ends included; the end can't be before the start or after today. The menu then reads "12 Nov – 16 Nov 2026"; Custom… again opens the popover with those dates.
- **Change against the previous period** (the small text under each tile): as many calendar days right before it, the last of them up to the same time. Today against yesterday up to this time; Last 7 days against the 7 days before; Last month (16 Oct – 16 Nov, 32 days with today) against the 32 days before; a custom range against as many days right before it. None for All history.
- **Buckets** for charts over time: by hour for Today or a one-day custom range; by day up to a month (Last month included); by week up to 6 months; by month beyond.

`DictationPage.Period` moves to its own type in ShepitCore, shared by both sections, with the range, the previous range and the bucket unit.

## 5. The section

The title row: "Statistics", the view switch (**Overview · Dictation · Meetings**, a segmented control; the last one used is remembered) and the period menu. Under it, the chosen view, scrolling. Sections inside a view are the window's grouped blocks (label above, content in a rounded group), as in the other sections.

### 5.1 Overview (mockup 7)

- **Tiles:** Dictations, Words, Meetings · hours, Time saved ("at 40 wpm" under it, a link to the typing-speed setting). Each with its change against the previous period.
- **Words per day** (or per hour, week, month: the bucket of §4): stacked bars, dictation and meetings, with the hover tooltip of today.
- A line under the chart says how time saved is counted (as today).

### 5.2 Dictation

- **Speed:** the table of today (median wait after stop, and per 10 s of audio, per engine and model), and under it **Speed over time**: a line per engine and model, the median wait per 10 s of audio in each bucket. A bucket with fewer than 3 dictations of that engine is left out of its line.
- **Pasted into:** the top 8 apps and Other, as today.
- **When you dictate:** the hour × weekday heatmap of today.
- **Languages:** the share of each language among dictations that report one ("Ukrainian 72% · English 28%"). With Ukrainian or English chosen, the engines report that language; Auto-detect reports what it found, "Ukrainian + English" for a dictation with both. No "detected another language than chosen" line (decided while building, 2026-11-17): with a language chosen every engine reports the chosen one (59 of 59 such dictations in the author's store), so it would always read 0%.
- **Dictionary:** fixes made and the most corrected terms, as today.
- **Failures:** the share of cancelled, failed and nothing recognized, as today, with the counts, of all attempts; a tap too short to record (`discarded`) isn't an attempt.

### 5.3 Meetings

- **Tiles:** Meetings, Hours, Your share of words (your words ÷ all words of the meetings), People per meeting (the average of detected speakers).
- **By app:** Teams, Zoom, Google Meet and Unknown, each with its number of meetings and hours, as bars.
- **Length:** the average and the longest meeting, and the meetings by length (under 15 min, 15–30, 30–60, over an hour).
- **Speaker detection:** meetings where it ran, its median time, and failed chunks (how many, in how many meetings).
- **Call offers:** how the panel's offers ended (Started, Started automatically, Dismissed, Hidden by time), in total and per app.

### 5.4 Empty and off

- `collectStats` off: "Statistics are off" and a button to Settings → History and privacy, in every view; numbers already stored are still shown under it.
- Nothing in the period: the tiles show 0 and the views say "No dictations in this period" or "No meetings in this period". Words per day says nothing when there are no words.

## 6. The store

- `stats.sqlite`'s `meetings` table gets an `app` column (`Teams`, `Zoom`, `Meet`, or empty for a meeting Shepit could not tie to an app). An older file gets the column when it is opened; its rows keep it empty. `schema_version` becomes 2.
- `MeetingRecord` gets the app; `MeetingSession` passes its call app when it records the meeting.
- An index on `offers (time)`, as `dictations` and `meetings` have (the period reads offers by time).
- Clear statistics… and `collectStats` work as today.

## 7. Elsewhere

- **README:** the Statistics section (views, period, Custom…), and that meetings keep their app in `stats.sqlite`.
- **The old spec** (`05-statistics.md`) gets a line pointing here for §2.
- Home, the menu and Settings are unchanged.

## 8. Structure

- `ShepitCore` (pure, tested):
  - The shared period (from `DictationPage.Period`, with Custom): range, previous range, bucket unit, menu title.
  - `Stats` gains: languages and the mismatch, speed over time, meetings by app, share of words, people, length groups, speaker detection, offers by outcome and app. Existing functions keep their tests.
  - `StatsDatabase`: the `app` column and its migration; `MeetingRecord.app`.
- `Shepit`: `StatisticsSection` is replaced by a `StatisticsView` in `Window/` with one file per view if it grows past a few hundred lines; it reads rows for the period (and the previous one) once per change of period or view, not on every redraw.

## 9. Tests and manual checks

Unit tests: every period's range and previous range at a fixed now and calendar, custom ranges (one day, across a month end, a DST change), bucket units; each new aggregation with small hand-made rows (languages with a mixed and an unknown code, a speed bucket under 3 dictations, meetings with and without an app, share of words with no words, length groups at their edges, offers per app); the migration (a version-1 file with meetings gets the column and keeps its rows; a new file has it); a meeting record with its app read back.

Manual (added to `docs/manual-test-checklist.md` as S1–S8):
- S1 Overview on a real history: tiles, changes, Words per day; matches the old section's numbers for the same days.
- S2 Each period in the menu, and Custom… over a few days and over one day; the menu's title; the choice after a relaunch.
- S3 Dictation view: speed table and lines, apps, heatmap, languages (with an Auto-detect dictation in both languages), dictionary, failures.
- S4 A meeting in Teams and one in Meet: Meetings shows them under their apps; older meetings under Unknown.
- S5 Call offers: start one from the panel, dismiss one, let one hide; the counts follow.
- S6 `collectStats` off: the note and its button; nothing new is recorded.
- S7 Clear statistics…: every view is empty; the file stays deleted while Statistics is only looked at.
- S8 Light and dark, a narrow and a wide window.

## 10. My calls (not confirmed one by one)

- The period choices are Dictations' list, so Last month (not "Last 30 days" of the mockup) is the default.
- The previous period runs up to the same moment (today against yesterday until now), so a half-finished day isn't compared with a whole one.
- Buckets: hour, day, week, month by the length of the period.
- Overview is the default view; the view and the period are remembered.
- Speed over time leaves out buckets with fewer than 3 dictations of an engine, so one slow dictation doesn't draw a spike.
- People per meeting is the speakers speaker detection found plus you, not names.
- Length groups: under 15 min, 15–30, 30–60, over an hour.
- Model load time and memory stay out of the window.

## 11. Open questions for the plan

- Whether Swift Charts draws the speed lines readably with many engine and model pairs (a limit, or the top 4 by use).
- The custom popover: one graphical calendar for a range, or two (start, end), as macOS has no range picker.
- Whether the three views share one fetch per period (rows of dictations, meetings and offers) or each reads what it shows.
