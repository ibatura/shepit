# Main window, part 6 (Import names): implementation plan

**Goal:** Import names… in a finished meeting reads a Teams or Zoom `.vtt` of that meeting, finds where the file sits in it, and offers each person the file's name in a sheet. Apply names names them, and merges two people of one voice, in the store and the note together.

**Architecture:** Everything that decides is pure and unit-tested in `ShepitCore`:
- `SpeakerTranscript` reads a `.vtt` into cues (start, end, speaker) and drops the text.
- `NameImport` lines the cues up with the meeting's lines in whole seconds: every shift is tried and one must clearly win. It matches people to speakers and builds the sheet: rows, merges, speakers nobody matches, and what Apply changes.
- `MeetingStore` gets one read: each line's person, start and length.

The app gets the button, the file picker, `ImportNamesSheet`, and `MeetingsModel.importNames` and `applyNames`. Applying changes the meeting through `MeetingStore.change`, as typing names does.

**Spec:** `docs/superpowers/specs/2026-11-20-import-names-design.md` ("the spec"; section numbers refer to it). Look: `docs/superpowers/specs/2026-11-11-visual-style/` (`visual-style.md` §5.2; `mockups.html` screen 2). Builds on `2026-11-14-meetings-design.md` §8 (the store and the note changed together) and `2026-11-17-voices-design.md` §5 (a name belongs to a person).

**Branch:** `import-names`, cut from `main`; the docs commits of 2026-11-20 are already on it. When it is ready, ask the author whether to open the pull request. Push the branch and open it only after they say yes. The author merges it in GitHub; Claude never merges.

## Execution notes

- **Style: Ponytail (full)** for every task (`~/.claude/skills/ponytail`): the smallest complete change, a test for every non-trivial branch, no options nobody asked for.
- **Review per task:** check each task's diff against the Ponytail rules. Tasks 2 and 4 also get `/code-review` on their diff: the alignment, and the change to the store and the note.
- **Review at the end (Task 6):**
  - The author runs `/thermo-nuclear-code-quality-review` on the branch; only the author can start it.
  - Then `/code-review` and `/security-review` on the whole branch.
  - Show the findings to the author as a list; the author picks what to change.
- One task at a time, with a commit per task and a short message. `make test` must be green after each task (625 tests on 2026-11-20).
- Tests first for everything in `ShepitCore`.
  - Tests use databases and notes in temporary folders, never `~/.local/share/dictation` or the author's meetings folder.
  - `.vtt` text in tests is made up: no names or lines from the author's files.
- The author's own `~/.config/dictation/settings.json` is not changed by code or tests.
- **Call content is confidential.**
  - On the author's files and meetings, report counts and percentages only. Call people "person 1, 2…" and speakers "speaker 1, 2…"; no names, no text.
  - The author's `.vtt` files stay in Downloads: read them with `python3 -I` or through the app, and never copy them into the repository or the scratchpad.
- Ask before installing: it restarts Shepit, and a transcript may be running.
- Task 4: look at the sheet in light and dark before the commit. The quick way is a scratch render test: an `NSHostingView` in a window, cached to a PNG in the scratchpad, and deleted before the commit.
- **Author gates:** Task 4 (the sheet on real meetings) and Task 6.

## Global constraints

- **The file:**
  - Read only after the author picks it, and never written, moved or copied.
  - Its path and text are not stored, logged or put in `stats.sqlite`.
  - The cue text is dropped while the file is read.
  - Cues and names live in memory only while the sheet is open.
- **Apply names** is one `MeetingStore.change`: the ticked merges first, then the ticked names. The store and the note's headers change together, or neither does. Nothing changes before Apply names, and Cancel changes nothing.
- **Names:**
  - A name is applied through `setName`, exactly as typing it in Meetings is: it links to the person with that name, from any meeting, or to a new person.
  - You are never renamed or merged away.
  - A person who already has a name, or was recognised by voice, changes only when the author ticks it.
