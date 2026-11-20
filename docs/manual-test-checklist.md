# Manual acceptance checklist — Shepit

Date: 2026-10-24  Engine: whisper.cpp large-v3, then large-v3-turbo  Result legend: ✅ pass · ❌ fail (note what happened)

| # | Scenario | Expected | Result |
|---|---|---|---|
| N1 | Toggle: ⌥Space, speak 10 s Ukrainian with 2 English terms, ⌥Space (TextEdit) | Panel: 🔴 Слухаю + timer + meter + draft text; then ⏳; text pasted; terms in Latin || ✅ |
| N2 | Same with a 30 s dictation; time stop → paste; repeat in the Lua tool with the same model | Shepit ≤ ~6 s and not slower than Lua || ✅ 31 s → 2.77 s (large-v3); same clip Lua server 2.73–2.85 s vs Shepit 2.78–2.88 s |
| N3 | Mode ▸ Hold to talk; hold ⌥Space, speak, release | Text pasted; settings.json now has "mode": "hold" || ✅ |
| N4 | Hold mode: quick tap (< 0.3 s) | Nothing happens || ✅ after recorder fix (was "Nothing recognized": lost start audio) |
| N5 | Esc while recording | "Cancelled", nothing pasted; Esc works normally afterwards in other apps || ✅ |
| N6 | Paste into Terminal, a browser text field, Slack, VS Code | Text appears in each; clipboard restored afterwards || ✅ (⌘V within 1 s still pastes the dictation — restore delay, as in Lua) |
| N7 | Start recording in Slack, switch to TextEdit, stop | Text pasted into Slack || ✅ |
| N8 | Ukrainian keyboard layout active | Hotkeys and paste still work || ✅ |
| N9 | Record 2 s of silence | "Nothing recognized"; no «Дякую за перегляд!» pasted || ✅ |
| N10 | First word of a dictation started right after ⌥Space | Not cut off || ✅ after recorder fix (first audio: built-in 0.17 s, MOMENTUM 4 0.52 s; was 1–3 s) |
| N11 | ⌃⌥D with a word selected → type the right spelling → Додати | Rule in dictionary.json; next dictation uses it || ✅ |
| N12 | Recent ▸ click an entry | Full text copied, "📋 Скопійовано" || ✅ |
| N13 | Engine ▸ whisper.cpp large-v3-turbo (while idle) | settings.json gets "engines"; status "Ready — whisper.cpp large-v3-turbo" || ✅ |
| N14 | Break settings.json (delete a comma), save, open the menu | ⚠ line names the error; dictation still works with the last good settings || ✅ |
| N15 | Remove Shepit from Accessibility, dictate | Notice "Text copied — allow Accessibility…"; text on the clipboard; menu shows the Accessibility line || skipped (would need re-granting Accessibility) |
| N16 | Microphone ▸ pick another device; then unplug/turn off that device mid-recording | Recording continues on the default, or stops and transcribes what it has || ✅ continued on the MacBook mic |
| N17 | Rebuild (`scripts/build-app.sh`) and relaunch | Accessibility and Microphone still granted || ✅ (≈10 rebuilds during the session, permissions kept) |
| N18 | Start the Lua tool again (Hammerspoon ▸ Reload Config) | Within ~2 s Shepit shows "Hotkey taken"; ⌥Space reaches the Lua tool only || skipped — user: the Lua tool will be removed after the switchover |

## Meeting transcripts (phase 3)

Date: ____  Engine: whisper.cpp large-v3-turbo  Headphones: ____

