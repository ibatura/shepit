# Main window, part 5: Voices and People

Date: 2026-11-17
Status: Draft, for the author's review
Look and screens: `2026-11-11-visual-style/visual-style.md` ("the style spec") §5.2, §5.5, and `mockups.html` screens 2 and 6.
Builds on: `2026-11-14-meetings-design.md` ("the meetings spec"): the meetings database, people, lines, merge, give a line, reset.

## 1. Intent

Today every remote voice of a meeting is "Person 1", "Person 2" until the author names it, in every meeting again. This part makes Shepit remember voices: when Remember voices is on, each line of a transcript keeps a voice sample, a person's voice print is made from the lines that are theirs now, and a later meeting names the people it recognises on its own. Every correction the author makes (naming, merging, giving a line to someone else) changes which lines are whose, so it changes the print too: prints get better with use and a wrong correction undone takes its samples back out.

The People section, a placeholder today, becomes the place for everyone named in meetings: their voice, their meetings, how much they talked, and renaming, merging and deleting.

## 2. Decided by the author

2026-11-11 (style spec §2, §5.2, §5.5, §8; `docs/future-ideas.md` "The main window"):
- Voice prints are a setting, `rememberVoices`, off by default. Saved voices can be seen and deleted, one by one or all.
- A person recognised by a saved voice gets the name at once, marked "recognised by voice"; the name can be changed like any other.
- The print of a person who got no name is deleted after 30 days. Fixed, not a setting.
- A People section in the sidebar for saved voices, not a place inside Settings. Per-person word counts live with the saved voices in the meetings database, never in `stats.sqlite`.

2026-11-17 (`docs/future-ideas.md`, "Voice prints that learn"):
- Two saved voices can be merged into one (the same person saved twice, or under two names).
- A print improves from the author's corrections: naming, merging people, giving a line to someone else.
- Voice prints are biometric data: only on this Mac, never in `stats.sqlite`, each person and all of them deletable.

2026-11-17, for this spec:
- **Samples only while Remember voices is on.** Nothing biometric is kept while it is off; meetings recorded then can't feed prints later.
- **Merging two voices renames the person in older meetings too:** every meeting where she is "Olena" gets "Olena K." in the database and in the note's headers, so one name is one voice everywhere.
- **Earlier meetings are suggested, not changed:** when a voice is saved or its print changes, the People section says the person may be in other meetings, and names them there only on a click.
- **The People section also has:** renaming a person, who talked how much, a person's meetings, and the author's own voice from the microphone.

## 3. Goals, non-goals, anti-goals

**Goals**
- `rememberVoices` in the People section; while on, a voice sample per transcript line, kept in `meetings.sqlite`.
- Prints made from samples; recognition when a transcript is ready; "recognised by voice" in the Meetings section.
- The People section: everyone named in meetings, their voice, meetings, talk time and words; rename, merge, delete a voice, delete all voices; suggestions for earlier meetings.
- The author's own print from the microphone.
- A debug command that tells how well recognition works on the author's stored samples, in counts only.

**Non-goals**
- Import names from a Teams, Zoom or Meet transcript (part 8).
- Giving lines speaker detection could not place (`Співрозмовники`) to the nearest voice (`docs/future-ideas.md`, "Lines speaker detection could not place").
- Speaker labels during the call (set aside: detection needs the whole call).
- Samples for meetings recorded before this version, or with Remember voices off, or added with Add notes…: their audio is gone.
- Statistics: Statistics → Meetings stays as it is; who talked how much is in People.
- Sharing or exporting prints.

**Anti-goals**
- Any sample or print leaving the Mac, or kept anywhere but `meetings.sqlite` in `databasesFolder`.
- Any sample written while `rememberVoices` is off.
- Keeping call or microphone audio after the transcript is ready (meeting spec §5.5): samples are taken before the audio is deleted, and are numbers, not audio.
- A note or a meeting changed by a suggestion the author didn't click.
- Names or words in `stats.sqlite`.

## 4. Voice samples

**What a sample is.** 256 numbers (a WeSpeaker embedding, about 1 KB) describing the voice of one transcript line. It can't be turned back into audio or words.

**Where it comes from.** Speaker detection already runs FluidAudio's offline diarizer over the call audio after Stop. Each segment it returns carries the centroid of its whole cluster, the same numbers for every line of Person 1, so those can't follow a single line. With `exposeChunkEmbeddings` on, the diarizer also returns an embedding per 10-second window and voice (windows step by 2 s), with the cluster it went to. A call line's sample is the normalised mean of the window embeddings of its own cluster that overlap the line. A line with no such window (too short, or detection put no voice there) has no sample.