- **Speed:** matching runs off the main thread, and takes well under a second in release for a 2-hour meeting against a 2-hour file.
- No network, no new permission, no new setting.
- Standard SwiftUI controls and SF Symbols, English labels in sentence case, texts as in the spec.

## Review focus

1. **Privacy:** nothing of the file is kept, logged or copied; the cue text never leaves the parser. Tasks 1 and 4.
2. **Lining up is right** (Task 2):
   - every shift is tried, negative ones included;
   - a file of another meeting is refused;
   - lines without `seconds` are timed by their words;
   - lines with no speaker are left out.
3. **The suggestions are careful** (Task 3):
   - only people with no name are ticked;
   - a name given by the author or by a voice changes only when ticked;
   - the holder rule decides which person gets a speaker's name;
   - You are left alone;
   - a name that clashes keeps Apply off.
4. **Applying is atomic:** with a note that can't be written, nothing changes. Task 4.
5. **Cost:** the time to match a 2-hour meeting. Task 2.

## File structure

```
app/Sources/ShepitCore/
  SpeakerTranscript.swift   new: a .vtt into cues (start, end, speaker), or why it can't be (Task 1)
  NameImport.swift          new: lining up and matching (Task 2); the sheet and what Apply changes (Task 3)
  MeetingStore.swift        timedLines: each line's person, start and length (Task 2)
app/Sources/Shepit/Window/
  MeetingsModel.swift       importNames (picker, read and match off the main thread), applyNames (Task 4)
  ImportNamesSheet.swift    new: the sheet (Task 4)
  MeetingsView.swift        the Import names… button in FinishedMeeting; NameField no longer private (Task 4)
app/Tests/ShepitCoreTests/
  SpeakerTranscriptTests.swift, NameImportTests.swift   new (Tasks 1–3)
  MeetingStoreTests.swift   timedLines (Task 2)
app/Tests/ShepitTests/
  MeetingsModelTests.swift  applying names and merges (Task 4)
```

---

### Task 1: Read a .vtt

- [ ] Tests first for `SpeakerTranscript.cues(_ text: String) throws -> [Cue]`. A `Cue` is start, end and speaker, with times in seconds from the file's start; it has no text field.
  - **Teams:** an id line, the timing line, and `<v Olena K.>text</v>` over one or several lines, with or without `</v>`. The speaker is the tag's name, trimmed and as written: "Olena K. (Guest)" stays as it is (spec §2).
  - **Zoom:** a number line, the timing line, and `Olena K.: text`. The speaker is what comes before the first `: ` of the first text line, so a colon later in the text doesn't count. A cue with no `: ` has no speaker and is left out.
  - **Both:**
    - a UTF-8 BOM, CRLF line ends, and timings without hours (`12:04.320`);
    - settings after the timing (`align:start position:0%`);
    - a header line after `WEBVTT`, and `NOTE` blocks.
  - **Refused:**
    - text that doesn't start with `WEBVTT` (after a BOM), the empty file included: "This isn't a WebVTT transcript.";
    - WebVTT where fewer than half the cues name a speaker: "This transcript has no speaker names." Zoom's captions file has no names, but a colon in the text of a few cues.
- [ ] `SpeakerTranscript` in `ShepitCore`, with the two errors as a `LocalizedError`.
- [ ] Commit `Shepit: read speakers and times from a Teams or Zoom .vtt`.

### Task 2: Line the file up with the meeting

- [ ] Tests first for `MeetingStore.timedLines(_ meeting: Int) -> [NameImport.Line]`, on a temporary store. A line is its current person, its start in seconds from the meeting's start (from `MeetingNote.date` of its timestamp), and its length.
  - The length is `seconds` where the line has it, else half a second per word; at least half a second either way.
  - Lines whose person is the call label (`MeetingNote.callLabel`) are left out.
  - A line counts under its person now: after a give, a merge and a reset.
