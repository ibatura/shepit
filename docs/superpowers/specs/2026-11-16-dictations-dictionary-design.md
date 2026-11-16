# Main window, part 3: Dictations and Dictionary

Date: 2026-11-16
Status: Draft, awaiting the author's review
Look and screens: `2026-11-11-visual-style/visual-style.md` ("the style spec") §5.3–5.4, and `mockups.html` screens 4 and 5.
The window it lives in: `2026-11-13-window-shell-design.md` ("the shell spec").

## 1. Intent

Today every dictation goes to `history.log`, a plain text file with the time and the text and nothing else. The window has a placeholder for Dictations, and the Dictionary section is a settings form. This part keeps dictations in a local database that also knows the app each one went to, fills the Dictations section with the whole kept history, and gives the Dictionary the look of mockup 5.

## 2. Decided by the author

2026-11-11 (style spec §5.3, §5.4):
- Dictations: the history by day, with the text, time, app, word count and Copy. The section shows the whole kept history, loaded as the list scrolls. A long text shows its first two lines and "…"; a click opens the whole text in place. Copy always takes the whole text. At the bottom: how long history is kept, Open history file, Clear history….
- Dictionary: terms as chips, replace rules as a two-column list, drop phrases as chips, and an Add word button (the same dialog as ⌃⌥D).

2026-11-16:
- The app of each dictation is kept from now on, in a new store done properly. Dictations from before (`history.log`) are neither carried over nor shown; the old file can be deleted later.
- After scrolling through 5000 test entries: a "Show" menu at the top of Dictations limits the list to a period, Last month by default (§5). All history stays one of the choices.

## 3. Goals, non-goals, anti-goals

**Goals**
- `dictations.sqlite`: every result from this version on, with its time, app, text and word count.
- The Dictations section as in mockup 4, plus deleting one entry.
- Home, the menu's Recent and Copy last dictation read the new store.
- The Dictionary section as in mockup 5: terms and drop phrases as chips, replace rules edited in place, Add word.

**Non-goals**
- Carrying over or showing `history.log` entries; deleting `history.log`.
- Search, or a filter by app.
- New statistics (part 6). `stats.sqlite` is unchanged.
- Editing a dictation's text.
- Showing or editing the built-in drop phrases.

**Anti-goals**
- Dictated text in `stats.sqlite`. It stays numbers and names only.
- A dictation lost because the store failed. If the write fails, the text is still pasted or copied, and a message says the history could not be written (as today).
- Anything written while `saveHistory` is off.
- The Dictations section slowing dictation: a dictation is one INSERT; the window reads pages.
- The store in a synced folder. It has a fixed local path, like `meetings.sqlite`.

## 4. The store

`dictations.sqlite` in `databasesFolder` (default `~/.local/share/dictation`), the one folder setting for every database, with `stats.sqlite` and `meetings.sqlite` (decided with the author on 2026-11-16; Settings → History and privacy → Databases; read at launch, files are not moved). On the shared `SQLiteFile`, with a schema version.

```
dictations (id INTEGER PRIMARY KEY, time REAL NOT NULL, app_name TEXT, app_bundle_id TEXT, text TEXT NOT NULL, words INTEGER NOT NULL)
index on time
```

- **Written** when a result has text, before it is pasted (where `history.log` was written), only with `saveHistory` on. The app is the one the dictation was started in, the same one `stats.sqlite` records; when Shepit could not tell, the row has no app. Words are counted as the statistics count them (split on white space).
- **`historyDays`**: rows older than that are deleted at launch, as `history.log` lines are today. `0` keeps everything.
- **Delete one entry** and **Clear history…** (§5). `PRAGMA secure_delete` is on, so the text of a deleted row does not stay in the file's free pages. Clear history… deletes the file, as Clear statistics does, and the kept audio of failed attempts, as today.
- **`history.log`** is no longer written or read. Shepit leaves the file where it is; the README says it is from older versions and can be deleted.
- `uninstall.sh --purge` already deletes the whole data folder, the store with it.

## 5. The Dictations section

- **List**, newest first, grouped by day: Today, Yesterday, then the date ("13 November", with the year when it is not this year). Times are shown in the Mac's current time zone.
- **A row:** the text, cut to two lines with "…"; on the right "14:02 · Slack · 7 words" ("1 word"; no app part when the row has none); a Copy button. A click on the text opens the whole text in place; another click closes it. Copy takes the whole text and shows "📋 Скопійовано", like Copy elsewhere in the window.
- **Right-click:** Copy, Delete…. Delete asks first ("Delete this dictation? This cannot be undone.") and removes the entry from the list, Home and Recent.
- **Period:** a "Show" menu at the top: Today, Last 7 days, Last month, Last 3 months, Last 6 months, Last 9 months, Last year, All history. Last month by default; the choice is remembered. A period starts at the beginning of its first day.
- **Loading:** the newest 200 entries of the period when the section opens; the next 200 when the list nears its end, never older than the period. A new dictation appears at the top while the section is open.
- **Empty:** "No dictations yet"; "No dictations in this period" when only older ones exist; with `saveHistory` off, "History is off" and a button to Settings → History and privacy.
- **A bar at the bottom**, always visible: "Kept for 30 days" or "Kept forever", which opens Settings → History and privacy; and Clear history…, which asks first. Open history file of the mockup goes: the section is the history now.