**The author's lines.** The microphone audio is written to the session folder like `call.wav` while Remember voices is on, and deleted with it. After Stop the same models give the microphone lines their samples. To keep Stop quick, only the first minutes of the author's speech are used (how many: §12).

**When.** Only while `rememberVoices` is on, and only for meetings Shepit records itself. The samples are written with the meeting's lines when the transcript is ready, in the same transaction.

**How long.**
- A sample whose line belongs to a named person (or to the author) stays until the meeting leaves the list, that person's voice is deleted, or Delete all voices….
- A sample whose line belongs to a person with no name is deleted 30 days after its meeting started (checked at launch and when a transcript is ready).
- Remove note from list… and Move file to Trash… delete the meeting's samples with it.

## 5. People, prints and recognition

**A person** is a name given in meetings, the same name ignoring case and spaces at the ends. Olena K. in three meetings is one person with three meetings. The author is a person too ("You"), whatever label their lines have in each note.

**A print** is not stored on its own: it is made from the samples of every line that belongs to that person now. So:
- naming Person 2 "Olena K." adds Person 2's lines to Olena K.'s print;
- merging people, or giving a line to someone else, moves those lines' samples with them;
- Reset people, renaming back, or giving a line back takes them out again;
- deleting a meeting takes its lines out.
A print is used for recognition once it has samples from at least one meeting and enough speech (how much: §12).

**Recognition** runs when a transcript is ready, after speaker detection, while Remember voices is on:
- Each Person N of the new meeting is compared with every print (the mean of Person N's line samples against each print, or against each print's nearest samples: §12).
- A person whose best match passes the threshold, clearly ahead of the second best, gets that name. Two people of one meeting can't get the same name: the closer one gets it.
- A match with You merges that person into the author's row (the author's voice heard through the call audio), as the meetings spec's merge does.
- The note's headers get the names, as when the author names someone (meetings spec §8), and the person is marked "recognised by voice" in the database.

In the Meetings section a recognised person's row shows "recognised by voice" under the name. Changing the name, merging or Reset people works as for anyone; a changed name drops the mark.

## 6. The People section

Mockup 6, grown into a section with a list and a person.

**Top:** the **Remember voices** switch with its explanation ("Keeps a voice print for each person you name, so they are named in later meetings. Stored on this Mac only."). Turning it off stops samples and recognition; saved voices stay until deleted, and the explanation says so. **Delete all voices…** beside it asks first, then deletes every sample.

**The list:** every person named in at least one listed meeting, You first, then by the last meeting, newest first. A row: the colour dot with initials, the name, "6 meetings · last 10 Nov", and a voice mark when the person has a print ("Voice saved", or nothing).

**A person**, chosen in the list:
- The name as an editable title. **Rename** gives the new name in every meeting where the person is, in the database and the notes' headers (meetings spec §8), and in the name suggestions. A name another person has asks: "Marko D. is already in People. Merge Olena into Marko D.?"
- **Merge into…** lists the other people. Every meeting with this person gets the other name; in a meeting that has both, this person's lines go to the other, as a merge in the Meetings section does.
- **Voice:** "Saved from 6 meetings" with **Delete voice…**, or "No voice saved" (Remember voices off, or no samples). Delete voice deletes the samples of this person's lines; the name stays in the meetings, and new meetings start a new print once the author names them again.
- **Who talked how much:** for the period menu at the top (Dictations' and Statistics' periods): meetings, talk time and words, and the share of the words in those meetings. Talk time is known for meetings recorded from this version on; for older ones the row says "–".
- **Meetings:** the meetings the person was in, newest first, with date, name, talk time and words; a click opens the meeting in the Meetings section.
- **May also be in:** when the print matches an unnamed person of other meetings (those still holding samples, so at most 30 days old), a line "May also be in 3 meetings" with **Show…**: a list of those meetings with the Person N each, a checkbox each (all on), and **Name them**, which names the checked ones as the Meetings section does. A suggestion turned down by unchecking isn't shown again for that meeting's person.

**You** has no Merge into and no Delete in the list's ⋯; its Voice line says "From your microphone and the lines given to you". Its talk time and words are the author's.

Changes are written like every change of the meetings spec: the database and the notes together, or neither; a note that can't be written stops the change and says which.

## 7. The database

