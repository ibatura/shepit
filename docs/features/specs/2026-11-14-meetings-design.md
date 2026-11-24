# Main window, part 2: Meetings

Date: 2026-11-14
Status: Draft, awaiting the author's review
Look and screens: `2026-11-11-visual-style/visual-style.md` ("the style spec") §5.2, §7, and `mockups.html` screens 2 and 3.
The note and its header rules: `2026-10-17-meeting-transcription-design.md` ("the meeting spec") §5.4–5.7.
The window it lives in: `2026-11-13-window-shell-design.md` ("the shell spec").

## 1. Intent

Today a meeting is only a file. Shepit writes the note, labels the remote voices Person 1, Person 2 after the call, and the menu renames them through a chain of dialogs. This part fills the Meetings section of the window: a list of every transcript, and one meeting at a time with its people and its transcript. There the author names the meeting and its people, merges two people into one and gives a single line to another person. A local database keeps the list and who said each line, so a wrong change can be undone.

## 2. Decided by the author

2026-11-11 (style spec §2, §5.2, §8; `docs/future-ideas.md` "The main window"):
- A local database of meetings next to the Markdown notes. The note stays the transcript itself; the database keeps the link to the file, the name, the app, the start and the duration.
- The transcript is read only in the window. Editing happens in Obsidian. No search across transcripts. (2026-11-19, the author: a line, or all of a person's lines, can be deleted in the window; see Transcript.)
- People are named in the window. Two people can be merged into one. A single line can be given to another person.
- "Reset people" puts every line back to the person speaker detection gave it; the database keeps that first labelling.
- Renaming a meeting renames its note file: the `meetingFileName` template is filled again with the new name, in the same folder, with ` (2)` added when that name is taken. Links to the note from other Obsidian notes are not updated.
- A meeting whose note was moved or renamed stays in the list, marked "note not found", with a way to point at the file.
- Two actions remove a meeting: "Remove note from list" (the note stays) and "Move file to Trash" (both go).
- The menu loses Copy last meeting transcript, Rename speakers (both) and Open meetings folder (style spec §7).

2026-11-14:
- Notes made before this part are added with an **Add notes…** button: a file chooser that takes several notes at once. Nothing is scanned on its own.
- The database is `~/.local/share/dictation/meetings.sqlite`, a fixed path like `stats.sqlite`, with no setting.
- A person's name field suggests names given to people in earlier meetings.

2026-11-15, after trying the screens:
- The two removals are named **Remove note from list** and **Move file to Trash**.
- The name field suggests every real name Shepit knows: names given in the window, the labels of notes added by hand, and "you". The list opens while typing and also matches across scripts ("Іван" finds "Ivan Batura").

## 3. Goals, non-goals, anti-goals

**Goals**
- The Meetings section as in mockups 2 and 3: the list grouped by week, a finished meeting, the meeting being recorded.
- Every transcript from this version on is in the database; older notes are added with Add notes….
- Name a meeting; name people, merge them, give a line to another person, reset.
- Copy, Open note, Open meetings folder, Locate note, Remove note from list, Move file to Trash.
- The menu keeps only Start and Stop for meetings.

**Non-goals**
- Import names from a Teams, Zoom or Meet transcript (part 8): `2026-11-20-import-names-design.md`.
- Voice prints, "recognised by voice" and the People section (part 7). Designed in `2026-11-17-voices-design.md`.
- New statistics (part 6). `stats.sqlite` is unchanged.
- Giving several lines at once.
- Finding a moved note on its own.

**Anti-goals**
- Transcript text in the database. It holds names, paths, times and who said which line; the text is only in the note.
- The window changing anything in a note other than entry header labels and the front matter `title` line, or writing a note other than through a temp file and a rename.
- A change that lands in the note but not in the database, or the other way round.
- Shepit opening a folder the author did not point it at. The list checks only that each listed note exists; a note is read when its meeting is opened.
- The Meetings section slowing dictation or a running transcript.

## 4. The database

`~/.local/share/dictation/meetings.sqlite`, SQLite like `stats.sqlite`, with a schema version so later parts (voice prints, import) can add to it. `uninstall.sh --purge` deletes it with the rest of the data folder; Clear statistics and `collectStats` don't touch it, because it is the list of meetings, not statistics.

What it keeps:
- **A meeting:** the note's path; the name (may be empty); the app (Teams, Zoom, Meet, or none); the start; the duration; the label "you" has in this note (the microphone label it was written with).
- **A person of a meeting:** the label speaker detection gave ("Person 2", the "you" label, or `Співрозмовники` when detection failed) and the name given in the window (none until named).
- **A line of a meeting:** where it is in the note (its header's timestamp and its order within that second), the person speaker detection gave it, and the person it belongs to now.

A meeting is added:
- **When a transcript is ready:** after the Person labels are written, the note is read and each entry header becomes a line. Name, app, start and duration come from the session. An empty transcript that Shepit removes (call offer design §5.4) is not added.
- **When Shepit quits during a transcript:** the same, right after the "interrupted" line is written; the duration runs to the interruption.
- **After a crash:** the launch that marks the note as interrupted (meeting spec §5.10) adds it; the duration runs from the start to the last entry.
- **With Add notes…:** each chosen `.md` that has at least one entry header. The start comes from the front matter `date` and `time`, else from the first header; the name and app from the front matter; the duration from the start to the last header. "You" is the label equal to `meetingMyName` (or the macOS full name) if the note has it. The labels the note has at that moment count as what speaker detection gave. A note already in the list (same path) and a file with no entry headers are skipped. A message says how many were added and how many skipped.

## 5. The list

The section has two columns: the list on the left, the chosen meeting on the right (mockup 2).

- Newest first, in groups: This week, Last week, then one group per month ("October 2026"). Weeks start as the macOS calendar says.
- A row: the name, or "Teams call", "Zoom call", "Meet call" without one, or "Meeting" without a name and an app. Under it: day and time ("Tue 10:00"; "3 Oct, 10:00" in the month groups), the duration in minutes, the app. A missing note shows "Thu 09:30 · note not found".
- While a transcript runs it is the first row, with a red dot: "Recording · 12:34 · Teams", then "Finishing (3 left)" and "Detecting speakers…".
- Under the list: **Add notes…** and **Open meetings folder**.
- A right click on a row: Open note, Remove note from list…, Move file to Trash….
- Empty list: "No meetings yet", and "Every transcript is added here. For notes made before this version, use Add notes…".
- The chosen meeting is remembered with the window's state (the app's preferences), like the section.

## 6. A finished meeting

**Top**
- The name, as an editable title. It is saved on Enter or when the field loses focus; empty means no name (§8).
- The app, the date and time, the duration, as small labels.
- Copy (the note without its front matter, as the menu's Copy did), Open note (in the app that opens `.md` files), and a ⋯ menu with Remove note from list… and Move file to Trash….

**People**
- One row per person who has lines, in order of their first line: a colour dot with initials ("P1" for Person 1), a name field, the share of words, Merge into, and a ⋯ menu with **Delete all their lines…** (2026-11-19).
- A click on the row (the dot, the share or an empty spot; not the name field or the menus) highlights every line of that person in the transcript with their colour, and a second click turns it off; several people can be highlighted at once. **Only highlighted people**, a checkbox above the transcript (off while nobody is highlighted), hides the other lines and the ⚠ lines (2026-11-19, the author).
- The name field shows the label as its placeholder ("Person 1"). While typing, a list opens with the names Shepit knows from all meetings (names given here, labels that are names, "you"), newest meeting first, matched also across scripts. It is saved on Enter or when it loses focus; empty puts the label back.
- A name another person of this meeting already has asks: "Olena K. is already in this meeting. Merge Person 3 into Olena K.?" with Merge and Cancel.
- **Merge into** lists the other people of the meeting. All lines of this person go to the chosen one, and the row goes away.
- The "you" row has the name and "you", and no Merge into. Its name can be changed for this note. Others can be merged into you (your own voice heard through the call audio).
- **Reset people…** under the rows asks first, then puts every line back to the person speaker detection gave it (for a note added by hand: as it was when added). Names given to people stay. It is off when nothing differs.
- The share is the person's words over all words; ⚠ lines and failed chunks (`⚠ не вдалося розпізнати`) don't count.

**Transcript** (its text read only)
- Every entry as "Name · 10:00:19" in small type, then its text. ⚠ lines (a capture that stopped, an interruption) are shown as plain notes.
- A click on an entry opens "Give this line to": the other people of the meeting, and **New person**, which makes the next free "Person N" and gives the line to them (for two voices that speaker detection put under one person).
- Under them, **Delete line** deletes it at once; **Delete all their lines…** on a person's row asks first: "Delete all lines of Person 3? 12 lines leave the note and Shepit, with their voice samples. This can't be undone." (the author's pick, 2026-11-19: a hello that everyone said can't be given to anyone.) A deleted entry leaves the note from its header to the next entry; its row, words and voice sample leave the database in the same transaction, and a later line of the same second moves up to the place it now has in the note. Only lines paired with the note as it is then are deleted.
- An entry the window can't pair with the database (§8) is shown with the label the note has and can't be given.
- The text is the note as it is now: read when the meeting is opened, when the window becomes active again, and after every change.

**A missing note:** instead of People and Transcript, "The note was moved, renamed or deleted:" with its last path, **Locate note…** (a file chooser; the chosen note becomes this meeting's note and its entries are paired again) and **Remove note from list…**.

## 7. The meeting being recorded

Mockup 3.
- The name with a red dot, and a red Stop.
- Tiles: Time, Words (both sides so far), Phrases waiting, Your microphone (Muted, On, or "–" when the call app's button can't be read).
- **Live transcript:** the entries written so far with their live labels (your name, `Співрозмовники`), newest at the bottom. It follows new entries unless the author has scrolled up.
- While finishing or detecting speakers: that state as text in place of Stop.
- When the transcript is ready the row turns into a finished meeting and stays chosen; the people appear.
- The name can't be changed while recording: it is part of the file name of a note that is still being written.

## 8. Changes and the note

Every change goes into the note and the database together, or into neither. A write that fails shows the path and the error, and nothing changes.

**People and lines** (name, merge, give a line, new person, reset)
- The headers of the lines that change get the new label: the person's name, or the label speaker detection gave when the person has no name. Only those headers; the text, other headers and the front matter stay as the author left them.
- The note is read again right before writing, and written through a temp file and a rename (as after speaker detection today).
- **Pairing** of the note with the database: the k-th header with timestamp T is the k-th line with T. When the author added or deleted entries in a second, the counts differ and that second's entries are left alone (meeting spec §5.5).
- A header label typed by hand in Obsidian is not read back. The window shows the person the database has; that header is rewritten only when its line is changed in the window.

**The meeting's name**
- The database gets the new name.
- The front matter's `title` line is rewritten; it is added after `time` when missing and removed when the name is emptied. Nothing else in the front matter changes.
- The note file is renamed: the file name part of `meetingFileName`, filled again with the new name and the meeting's start and app, in the folder the note is in now, with ` (2)`, ` (3)` added when taken. A template without `{title}` leaves the file name as it is.
- `meeting-names.json`: the entry with this meeting's start gets the new name (added when it had none, removed when emptied), so a repeating meeting is offered the corrected name next time.
- A missing note changes only the database and `meeting-names.json`.

**Removing**
- **Remove note from list…** asks: "The note stays. Names given here and Reset people are lost; Add notes… adds the note again with the labels it has." Then the meeting leaves the database.
- **Move file to Trash…** asks with the file's name, moves the note to the Trash and removes the meeting from the database.

## 9. Elsewhere in the app

- **Menu:** Copy last meeting transcript, Rename speakers…, Rename speakers in another note… and Open meetings folder go. Start and Stop meeting transcript stay.
- **Recording card** in the sidebar: opens Meetings with the running transcript chosen.
- **"Transcript ready" panel:** Name people opens the window on that meeting.
- **Home:** unchanged.
- **`last-meeting`:** no longer written or read; the database knows the newest meeting. The file left by earlier versions is deleted at launch.
- **The rename dialogs** and the note chooser of "Rename speakers in another note…" are removed.
- **The call app** is a `CallApp` from window detection to the database, not a string (`docs/future-ideas.md`, "Call offer: left open", Structure). `settings.json` keeps its strings; the two name lookups (menu Start, call panel) are left as they are.
- **README:** the Meetings section, Add notes… for older notes, the database file under privacy, and that `--purge` deletes it.

## 10. Structure

- `ShepitCore` (pure, tested):
  - Reading a note: front matter fields (`date`, `time`, `title`, `app`) and entries (label, timestamp, text, line number); setting the labels of given entries; setting or removing the `title` line. Built on `MeetingNote` and `Speakers`.
  - `MeetingStore`: the database of §4 (schema, add, list, remove, relink, rename, the person and line changes, names used in other meetings).
  - What the window shows, as data: list groups and row texts, people rows with shares, transcript rows (paired or not), and each change turned into new note text plus a database update.
  - The new file name for a rename (`MeetingFileName`); renaming an entry in `MeetingNames`.
- `Shepit`: `MeetingsSection` (list, finished meeting, running meeting) in `Window/`; adding meetings at ready, quit and crash, and the actions, in `AppHost+Meetings`; the chosen meeting in `WindowNavigation`; the menu items and rename dialogs removed.
- `MeetingSession` gives the words so far and the entries it wrote (label, time, text) for the live view; the mute state comes from `MuteWatch`.

## 11. Tests and manual checks

Unit tests: reading notes (front matter with and without `title` and `app`, CRLF, escaped lines, ⚠ lines, no headers); header changes touch only the given entries; pairing with entries added and deleted in Obsidian; the `title` line set, added, removed; the database (a new file, each way of adding, order, rename, name, merge, give, new person, reset, remove, relink, suggestions leave out this meeting, data kept after reopening); list groups and row texts (this week, last week, months, the running states, a missing note, no name); shares; the rename file name (with and without `{title}`, subfolders in the template, a taken name); the `meeting-names.json` entry renamed; the menu without the removed items.

Manual (added to `docs/manual-test-checklist.md` as L1–L13):
- L1 A real call: the running meeting first in the list with time, words, waiting phrases and mute; live entries; Stop, finishing, people.
- L2 Name people; the note in Obsidian shows only the headers changed.
- L3 The same name for two people asks to merge; Merge into; Reset people brings the lines back and keeps the names.
- L4 Give a line; New person.
- L5 Rename a meeting: the file renamed in its folder, the front matter `title`, the new name offered at that time next week (or by a second transcript started at the same time of day).
- L6 Edit an entry's text in Obsidian while the meeting is open: the window shows it on return; a change in the window keeps the edit.
- L7 Delete an entry in Obsidian: that second's entries can't be given; the rest work.
- L8 Move the note in Finder: "note not found"; Locate note….
- L9 Add notes… with the old notes; a file that is not a transcript is skipped; adding again skips them all.
- L10 Remove note from list; Move file to Trash (the note is in the Trash).
- L11 Name people from the "Transcript ready" panel; the recording card opens the running meeting.
- L12 Quit during a transcript: the meeting is in the list after the next launch, marked interrupted in the note.
- L13 The menu has no Copy last meeting transcript, Rename speakers or Open meetings folder.

## 12. My calls (not confirmed one by one)

- The database keeps no transcript text; the window reads the note each time.
- Names are saved on Enter or when the field loses focus, not on each key: a meeting's rename renames a file.
- Typing a name another person of the meeting has asks to merge (the old dialogs merged silently).
- "New person" in Give this line to.
- "You" can't be merged into another person; others can be merged into you.
- Reset people keeps the names given to people.
- Header labels typed by hand in Obsidian are not read back.
- Renaming a meeting also renames its entry in `meeting-names.json`.
- List groups: This week, Last week, then months.
- A meeting without a name is "Teams call", "Zoom call", "Meet call" or "Meeting".
- Import names… came in part 8 (`2026-11-20-import-names-design.md`).
- `last-meeting` goes, and its leftover file is deleted.
- The running meeting's name can't be changed until the transcript is ready.
- Both removals ask first.
- The chosen meeting is remembered across window closes and restarts.
- The call app becomes a `CallApp` in the meeting code (the structure note left for this part); the rest of that note stays open.
- The duration of a note added by hand or after a crash runs to its last entry.

## 13. Open questions for the plan

- Whether the list column is a nested `NavigationSplitView`, an `HSplitView`, or a fixed-width list as Settings has.
- Whether a `LazyVStack` keeps a two-hour transcript (about 1500 entries) smooth.
- A note in iCloud Drive that macOS has offloaded is downloaded on read; whether opening such a meeting needs a progress mark.
