# Main window, part 6: Import names

Date: 2026-11-20
Status: Approved by the author on 2026-11-20. Afterwards, on the author's meetings, §5's test of whether a file lines up
with the meeting was changed from a share of covered speech to one clear best shift (§11).
Build order: item 8 in `docs/future-ideas.md` ("Planned, in this order"). Branch `import-names`.
Look and screens: `2026-11-11-visual-style/visual-style.md` ("the style spec") §5.2, and `mockups.html` screen 2 (the Import names… button).
Builds on: `2026-11-14-meetings-design.md` ("the meetings spec": people, lines, merge, the store and the note changed together) and `2026-11-17-voices-design.md` ("the voices spec": a name belongs to a person, prints follow names).

## 1. Intent

After a call, every remote voice is "Person 1", "Person 2" until the author names it, and Shepit can only recognise people it has heard named before. Teams and Zoom write their own transcript of the same call, with a name on every line. This part reads such a file, lines it up with the meeting by time, and offers the names: Person 2 is "Olena K." because, at the times Person 2 speaks, the file says Olena K. speaks. The author looks the names over and applies them; every name applied also feeds that person's voice print, so later meetings recognise them on their own.

On 2026-11-20 a Teams `.vtt` lined up this way agreed with Shepit's speakers on 79–98% of each one's time.

## 2. Decided by the author

2026-11-11 (style spec §2, §5.2, §8; `docs/future-ideas.md` "The main window"):
- Import the same meeting's transcript to take the participants' names from it. Files the author has: Teams `.vtt` and `.docx`, Zoom `.vtt`, Google Meet `.txt` written by a browser plugin.
- Import takes names only.
- The Meet `.txt` format is done last, from a sample the author sends.
- The button is Import names…, in a meeting's header next to Copy and Open note.

2026-11-20, for this spec:
- **Teams and Zoom `.vtt` in this part.** Teams `.docx` and Meet `.txt` come in later parts.
- **A sheet with suggestions, not names applied at once.** Each person gets the file's name and how well it fits; the author unticks or corrects, then applies.
- **Two people of one voice: offer to merge them.** When speaker detection split one voice in two and both line up with one name, the sheet offers the merge, ticked.
- **Names only.** Lines are not moved, not even lines with no speaker (`[Співрозмовники]`) or lines the file gives to someone else.
- **Names exactly as the file writes them**, with an addition such as "(Guest)" if the file has one: whatever name is there is the name (the author, 2026-11-20). The author can still edit it in the sheet.
- **A screenshot of Teams' speaker timeline is not read** (the author doubted it would work, 2026-11-20). Shepit has no vision model; reading the coloured bars by pixel would break with every change of Teams' layout, and a `.vtt` gives the same names with exact times. Recorded in `docs/future-ideas.md` under "Set aside".

## 3. Goals, non-goals, anti-goals

Goals:
- Name a meeting's people from a Teams or Zoom `.vtt` of that meeting in one sheet.
- Find where the file sits in the meeting without the author's help, even when the transcript was turned on late.
- Say plainly when a file is not of this meeting, or has no names.

Non-goals (later, or decided against):
- Teams `.docx`, Meet `.txt` (later parts).
- Moving lines, filling lines with no speaker, splitting one person into two.
- Importing many files at once, or finding which meeting a file belongs to.
- Reading the file's text into the note or the store.

Anti-goals:
- No network; the file is read only after the author picks it.
- No copy of the file, no record of its path, no text of it kept or logged.

## 4. The files

A `.vtt` (WebVTT) file is a list of cues: a timing line `00:12:04.320 --> 00:12:07.950` and text. The times are seconds from the file's own start; the file has no date or time of day.

- **Teams:** each cue has an id line (`<guid>/12-0`), the timing line, and text in a voice tag: `<v Olena K.>text</v>`, which can run over several lines. The speaker is the tag's name.
- **Zoom:** each cue has a number line, the timing line and `Olena K.: text`. The speaker is what comes before the first `: ` of the cue's text. A cue with no `: ` has no speaker (Zoom writes no name when it doesn't know one).
- Both: a UTF-8 BOM, CRLF line ends and timings without hours (`12:04.320`) are read. Names are trimmed and taken as written.
- A file that doesn't start with `WEBVTT`: "This isn't a WebVTT transcript." A WebVTT file with no speaker on any cue (the author has two such files, from 2025): "This transcript has no speaker names."