| # | Scenario | Expected | Result |
|---|---|---|---|
| M1 | First Start on this Mac | macOS asks for System Audio Recording; after Allow the call is recorded ||
| M2 | Start → talk and play call audio 1 min → Stop | Note appears at once, fills a few seconds behind; after Stop `[Person N]` labels; menu shows recording / finishing / detecting speakers || ✅
| M3 | Note open in Obsidian during the call | Obsidian shows new lines as they come; an edit in a written line stays || ✅
| M4 | Name dialog: accept the detected name; empty; Cancel | Name in the file name and front matter; no name; Cancel → no file, no session ||
| M5 | ⌥Space dictation during a meeting | Pasted as usual, not slower; that speech is not in the transcript || ✅
| M6 | Switch output (headphones ↔ speakers) mid-call | Call audio continues after ~1 s; note keeps filling; on speakers the call is not repeated under your name (at most a few misheard lines) || ✅
| M7 | Turn off the Bluetooth headphones mid-call | Both streams continue on other devices, or a `⚠ … stopped` line and a notice; nothing hangs ||
| M8 | Quit Shepit mid-call | Asks first; Quit → note ends with `⚠ Запис перервано о …`; no audio left in `$TMPDIR/dictation` || ✅
| M9 | 1-hour call | "phrases waiting" stays low; speaker detection after Stop < 2 min; memory sane ||
| M10 | Copy last meeting transcript | Clipboard has the note without front matter || ✅
| M11 | Rename speakers… in the last note; same name for two Persons | Headers renamed and merged; text untouched || ✅
| M12 | Rename speakers in another note… on an older note | File chooser opens in the meetings folder; renamed || ✅
| M13 | Delete the speaker model (Settings → Meetings), run a meeting | Start works; notice that speakers won't be detected; labels stay `Співрозмовники` || ✅
| M14 | Delete the voice detection model | Start disabled with "(download the model in Settings)"; Download in Settings → Meetings fixes it || ✅
| M15 | Turn System Audio Recording off, run a meeting with 2+ min of your speech | Notice that call audio may not be recorded; your phrases are in the note || — skipped
| M16 | Settings → Meetings: type an invalid file name (`a:b`), then a valid one with `/` | Inline error, nothing saved; valid one shows the example and saves on Enter || ✅
| M17 | Statistics after a meeting | Meetings · hours tile counts it; Words chart stacks meeting words on dictation words || ✅
| M18 | Settings → Meetings → Block dictation during a meeting: on, press ⌥Space while recording; then off | On: no recording, a notice says dictation is off; off: dictation works as in M5 || ✅
| M19 | Settings → Meetings → File name: ⌘A, ⌘C, ⌘V, ⌘X, ⌘Z; the same in the meeting-name and Rename dialogs | Each works as in any Mac app || ✅
| M20 | Teams call: Start with the call window open; mute in Teams, speak, unmute, speak | Name dialog shows the meeting name; only the unmuted speech is under your name || ✅ 2026-11-04 Sprint Planning: name found in 1.2 s; muted speech left out; 4 speakers, 3 short lines mislabelled
| M21 | Zoom call, then a Google Meet call (meet.new, then one from Google Calendar): Start each; mute, speak, unmute, speak | Note says Zoom / Meet; the calendar Meet's name is in the dialog; muted speech left out || ✅ 2026-11-06: Zoom recorded as Zoom, no topic (Zoom shows none), mute from "Mute my audio"; Meet name from the tab and the page, mute from «Вимкнути мікрофон»
| M22 | Start a meeting, name it, Stop; a week later (or on 2 days for a daily one) Start at the same time | The dialog is prefilled with that name; ▾ lists recent names ||

## Call panel

Date: ____

| # | Scenario | Expected | Result |
|---|---|---|---|
| C1 | Start a call in Teams, in Zoom, in Google Meet (Chrome) | In each, one panel within 5 s with the call's name (Zoom: "Zoom call") || ✅ 2026-11-12: Teams, Zoom, Meet; the Teams pre-join title "Meeting join" is ignored since 2026-11-13 (the offer says "Teams call")
| C2 | Press Start transcript | Starts at once, no name dialog; the note has the panel's name || ✅ 2026-11-12: all three apps
| C3 | Leave the panel alone (`callOfferSeconds` 15) | Hides after 15 s; no second panel in this call; Start from the menu works || ✅ 2026-11-12 Teams
| C4 | `callOfferSeconds` 0, start a call | The panel stays until a button is pressed || ✅ 2026-11-12
| C5 | Start automatically on, start a call | Counts down 5 s, then the transcript starts || ✅ 2026-11-12 Teams
| C6 | Start automatically on, press Don't record | Nothing starts; no more panels in this call || ✅ 2026-11-12 Teams
| C7 | Press Not this call, stay in the call 1 min | No second panel || ✅ 2026-11-12 (author; the call was shorter than 1 min)
| C8 | Leave a call with a transcript running | "Call ended" counts down, then the transcript stops; in another call Keep recording leaves it running, with no second stop panel || ✅ 2026-11-12: stopped by itself in all three apps
| C9 | Switch headphones mid-call with a transcript running | No stop panel; the transcript goes on || ✅ 2026-11-12
| C10 | Dictate into another app with no call; then Start on a Teams pre-join screen and close it | No panel for dictation; after closing, the stop panel runs and no note is left || ✅ 2026-11-13: no panel for dictation; Start on the Teams pre-join screen, Cancel 19 s later: Teams released the microphone, "Call ended" counted down and the transcript stopped 15 s after Cancel (`Shepit call-watch`). The note stays when something was said. The run of 2026-11-12 did not repeat
| C11 | Two calls back to back: the second starts while the first transcript is still finishing (detecting speakers) | The second call's offer appears as soon as the first transcript is ready ||

