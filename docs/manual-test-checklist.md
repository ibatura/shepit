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