Only each cue's start, end and speaker are kept, in memory, while the sheet is open; the cue text is dropped as it is read.

## 5. Lining up and matching

**Shepit's side** is the meeting's lines as the store has them now, each with its current person (You included), from its timestamp for its `seconds`. Meetings listed before Voices have no `seconds`: there a line lasts half a second per word (lines that have both average 0.49 s a word). At least half a second either way. Lines with no speaker are left out.

**In whole seconds.** Each second of the meeting belongs to the person whose line covers it (where two lines overlap, the later one), each second of the file to the speaker of the cue that covers it. Shepit's timestamps are whole seconds, so a finer step buys nothing: tenths of a second around the best shift found the same matches on the author's meetings.

**The shift.** The file's 00:00 can be anywhere in the meeting: Teams starts its transcript when someone turns it on, and Shepit may have been started late. Shepit tries every whole-second shift at which the file and the meeting overlap and scores it: for each person, the seconds they share with the file speaker they share most with, summed over the people. The best score wins.

**Does it line up?** A file of this meeting lines up at one place only; a file of another meeting lines up about as well anywhere. So the best shift must score at least 10% more than every shift more than a minute away from it. Below that: "This transcript doesn't line up with this meeting." and nothing is offered. The share of the file's speech that lies on some Shepit line (the first idea) doesn't tell them apart: other meetings' files reached 75–91%.

**A person's match.** For each person with lines now, the file speaker they share most seconds with, and that speaker's share of all the seconds they share with any speaker. A match at 50% or more and at least 5 seconds. Below that the person has no clear match.

**One name, two people.** When several people match the same speaker, the one who shares most seconds with it holds it: a Person N gets the name, and every other Person N matching it is offered as a merge into the holder. When You hold it, they are offered as a merge into you (the author's own voice heard through the call). You are never renamed or merged: your name comes from Settings → Meetings, as today, and when a Person N holds the speaker You also match (the author's microphone hearing the call through speakers), You are left as you are.

**Speakers nobody matches** are listed by name in the sheet, with nothing to do.

## 6. The sheet

Import names… sits in a finished meeting's header next to Copy and Open note. It opens a file picker for `.vtt` files, starting in Downloads. While the file is read and matched the button shows a spinner; a 2-hour meeting should take well under a second (§11).

The sheet, in the window's style:
- **Title** "Import names", and below it "From `<file name>` · the file starts 12:04 into the meeting" (or "…starts 0:40 before the meeting").
- **One row per person with lines, except You:** their colour, their label or name now, a name field filled with the file's name (the Meetings name field, with suggestions from every meeting), the share ("92% of their time"), and a checkbox.
  - No name yet and a clear match: ticked.
  - Already named the same (ignoring case): "already named", no checkbox.
  - Named differently, or recognised by voice: the file's name in the field, the name now beside it ("now Olena K."), unticked.
  - No clear match: an empty field, unticked; typing a name ticks it.
- **Merge rows** under the people: "Merge Person 4 into Person 1: both are Olena K. in the file", or "Merge Person 4 into you: that's you in the file", ticked.
- **"Also in the file:"** the names of speakers nobody matched.
- **Cancel** and **Apply names** (the default button), off while nothing is ticked.

## 7. Applying

Apply names makes one change to the meeting (`MeetingStore.change`, meetings spec §8): the ticked merges first, then the ticked names, in the store and the note's headers together, or none of them. A name goes to the person who already has it, from any meeting, or to a new person, exactly as typing it in Meetings does (voices spec §5); prints follow names, so nothing else is updated. Imported names are not marked: the author confirmed each one.

Afterwards everything is as if the author had typed the names: they can be changed in Meetings or People, and Reset people undoes the merges (names stay, as today).

## 8. Privacy

- Shepit reads the file only after the author picks it, and never writes, moves or copies it.
- Its path and text are not stored, logged or put in `stats.sqlite`; times and names live in memory while the sheet is open.
- The names applied land in `meetings.sqlite` and the note, as typed names do. No network.

