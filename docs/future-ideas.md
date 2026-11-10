# Future ideas

Ideas discussed on 2026-10-06 and set aside for now. Each has a short note on what it is and why it waits.

## Re-paste the last dictation hotkey

A second hotkey (e.g. ⌥⇧Space) that pastes the most recent transcript again — for when the text landed in the wrong place.

*Why not now:* the 🎙 → Recent submenu already lets you copy any recent dictation with one click.

## Voice commands

Spoken commands replaced before pasting: «новий рядок» → line break, «новий абзац» → blank line, maybe «кома»/«крапка» for punctuation.

*Why not now:* whisper already punctuates well; line breaks haven't been needed yet.

## Pause media while recording

Pause music/video when recording starts and resume it afterwards.

*Why not now:* with headphones the music doesn't reach the microphone, and whisper ignores quiet background music. It only matters when music plays loudly through the laptop speakers — then song lyrics can leak into the transcript.

## Per-app profiles

Different behaviour per app, e.g. in Terminal: no trailing period and a lowercase first letter; in Slack: as now.

*Why not now:* unclear if needed; revisit after using the tool for a while.

## Local LLM clean-up

Pass the transcript through a local LLM (e.g. via Ollama) to drop filler words («ну», «еее»), repetitions, and fix grammar — fully offline.

*Why not now:* adds 1–3 s per dictation and several GB of memory; current output is good enough.

---

## From the security & resource audit (2026-10-06)

Fixed already: clean child-process environment, token-protected whisper-server
without CORS, private random temp audio, safe JSON writes, history retention
controls, pinned whisper.cpp commit, shell-free paths, `serverPort` cap.
Left for later:

### Tighter file permissions *(declined for now)*
Config and history are `0644` and their folders `0755`. The home folder is
already closed to other users (`drwxr-x---`), so this is defence in depth:
`umask 077` in the installer and `chmod 600/700` on existing files.

### Lazy-load / unload the models *(declined: keep both in memory)*
Both servers stay loaded (~5.3 GB idle). Options if memory ever matters: start the
preview server on first recording, unload it after idle, or default `livePreview`
to off (~1.8 GB saved).

### Cheaper live preview
Every 2 s the last 20 s are re-transcribed. Could adapt the interval to speech
activity, shrink the window, or only send the new audio.

### Cancellable preview requests and recorder stop timeout
Kill an in-flight preview curl when recording stops; give each request its own
snapshot file; force-terminate sox if it doesn't exit within a few seconds of
SIGINT.

### Integration tests
Hammerspoon lifecycle, both servers, auth/CORS, temp-file symlink, recorder hang,
I/O failures, and a long soak run — currently covered by unit tests and manual
checks only.

### Smaller items
- `killStale` could check that the process it kills was started by this tool
  (e.g. by its parent), not just by path and port.
- Recorder: check the `sox` binary itself exists when a named microphone is used.
- Recent menu reads the last 64 KB of history; a single huge transcript can push
  older ones out of the menu.
- Pre-commit guard against force-adding `tools/accuracy/recordings/`.

## Full UI redesign (planned)

2026-10-27: the user reviewed the phase 3 screens (Settings → Meetings, Rename speakers prompts, Statistics). They work, but the interface is not good enough, and it will be redesigned completely, with its own spec and implementation plans. What it needs:
- A proper app window for meeting transcripts: list, open, read.
- Renaming persons right in the transcript.
- Importing the same meeting's transcript from Zoom, Google Meet or Teams and taking the participants' names from it.
- The rest of the Settings window redone in the same style.

*Why not now:* phase 3 is finished first, with the current UI, and checked on a real call.

## Offer to record when a call starts (planned)

2026-10-29: after phase 3 the user wants Shepit to notice when a call starts in Teams, Zoom or Google Meet, the way Zoom does, and offer to start a meeting transcript already named after that call: one click to accept, nothing recorded without it. It needs its own research and plan:
- How to detect a call reliably: the meeting app using the microphone (Core Audio "device is running somewhere" / per-process input), its call window appearing (Accessibility), or both.
- Getting the meeting name for each app. Done in phase 3 and reusable as is (`MeetingApps.scan`, `MeetingTitle`, `MeetingNames`):
  - Teams: the call window title.
  - Google Meet (Chrome): the tab title `Meet: "name" – …`, or the name after the clock in the page's bottom bar ("17:09 | name"). A quick meeting shows only a code (`abc-defg-hij`), which is not a name.
  - Zoom (`us.zoom.xos`): shows no meeting topic anywhere. The name comes from `meeting-names.json`: the name used last time at this weekday and time (±15 min, last 36 days), or a daily repeat; otherwise the recent names list.
  - The mute state is already read from each app (Teams and Zoom buttons, Zoom's Meeting menu, Meet's microphone button), so "is a call running" can use the same Accessibility scan.
- Not nagging: no offer while a meeting is already being recorded, after a dismiss for the same call, or for apps the user turned off.
- Everything stays local: no network, no calendar sign-in.

This replaces "auto-start when a call begins" in the list below: it offers, it never starts on its own.

## Meeting transcripts: set aside in v1

From the meeting transcription design (`docs/superpowers/specs/2026-10-17-meeting-transcription-design.md` §3), 2026-10-26.

- **Real names from Teams/Meet** (UI scraping, Graph API) or automatic matching with an exported Teams transcript. *Why not now:* fragile or needs company sign-in; Rename speakers… covers it by hand.
- **Meeting names from calendars** (Outlook, macOS Calendar). *Why not now:* window titles, the Meet page, remembered names and the name dialog are enough so far. Option for later (2026-11-06): read macOS Calendar (EventKit) after the user adds their Google or Microsoft account in System Settings → Internet Accounts. Local only, no sign-in inside Shepit; the event that runs now gives the name.
- **Speaker labels live during the call.** *Why not now:* diarization needs the whole call to be accurate; labels come right after Stop.
- **On-screen live captions, auto-start when a call begins, meeting summaries.** *Why not now:* not needed for the notes; summaries would need a local LLM.
- **Only the meeting app's audio** instead of all system audio. *Why not now:* the app has to be picked per call; headphones and muting other sound work for now.
- **Echo cancellation**, so speakers (not headphones) give clean attribution. *Why not now:* headphones solve it, and since Task 11 mic phrases that repeat the call within 5 s are dropped by their words (Test4: 17 of 19 repeats).
- **Finishing an interrupted session** after a quit or crash. *Why not now:* audio is deleted on purpose; the note keeps what was written.