`meetings.sqlite`, upgraded to version 2 with `SQLiteFile`'s numbered upgrades (as `stats.sqlite` in the Statistics part):
- `lines` gets `words` (the entry's word count, not its text) and `seconds` (its talk time from the session's offsets; null for Add notes… and older meetings). `words` of meetings already in the list are filled the first time the meeting is opened in the window, when the note is read anyway.
- `people` gets `recognised` (1 when the name came from a voice).
- A new `samples` table: meeting, timestamp, order (the line's key, as in `lines`) and the 256 numbers as a blob. Deleted with its meeting.
- A new `declined` table: meeting and person key of suggestions the author unchecked.

Prints are read from `samples` joined with `lines` and `people`; the means are kept in memory and made again after any change.

## 8. Checking recognition

`Shepit voices-check` (a debug command like `call-watch`) reads `meetings.sqlite` and, for every person with samples in two or more meetings, asks: from the other meetings' samples, would this meeting's lines have been recognised, at thresholds from 0.3 to 0.8? It prints counts and rates only: no names, no text, people as "person 1, 2…". The author runs it after a few weeks of meetings to set the threshold (§12).

## 9. Elsewhere in the app

- **Meetings section:** "recognised by voice" under a recognised person's name; the name suggestions also list the People section's people.
- **Transcript ready panel:** the detail adds "2 of 4 people recognised" when some were.
- **Home:** unchanged.
- **Settings:** `rememberVoices` is set in the People section; History and privacy gets a line pointing there.
- **README:** what a voice print is, where it is, how to delete it. **uninstall.sh --purge** already deletes `meetings.sqlite`.

## 10. Structure

- **ShepitCore:** `VoiceSample` (256 floats, from and to a blob, cosine similarity, mean); `Voices` (pure: a line's sample from window embeddings, prints from samples, recognition with threshold and margin, suggestions); `MeetingStore` gains samples, recognised, words and seconds, rename and merge across meetings; `PeoplePage` builds the section's list, a person, talk time and words.
- **ShepitEngines:** `Diarizer` returns turns and window embeddings (`exposeChunkEmbeddings`); a call for the microphone's samples.
- **Shepit:** `MeetingSession` keeps `mic.wav` while Remember voices is on; `AppHost+Meetings` recognises and stores samples when a transcript is ready; `PeopleModel` / `PeopleView` in `Window/`; `Shepit voices-check`.

## 11. Tests and manual checks

**Tests (ShepitCore):** a line's sample from overlapping windows of its cluster only; prints follow naming, merge, give a line, reset and delete; recognition with threshold, margin and one name per meeting; You merge; 30-day deletion of unnamed samples; rename and merge across meetings write the notes' headers and the database together; nothing written with `rememberVoices` off; suggestions skip declined ones; talk time and words per period.

**Manual checks V1–V10** (`docs/manual-test-checklist.md`), on real calls:
- V1 Remember voices off: a meeting keeps no samples (`samples` empty for it).
- V2 On: name two people in a meeting; the People section lists them with "Voice saved".
- V3 A second meeting with one of them: the name comes on its own, marked "recognised by voice", in the note too.
- V4 Give a recognised line to someone else, then Reset people: the print follows (checked with `voices-check`).
- V5 Merge two people in People: older notes get the kept name.
- V6 Rename a person: every meeting and note follows.
- V7 May also be in: Show…, uncheck one, Name them.
- V8 Delete voice, then Delete all voices: samples gone, names stay.
- V9 Your own voice heard through the call (speakers, not headphones): merged into you.
- V10 Who talked how much and a person's meetings for Last month; a click opens the meeting.

## 12. To find out in the plan (on the author's meetings)

- The threshold and the margin, and whether a print matches better as one mean or as the nearest of its samples across Teams, Zoom and Meet audio. Start from FluidAudio's own defaults; settle with `voices-check` after a few weeks.
- How much speech a print needs before it is used.
- How many minutes of the author's speech give a good print without slowing Stop.
- How long speaker detection takes with window embeddings on, and how big `samples` grows per hour of meeting.

## 13. My calls (not confirmed one by one)

- A person is a name, the same ignoring case; there is no separate person id.
- The People section lists everyone named in meetings, not only saved voices, so a person's meetings and talk time work with Remember voices off too; the voice is one line of a person.
- Turning Remember voices off keeps saved voices until Delete all voices….
- A recognised You merges into the author's row on its own.
- One branch, built in this order so each step is usable: samples and prints, recognition, the People section, rename and merge across meetings, who talked how much, suggestions, your own voice.