- [ ] Tests first for `NameImport.align(_ lines: [Line], _ cues: [SpeakerTranscript.Cue]) -> Alignment?`. An `Alignment` holds:
  - `shift`: the meeting second at which the file's 00:00 falls, negative when the file started first;
  - `matches`: for each person with a clear match, the speaker, the share and the seconds shared;
  - `speakers`: the file's speakers in order of their first cue.

  Cases:
  - **Ownership:** each second has one owner on each side. On the meeting side it is the person whose line covers it, the later line where two overlap; on the file side, the speaker whose cue covers it.
  - **Shift:** a made-up meeting of 30 minutes (three people and You), and a file made from the same turns.
    - Cut to start 20 minutes in: shift 1200.
    - Starting 40 s before Shepit: shift -40.
    - The turns' edges moved by up to a second: the same shifts.
  - **Refused:** another meeting's file gives nil, for example the same people's turns in another order. The rule: every shift more than 60 s from the best must score below 90% of it. Make the two numbers constants, with a comment pointing to spec §11.
  - **Match:** a person's match is the speaker they share most seconds with, with its share of all the seconds they share. It is clear at 50% and 5 s; at 49%, or at 4 s, there is no match.
  - **Ties:** equal scores pick the shift nearest to 0.
- [ ] `NameImport.align`: two arrays of owners, one entry per second, and the score of each shift summed over the file seconds that fall inside the meeting.
- [ ] Measure the speed in release with a scratch test, deleted before the commit, run with `swift test -c release --filter`: 2 hours of made-up lines (6 people) against a 2-hour file (12 speakers). Report the time. If it isn't well under a second, tell the author before changing the method.
- [ ] `/code-review` on the task's diff.
- [ ] Commit `Shepit: line a transcript file up with a meeting`.

### Task 3: The sheet's suggestions

- [ ] Tests first for `NameImport.sheet(file: String, alignment:, people: [MeetingStore.Person], order: [String], you: String?) -> Sheet`. `order` is the people with lines, in the meeting's order.
  - **Subtitle:**
    - "From Daily.vtt · the file starts 12:04 into the meeting";
    - "From Daily.vtt · the file starts 0:40 before the meeting";
    - an hour or more as 1:02:04.
  - **Holder:** when several people match one speaker, the one who shares most seconds with it holds it. On a tie, the first in `order` holds it.
  - **Rows:** one per person in `order` except You.
    - Holds a speaker and has no name: the speaker's name and share, ticked.
    - The same name, compared with `Names.fold` (case, accents and script, as people are linked): "already named", no checkbox.
    - Another name, one recognised by voice included: the file's name, "now Marko D.", unticked.
    - No clear match, or matches a speaker someone else holds: an empty field, no share, unticked.
  - **Merges:**
    - A person with no name who matches a speaker held by a Person N: "Merge Person 4 into Person 1: both are Olena K. in the file", ticked. The holder's name stands in for "Person 1" when it has one.
    - Held by You: "Merge Person 4 into you: that's you in the file", ticked.
    - A person with a name who isn't the holder: no merge.
    - You matching a speaker a Person N holds: nothing for You.
  - **Also in the file:** the speakers nobody holds, by first cue.