## Main window: shell, Home, Settings

Date: ____

| # | Scenario | Expected | Result |
|---|---|---|---|
| W1 | Open the window from the menu (Open Shepit), by Settings… / ⌘,, and by launching Shepit again; move and resize it, pick sections, quit and start Shepit, open again | Open Shepit and a relaunch show the section it had last, Settings… shows Settings; the frame and both section choices are remembered ||
| W2 | Open the window, then close it with the red button and with ⌘W; minimize it and click the Dock icon | Dock icon, ⌘Tab and the Shepit / Edit / Window menu bar only while the window is open; the menu bar answers clicks right away; a minimized window comes back; dictation works after closing || 2026-11-13 in part: the Dock icon shows while the window is open (the generic icon: Shepit has none yet); the menu bar, ⌘W and a minimized window not reported
| W3 | With the window in front, dictate; then dictate with the cursor in a text field of the window | The text is pasted where the cursor is, or is on the clipboard with a notice; write down what happens || ✅ 2026-11-13: with the window in front the text is pasted where the cursor is, in the window's field too
| W4 | Watch Home → Status through a dictation and through Reload model | Recording → Transcribing → Ready; Loading… while the model reloads ||
| W5 | Change Mode, Language and Microphone on Home; then edit `mode` in `settings.json` by hand | Settings → Hotkeys / General / Dictation and the file show the change; the hand edit shows on Home within a few seconds ||
| W6 | Change each of the three engines on Home; open a picker while dictating and while a transcript runs | The engine changes for that job; the picker of a running job is off; Mode, Language and Microphone are off while their job runs ||
| W7 | Join a real call with the window open; press Not this call on the panel; press Start transcript on Home; Stop | Home shows the call's name and app; Start uses that name with no dialog; the recording card and the red Stop appear; after Stop the row says finishing, then "No call right now" or the call again || 2026-11-13 in part: Start on a Teams call; the recording card shows the timer and "Teams"; Not this call and Stop not reported
| W8 | Dictate a short and a very long text with Home open; press Copy; press All dictations | Both appear at the top within a few seconds; the long one is cut to two lines; Copy gives the whole text; All dictations opens the placeholder with Open history file ||
| W9 | Settings → Appearance: each theme and a few accent colours, without restarting Shepit; `Shepit panel-test`; open a dialog (Clear history…) | The window, the call panel and the dialog follow the theme and the colour || 2026-11-13 in part: the accent colour changes at once (it needed a restart before commit 8d46025); the theme, the call panel and a dialog not reported
| W10 | Settings → Hotkeys: record a meeting hotkey; press it with no meeting, during one, and right after Stop; try to record the dictation hotkey's keys; Remove | Starts as the menu's Start; stops; "Transcript is finishing"; the clash is refused inline; after Remove the key is gone from `settings.json` and the shortcut does nothing ||
| W11 | With the window open behind another app: Open Shepit from the 🎙 menu, then ⌘O in the open menu | The window comes to the front and takes typing, with no click on the Dock icon ||

2026-11-14: after the review fixes the author clicked through the window on the installed app and found it working; the rows above were not checked one by one.

## Main window: Meetings

Date: 2026-11-16

Design: `docs/superpowers/specs/2026-11-14-meetings-design.md`. M10–M12 above tested menu items that this part replaced.