## 9. Structure

- **ShepitCore `SpeakerTranscript`:** reads a `.vtt` into cues (start, end, speaker), or says why it can't.
- **ShepitCore `NameImport`:** from the meeting's lines and people and the cues, the shift, whether it lines up, each person's match and share, the merges and the unmatched speakers. Pure, tested.
- **App:** `ImportNamesSheet` in `Window/` (a file of its own: `MeetingsView.swift` is 473 lines), `MeetingsModel.importNames` (picker, read off the main thread, apply through `MeetingStore.change`), and the button in `FinishedMeeting`. `MeetingStore` gets one read, each line's person, start and length (§5); `merge` and `setName` inside `change` do the rest.

## 10. Tests and manual checks

**Tests (ShepitCore):** Teams cues over several lines, a BOM, CRLF and timings without hours; Zoom names before `: `, a colon later in the text, a cue with no name; no names and not WebVTT refused; the shift found for a file that starts 20 minutes into the meeting and for one that starts before it; a file that lines up about as well a minute away refused; lines without `seconds` timed by their words; two people matching one speaker give a merge into the one who shares more; a Person N matching the speaker You hold gives a merge into you, and You matching a speaker a Person N holds changes nothing; You never renamed; already named the same, named differently and no clear match each set up their row as in §6; lines with no speaker left out. **App:** applying writes the names and merges to the store and the note together.

**Manual checks I1–I8** (`docs/manual-test-checklist.md`). The author has Teams `.vtt` files of two meetings in the store (29 Oct, 20 Nov) and of other meetings for I2 (the 28 Oct daily, and the 5 Nov one, which lines up with neither meeting of that day).
- I1 Import a meeting's Teams `.vtt`: the suggested names are who spoke (the author checks a few lines), Apply names, the note's headers get them.
- I2 A `.vtt` of another meeting, of the same team too: refused.
- I3 A `.vtt` with no speaker names: refused.
- I4 Two Person N of one voice: the merge is offered, ticked, and done.
- I5 A person named differently: unticked; tick it, apply, the name changes.
- I6 A name someone already has from another meeting: People shows one person with both meetings.
- I7 A Zoom `.vtt`: at the next Zoom call (the store has no Zoom meeting with a file yet).
- I8 Nothing kept: the file's path and text are in no database, setting or log.

## 11. Settled on the author's meetings (2026-11-20)

Read-only, in counts only: two meetings with their Teams `.vtt` (29 Oct, 46 minutes, 7 people; 20 Nov, 56 minutes, 4 people), and seven pairs of a file with another meeting, files of the same team's daily meetings among them.

- **The shift:** found on both (the file started 3:30 before Shepit on 29 Oct, 1:42 after it on 20 Nov), and on parts of the files cut to start 10, 20 or 30 minutes later.
- **Lines up:** on the two meetings the best shift more than a minute away scored 62–63% of the best; on 10-minute parts of their files 74–86%; on the seven other meetings' files 95–100%. Hence 10% (a ratio below 90%). A file of 5 minutes or less may be refused (86–96%), and so is a file that mostly lies outside the meeting.
- **Matches:** at 50% and 5 s every person of both meetings matched a speaker; on 20 Nov the three besides You already had names, and each was the file's name (shares 79–98%). The shares on 29 Oct were 56–94%. You matched a speaker held by a Person N once (29 Oct: 56% of 48 s against 726 s): left alone, as §5 says.
- **Line times:** the 20 Nov meeting has `seconds`; timed by its words instead it gave the same shift (±1 s) and the same matches.
- **Speed:** a plain Python loop over every shift took 1.3 s for an hour against an hour. Compiled Swift should be well under a second for two hours against two; the plan measures it in the app.
- **"(Guest)":** names are taken as written (§2).

## 12. My calls (not confirmed one by one)

- Import from a meeting's header only, one meeting and one file at a time.
- The shift search covers every overlap, not a fixed window around the start.
- No mark for imported names and no count in `stats.sqlite`.
- No new mockup: the sheet uses the window's existing controls. A mockup on request.