## 6. The Dictionary section

Mockup 5. The title row has Add word, the section's main button: the same dialog as ⌃⌥D with nothing selected. A change is written to `dictionary.json` at once, and a hand edit of the file shows within a few seconds (the 2-s check), both as today.

- **Terms** (label "Terms: words the engine should know"). Chips in rows that wrap. "+ add" turns into a text field; Enter adds the term at the end (a term already there is ignored). A chip's × (shown on hover) removes it. Chips are dragged to change the order. The terms past the prompt limit (the ones `DictionaryRules.buildPrompt` leaves out with the current style prompt) are dimmed, and the hint says that the engine reads only the first ones, so the important ones go first. A term is not edited in place: remove it and add it again.
- **Replace** (label "Replace: heard → written"). One row per rule, sorted by what is heard: two text fields with → between them, and −. The last row is empty, with +. A change is saved on Enter or when the field loses focus; an empty side or a heard phrase another rule has is refused under the row, and the rule stays as it was.
- **Drop** (label "Drop: phrases removed from every result"). Chips, "+ add" and × as for terms, with no order. The hint says that common ones are built in.
- The hints are today's footers, made shorter, under each label.

## 7. Elsewhere in the app

- **Home:** the newest 10 dictations come from the store and now show the app ("14:02 · Slack"). All dictations opens Dictations, as now.
- **Menu:** Recent and Copy last dictation read the store.
- **Settings → History and privacy:** Open history goes; Save history, Keep history, Recent menu items, Keep failed audio and Clear history… stay. Their hints say "history" instead of `history.log`.
- **The Dictations placeholder** and the `openHistory` action go. `Paths.historyFile` and the `History` file code go with them; the time formatting Home and the menu use stays.
- **README:** the Dictations section, the store under privacy and in the file list, "Lost text" points at Dictations, and `history.log` is from older versions.

## 8. Structure

- `ShepitCore` (pure, tested):
  - `DictationStore`: the store of §4 (schema, add, a page before a given entry, the newest N, delete, prune, clear).
  - What the Dictations section shows, as data: day groups, row texts, the bottom bar's "Kept for …".
  - Which terms fit the prompt, from `DictionaryRules.buildPrompt`.
- `Shepit`: `DictationsSection` in `Window/`; `DictionarySection` rewritten, with a small wrapping layout for chips; `AppHost` writes to the store and builds `AppSnapshot.history` from it.

## 9. Tests and manual checks

Unit tests: the store (a new file, add, pages in order with several entries in one second, the newest N, delete, prune, clear, no app, data kept after reopening, `secure_delete` on); day groups (today, yesterday, this year, an earlier year) and row texts (with and without an app, "1 word"); "Kept for 30 days" and "Kept forever"; the terms that fit, with and without a style prompt; Home and the menu built from store entries.

Manual (added to `docs/manual-test-checklist.md` as D1–D9):
- D1 Dictate into three apps: the entries are at the top of Dictations with their app and word count; Home shows the app.
- D2 A long dictation: two lines with "…"; a click opens and closes it; Copy takes the whole text.
- D3 A long history (a test home with a few thousand entries): the list loads as it scrolls, with no jump.
- D4 Delete one entry: it asks first; the entry is gone from Dictations, Home and Recent.
- D5 Clear history… asks first and empties the list; `historyDays` 1 and a relaunch drops older entries; with `saveHistory` off nothing is written and the section says "History is off".
- D6 Terms: add, remove, drag to another place; `dictionary.json` has the new order; the terms past the limit are dimmed.
- D7 Replace: change a rule and press Enter, change one and click away; a heard phrase another rule has is refused; remove; add.
- D8 Drop phrases: add and remove. Add word in the window and ⌃⌥D on a selected word: the section shows the new term and rule.
- D9 Edit `dictionary.json` by hand with the window open: the section shows the edit within a few seconds.

## 10. My calls (not confirmed one by one)

- A SQLite store rather than an app field added to `history.log`: one entry can be deleted without rewriting a file, pages load as the list scrolls, and old entries are pruned with one query.
- `history.log` stops being written and is left on disk.
- One entry can be deleted, from the right-click menu, after a question; `secure_delete` keeps its text out of the file.
- How long history is kept is shown in Dictations and changed in Settings; Clear history… is in both places.
- Terms are chips that can be dragged; the ones past the prompt limit are dimmed.
- Times in the Mac's current time zone; no time zone is stored.
- Pages of 200 entries.
- Groups by day: Today, Yesterday, then the date.
- Replace rules sorted by what is heard, saved on Enter or when the field loses focus.
- Terms are not edited in place.

## 11. Open questions for the plan

- The wrapping layout for chips: a small SwiftUI `Layout`, and whether `draggable` / `dropDestination` give a smooth reorder inside it.
- Whether a `List` that asks for the next page when its last rows appear scrolls smoothly through a few thousand entries.
- Whether Add word in the window keeps today's `NSAlert` or becomes a sheet.