| # | Scenario | Expected | Result |
|---|---|---|---|
| L1 | A real call: start a transcript, open Meetings while it records, mute and unmute in the call app; Stop | The running meeting is first in the list with a red dot; time, words, phrases waiting and "Your microphone" follow; entries appear and the list follows them unless scrolled up; finishing, detecting speakers, then the meeting with its people stays chosen || ✅ 2026-11-16
| L2 | Name two people; look at the note in Obsidian; in another meeting type «Іван» in a name field | Only the `[name] time` lines of those people changed; text and front matter untouched; while typing, a list opens with the matching names, «Іван» finds «Ivan Batura» || ✅ 2026-11-16
| L3 | Type the name another person has; Cancel, then again and Merge; Merge into; Reset people… | The merge question; Cancel keeps both; Merge and Merge into give all lines to one person; Reset brings every line back and keeps the names || ❌ 2026-11-16: after Cancel the picked name stayed in the field and was saved again on the next focus change (a second question); fixed in the next commit, to check again
| L4 | Click a line, give it to another person; click another, New person | The header of that line only changes; New person makes the next `Person N` ||
| L5 | Rename a meeting; start a transcript at the same time of day later (or next week) | The note's file is renamed in its folder, its `title` changed; the name dialog offers the new name ||
| L6 | Edit an entry's text in Obsidian while the meeting is open; come back to Shepit; name a person | The window shows the edit; the edit is still in the note after the change ||
| L7 | Delete an entry in Obsidian; come back | Lines with that entry's time (to the second) can't be given; the rest can ||
| L8 | Move the note in Finder; come back; Locate note… | "note not found" in the list and the meeting; after Locate the transcript is back ||
| L9 | Add notes… with the old notes and a non-transcript `.md`; Add notes… again | The old meetings appear with the right dates; the message counts the skipped files; the second time all are skipped ||
| L10 | Remove note from list… on one meeting; Move file to Trash… on another | Both ask first; the first note stays in its folder; the second is in the Trash; both leave the list ||
| L11 | Name people on the "Transcript ready" panel; the recording card during a transcript | The window opens on that meeting; the card opens the running one || ✅ 2026-11-16
| L12 | Quit Shepit during a transcript, start it again | The meeting is in the list; the note ends with "Запис перервано" || ✅ 2026-11-16
| L13 | Open the 🎙 menu | No Copy last meeting transcript, Rename speakers or Open meetings folder; Start / Stop meeting transcript is there ||
| L14 | Reveal in Finder and Copy path from a meeting's right-click menu and its ⋯ menu; the same on a meeting whose note is not found | Finder shows the note's folder with the file selected; the path is on the clipboard with 📋 Скопійовано; Reveal in Finder is off for a note not found ||
| L15 | In a finished meeting, click two people (initials, share or an empty spot), then Only highlighted people; click one of them again | Both people's lines are highlighted, each in their colour; the checkbox leaves only their lines; a second click turns one off; the name field still edits on a click ||
| L16 | Click a line → Delete line; in a person's ⋯ → Delete all their lines…, Cancel, then Delete | The line leaves the note at once (Open note); the question says how many lines; after Delete the person leaves People and their lines leave the note; the other lines of the same second can still be given ||

2026-11-16: the author looked through L4–L10 briefly without renaming or removing anything, and will check them in use.

## Main window: Dictations and Dictionary

Date: 2026-11-16

Design: `docs/superpowers/specs/2026-11-16-dictations-dictionary-design.md`.