- [ ] Tests first for `NameImport.clashes(names: [String: String], people:, you:) -> Set<String>`. It returns the keys whose ticked name another person of the meeting will also have after the import. That other person is either someone not renamed by the import (You's name included) or another ticked row.
- [ ] Tests first for `NameImport.changes(names:, merges:) -> (merges: [(String, String)], names: [(String, String)])`, what Apply does:
  - the ticked merges, then the ticked names;
  - each name made one line and trimmed (`MeetingPage.name`), and empty names skipped;
  - no name for a person who is merged away.
- [ ] Commit `Shepit: the import's suggestions, merges and changes`.

### Task 4: GATE: Import names… in Meetings (with the author)

- [ ] `MeetingsModel.importNames()`:
  - **Picker:** an open panel for `.vtt` files, "Choose the transcript file Teams or Zoom saved of this meeting", prompt "Import", starting in Downloads.
  - **Reading:** the file is read, parsed and lined up off the main thread; the store's reads (`timedLines`, `people`) stay on the main thread, as the section's other reads do. While it works, the button shows a spinner.
  - **Errors:** each shows a notice "Can't import names from <file name>" with the reason: not WebVTT, no speaker names, not readable as UTF-8, or "This transcript doesn't line up with this meeting."
  - **Result:** the sheet's model (the meeting and the `Sheet`), while the sheet is open.
- [ ] `ImportNamesSheet` (`Window/ImportNamesSheet.swift`):
  - The title and subtitle.
  - **Rows:** each has the person's colour and label as in the People box; `NameField` (no longer private), filled with the file's name and with every meeting's names as suggestions; the share; and the checkbox, or "already named". Show "now Marko D." when the person has another name.
  - Typing a name ticks the row, and emptying it unticks it.
  - **Clash:** a row whose name clashes shows "Another person here is called Olena K.", and Apply names is off while that row is ticked.
  - **Merge rows** have checkboxes; below them, "Also in the file:".
  - **Buttons:** Cancel, and Apply names (the default button), off while nothing is ticked.
  - Apply names first ends editing in the sheet (the window's first responder set to nil), so a name typed just before clicking counts.
- [ ] `MeetingsModel.applyNames(_ meeting: Int, _ changes:)` makes one `change(meeting) { merges; names }`, as `merge` and `name` do. Then the sheet closes and the page is read again.
- [ ] The Import names… button in `FinishedMeeting`, after Open note (style spec §5.2). It is off when the note is missing.
- [ ] Tests in `ShepitTests`, with a temporary store and note:
  - applying a name and a merge changes the store and the note's headers together;
  - with the note unwritable, nothing changes and the notice shows;
  - a sheet closed with Cancel changes nothing.
- [ ] Look at the sheet in light and dark (a scratch render, deleted before the commit).
- [ ] `/code-review` on the task's diff.
- [ ] **With the author** (ask before installing): install, then the author imports three files.
  - The 20 Nov file into its meeting: every row says "already named".
  - The 29 Oct file into its meeting: names are offered. The author checks a few against who spoke, and applies them or not.
  - The 28 Oct file into the 29 Oct meeting: refused.

  Report in counts only, and change what the author asks.
- [ ] Commit `Shepit: Import names… in Meetings`.

### Task 5: Docs

- [ ] README, under "Meetings in the window": Import names…, covering
  - Teams and Zoom `.vtt` only;
  - the file is only read, and only names are taken;
  - what the sheet shows;
  - when a file is refused (another meeting's file, or a file of a few minutes).

  The privacy section: nothing of the file is kept.
- [ ] `docs/manual-test-checklist.md`: I1–I8 from spec §10, plus I9: type a name and click Apply names at once, and the name is saved.
- [ ] The style spec's §5.2, and the meetings and voices specs' non-goals, point to this spec. The Import names… button is no longer "not shown".
- [ ] Commit `Docs: Import names`.

### Task 6: GATE: the author's checks and reviews

- [ ] I1–I9 with the author on the installed app. I7 waits for a Zoom call: it goes to `docs/future-ideas.md` as left open.
- [ ] The end-of-branch reviews from the execution notes, and the whole diff against the Review focus list. Fix what the author picks.
- [ ] Update `docs/future-ideas.md` (item 8 done; left open: I7, Teams `.docx`, the Meet `.txt` format) and "Where things stand" in `CLAUDE.md`.
- [ ] Ask the author whether to open the pull request. Push and open it, with a description of what changed and how it was checked, only after they say yes.

---

## Open questions to raise when the task starts (not blockers)

- Task 2: the 90% and the minute were settled on two meetings. If I1 or I2 disagree on other files, the author decides.
- Task 4: a person whose merge is ticked keeps an empty, unticked row. Settle with the author on the look whether to hide that row instead.
- Task 4: whether the picker should remember the last folder instead of always opening Downloads.