| # | Scenario | Expected | Result |
|---|---|---|---|
| D1 | Dictate into three apps; open Dictations and Home | The entries are at the top of Dictations with their app and word count; Home shows the app; a dictation made while the section is open appears at the top ||
| D2 | A long dictation: click it, click again; Copy | Two lines with "…"; the click opens the whole text and closes it; Copy takes the whole text with 📋 Скопійовано ||
| D3 | A test home with a few thousand entries (`DICTATION_HOME`, the installed Shepit quit): every period under Show; scroll to the end and back | Each period lists only its entries, Last month by default; the list loads as it scrolls, with no jump; the period is remembered after a relaunch || ✅ 2026-11-16 (scrolling through All history is slower; the author's design remarks are under "Minor ideas" in `docs/future-ideas.md`)
| D4 | Right-click → Delete… on one entry; Cancel, then Delete | It asks first; Cancel keeps it; after Delete the entry is gone from Dictations, Home and Recent ||
| D5 | Clear history…; `historyDays` 1 and a relaunch; `saveHistory` off and a dictation | Clear asks first and empties the list; the relaunch drops entries older than a day; with history off nothing is written and the section says "History is off" ||
| D6 | Terms: + add, × on hover, drag a chip onto another | `dictionary.json` has the term at the end, without the removed one, and in the new order; terms past the limit are dimmed ||
| D7 | Replace: change a rule and press Enter; change one and click away; give a rule the heard phrase another has; − on a rule; add one in the last row | Both changes are saved; the duplicate is refused (the reason in the banner) and the row shows the old rule; the removed rule is gone; the new one is sorted in ||
| D8 | Drop phrases: + add and ×; Add word in the window; ⌃⌥D on a selected word in another app | The file follows; Add word opens the dialog with nothing selected; the section shows the new term and rule at once ||
| D9 | Edit `dictionary.json` by hand with the window open on Dictionary | The section shows the edit within a few seconds ||

## Main window: Statistics

Date: 2026-11-17

Design: `docs/superpowers/specs/2026-11-17-statistics-design.md`.

| # | Scenario | Expected | Result |
|---|---|---|---|
| S1 | Overview on a real history, Last 7 days; hover a bar; dictate in another app with the window open beside it | Dictations, words, meetings and hours, time saved, each with ▲ / ▼ and a percent; the bars add up to the words; the tooltip gives a day's dictation and meeting words; the new dictation is counted at once ||
| S2 | Every period in the menu; Custom… over a few days and over one day; relaunch Shepit | Words per hour for Today and one day, per day up to Last month, per week up to 6 months, per month beyond; the menu reads "12 Nov – 16 Nov 2026" or "16 Nov 2026"; the end can't be before the start or after today; the view and the period are the same after the relaunch ||
| S3 | Dictation view, with an Auto-detect dictation in both languages | The speed table and a line per engine (points only where an engine had 3 dictations); Pasted into, the heatmap, Languages with "Ukrainian + English", Dictionary, Failures with their counts ||
| S4 | A meeting in Teams and one in Google Meet, then Meetings | Both under their app in By app, older meetings under Unknown; tiles, Length and Speaker detection follow ||
| S5 | Call offers: start one from the panel, press Not this call on one, let one hide | Call offers counts each under its outcome and app ||
| S6 | Collect statistics off; dictate once | "Statistics are off" with its button in every view, the old numbers under it; the dictation isn't counted ||
| S7 | Clear statistics…, then open each view | Every view is empty; `stats.sqlite` stays deleted while Statistics is only looked at ||
| S8 | Light and dark; a narrow and a wide window | Tiles, charts, legends and tooltips readable; nothing cut off ||

## Main window: Voices and People

Date: 2026-11-18

Design: `docs/superpowers/specs/2026-11-17-voices-design.md`. On real calls; samples are counted read-only (`sqlite3 -readonly ~/.local/share/dictation/meetings.sqlite "SELECT count(*) FROM samples WHERE meeting = …"`), and only counts are reported.

| # | Scenario | Expected | Result |
|---|---|---|---|
| V1 | Remember voices off; a meeting with two remote people; name them | The meeting keeps no samples; People lists both with "No voice saved" | Not checked on purpose: the author left it for everyday use (2026-11-20) |
| V2 | Remember voices on (People); a meeting with two remote people where you mute and unmute a few times and speak first after some minutes; name both in Meetings | People lists them with the waveform and "Saved from 1 meeting"; You says "Saved from 1 meeting, from your microphone" | ✅ 2026-11-20: the voice lines in People; nobody has 1–2 samples, so none says "too little speech to recognise yet" |
| V3 | A second meeting with one of them | After Stop the person has the name on their own, "recognised by voice" under it in Meetings, the name in the note's headers; the Transcript ready panel says "1 recognised" | 2026-11-20: one person named by voice, and rightly (the Teams transcript gives their lines to the speaker with that name); "recognised by voice" under the name. The panel cut "1 recognised" off after a 48-character name: the name goes last since then; the author sees it in everyday use (2026-11-20) |
| V4 | `voices-check`; give a recognised line to someone else, then Reset people…; `voices-check` again | The line goes to the other person and back; the counts after Reset are the same as before | ✅ 2026-11-20: a recognised line given away and back with Reset people…; voices-check the same before and after (1244 samples; at 0.70: 11 recognised, 0 wrong, 2 missed); the names stayed |
| V5 | People → Merge into: a person into another named in older meetings | It asks first; every meeting of the first goes to the second, the older notes get the kept name; the first leaves People and the second is chosen | ✅ 2026-11-20: a person named by a short name in one meeting, merged into the full name; 15 persons after, no two with one name, none without a meeting |
| V6 | People: rename a person (click the name or ✎, type, Save); then type the name another person has | Every meeting and note of the person follows; the taken name asks Merge, Keep both or Cancel; Keep both lists two people with one name | ✅ 2026-11-20: rename and Keep both, then names back; no test name or doubled name left; the notes have each name as often as the store has the lines (22 person–meeting pairs) |
| V7 | A person with a saved voice who is an unnamed `Person N` in another recent meeting: May also be in → Show…, uncheck one, Name them | The checked meetings get the name, in their notes too; the unchecked one is not suggested again | ✅ 2026-11-20: one meeting suggested (0.93 alike, 0.5 ahead) and named: 43 lines in the store and the note, no old label left. Unchecking one not tried: only one was suggested |
| V8 | Delete voice… on a person; then Delete all voices… | Both ask first; the person shows "No voice saved" and keeps the name in their meetings; after Delete all the `samples` table is empty and You has no voice | Not checked on purpose: the author left it for everyday use (2026-11-20) |
| V9 | A call on speakers, not headphones, with Remember voices on | Your voice heard through the call is not left as a `Person N`: it is merged into you | Passed on 2026-11-20 with nothing to merge: a 60-minute Teams call on headphones, then speakers, then headphones. No call line was more than 0.33 like the author's print (0.7 merges), so their voice didn't come back through the call and no Person N held it; 1 of the 122 microphone lines with a sample was unlike them (below 0.5). The merge into you itself is covered by tests only |
| V10 | People: Who talked how much for Last month and other periods; a person's meetings; a click on one; relaunch Shepit | Meetings, talk time, words and share follow the period, and so does the list of meetings ("No meetings in this period" when empty); older meetings show words and "–" for talk time; the click opens the meeting in Meetings; the period and the person are the same after the relaunch | ✅ 2026-11-20 |

## Main window: Import names

Date: 2026-11-20

Design: `docs/superpowers/specs/2026-11-20-import-names-design.md`. With the `.vtt` files Teams or Zoom saved of real calls; on the author's meetings only counts are reported.

| # | Scenario | Expected | Result |
|---|---|---|---|
| I1 | Meetings → a meeting with its Teams `.vtt` → Import names… → the file → Apply names | The suggested names are who spoke (check a few lines); the note's headers get them | ✅ 2026-11-20: "everything works", the author on the installed app |
| I2 | Import names… with a `.vtt` of another meeting, of the same team too | "This transcript doesn't line up with this meeting." | ✅ 2026-11-21 |
| I3 | Import names… with a `.vtt` that has no names (Zoom's `.cc.vtt`) | "This transcript has no speaker names." | 2026-11-21: "doesn't line up" came, most likely from Zoom's `.transcript.vtt` of the same recording (it has names); both `.cc.vtt` files give "no speaker names" in the parser. Try again with the `.cc` one |
| I4 | A meeting where speaker detection split one voice into two `Person N` | The merge is offered, ticked, and done | |
| I5 | A person named differently from the file | Unticked; tick it, Apply names: the name changes | |
| I6 | A name someone already has from another meeting | People shows one person with both meetings | 2026-11-21, read-only: no name is held by two people in People (16 names); the 29 Oct meeting has no names applied yet, so the check waits for that |
| I7 | A Zoom `.vtt` of a Zoom call | As I1 | Waits for a Zoom call: the store has no Zoom meeting with its file |
| I8 | After an import | The file's path and text are in no database, setting or log | ✅ 2026-11-21, read-only: no `.vtt` name and no `Downloads/` path in the three databases, `meeting-names.json`, `dictionary.json`, `settings.json`, Shepit's preferences, the 60 meeting notes or Shepit's log of the last 2 days |
| I9 | Type a name in the sheet and click Apply names at once | The name is saved | ✅ 2026-11-20 |
| I10 | Hover over Import names… (Shepit's window active) | A hint says what it is for, after a quarter of a second | 2026-11-21: too slow with macOS's delay; Shepit now shows hints after 0.25 s |
