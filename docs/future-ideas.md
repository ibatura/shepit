# Future ideas

What comes next, and what was set aside and why. Reviewed with the author on 2026-11-11.

## Planned, in this order

Build order agreed on 2026-11-11:

1. **Visual style with mockups**: done, `docs/superpowers/specs/2026-11-11-visual-style/`.
2. **Offer to record when a call starts**: built on branch `call-offer` (2026-11-12); manual checks C1–C10 and the end-of-branch reviews are open.
3. **Window shell** with Home and Settings.
4. **Meetings**: the database, names, merging people, giving a line to another person.
5. **Dictations and Dictionary.**
6. **Statistics**, with the new numbers.
7. **Voices**: voice prints and the People section.
8. **Import names** from a transcript; the Meet `.txt` format last.

Each gets its own spec and plan.

### The main window (decided 2026-11-11)

2026-10-27: the author reviewed the phase 3 screens (Settings → Meetings, Rename speakers prompts, Statistics). They work, but everything is a menu item followed by a small dialog. Shepit should be a program you can work in; the menu stays for quick actions only.

- **One window, not several.** The current Settings window grows into the main window: meetings, the call running now, dictation history, dictionary, statistics, settings.
- **The menu keeps quick actions:** copy the last dictation again, start and stop a meeting transcript, engine, mode and language. Add word, edit dictionary, reload settings and reload model also live in the window, where many things can be changed without reopening the menu each time.
- **The call running now** is shown in the window, with Start and Stop there too.
- **Meetings list:** which transcripts were made and when. Open one to read it.
- **Rename people in the window.** Opening a meeting shows its people (Person 1, Person 2, Person 3); each gets a name field.
- **A local database of meetings** next to the Markdown notes. The note stays the transcript itself (for Obsidian or Notion). The database keeps a link to the file, the name, the app (Zoom, Teams, Meet), the start time and the duration.
- **No search across transcripts.** Obsidian does that.
- **Voice prints, optional.** A setting to keep voice prints of named people so they are recognised in later meetings. The author can see the saved people and delete any of them, or all.
- **Import the same meeting's transcript** to take the participants' names from it. Files the author has: Teams `.vtt` and `.docx`, Zoom `.vtt`, Google Meet `.txt` written by a browser plugin.

Decided later the same day:
- A single line can be given to another person, and two people can be merged into one.
- The transcript is read only in the window; editing happens in Obsidian.
- Import takes names only. The Meet `.txt` format is done last, from a sample the author sends.
- Voice prints are off by default.
- A meeting whose note was moved or renamed stays in the list, marked "note not found", with a way to point at the file.
- The look is restrained, like macOS System Settings, plus an Appearance section in Settings with a colour choice.

The screens are in `docs/superpowers/specs/2026-11-11-visual-style/`.

### Offer to record when a call starts (decided 2026-11-11)

2026-10-29: Shepit should notice a call in a meeting app, the way Zoom does, and offer a transcript already named after that call.

- **A floating panel**, not a macOS notification.
- **A call is detected by the microphone only** (decided 2026-11-12): a meeting app holding the microphone is a call, as other note takers do it. So the panel may already appear on the pre-join screen (Teams turns the microphone on there).
- **With a name found:** the panel shows the name and a Start button; one click starts, with no name dialog. **Without a name** (Zoom): the panel says "Zoom call" and has the same Start button.
- **Automatic start is a setting.** When on, the same panel shows a countdown bar and the transcript starts unless the author presses the stop button. When off, nothing is recorded without a click. This changes the earlier rule "it never starts on its own": it now starts on its own only when the author turned the setting on.
- **End of the call:** a panel says the transcript stops in a few seconds, with a countdown bar and a "Continue" button.
- **The offer hides after a number of seconds** set in Settings (default 15; 0 keeps it until a button is pressed).
- **Dismiss** applies to this call only.
- **Apps:** Teams, Zoom, Google Meet, Teams in a browser, Slack. FaceTime and Telegram if possible.
- **Calendar names** (EventKit) are not part of this; see below.

Design: `docs/superpowers/specs/2026-11-12-call-offer-design.md`. Plan: `docs/superpowers/plans/2026-11-12-call-offer.md`.

Built 2026-11-12 for Teams, Zoom and Meet in Chromium browsers. The microphone is watched by a once-a-second check: Core Audio's listeners reported nothing on a real call. Checked on real calls: the watch in all three apps, and the whole path (offer, stop countdown, empty transcript removed) in Zoom.

Still to probe with `Shepit call-watch` (it prints every app that takes or releases the microphone): Zoom and Meet joined by a link (pre-join screen), Slack, Teams in a browser, FaceTime, Telegram, Meet in Safari and Firefox. A browser's microphone belongs to one helper process for all its pages, so any page using it while a Meet tab is open counts as the call.

Already there from phase 3 (`MeetingApps.scan`, `MeetingTitle`, `MeetingNames`):
- Teams: the call window title.
- Google Meet (Chrome): the tab title `Meet: "name" – …`, or the name after the clock in the page's bottom bar ("17:09 | name"). A quick meeting shows only a code (`abc-defg-hij`), which is not a name.
- Zoom (`us.zoom.xos`): shows no meeting topic anywhere. The name comes from `meeting-names.json`: the name used last time at this weekday and time (±15 min, last 36 days), or a daily repeat; otherwise the recent names list.
- The mute state is read from each app (Teams and Zoom buttons, Zoom's Meeting menu, Meet's microphone button), so "is a call running" can use the same scan.

Everything stays local: no network, no calendar sign-in.

## Set aside

### Dictation

- **Re-paste the last dictation hotkey** (e.g. ⌥⇧Space), for when the text landed in the wrong place. *Why not now:* the Recent submenu copies any recent dictation with one click.
- **Voice commands:** «новий рядок» → line break, «новий абзац» → blank line, maybe «кома»/«крапка». *Why not now:* whisper punctuates well; line breaks haven't been needed.
- **Pause media while recording.** *Why not now:* with headphones the music doesn't reach the microphone. It only matters with loud music through the laptop speakers.
- **Per-app profiles**, e.g. in Terminal no trailing period and a lowercase first letter. *Why not now:* unclear if needed.
- **Local LLM clean-up** of filler words and grammar. *Why not now:* adds 1–3 s per dictation and several GB of memory; the output is good enough.
- **Cheaper live preview.** Every 2 s the last 20 s are transcribed again. Could follow speech activity, shrink the window, or send only the new audio.

### Meetings

From the meeting transcription design (`docs/superpowers/specs/2026-10-17-meeting-transcription-design.md` §3), 2026-10-26.

- **Real names read from the Teams or Meet window, or through the Graph API.** *Why not now:* fragile or needs company sign-in. Names from an imported transcript are planned above.
- **Meeting names from calendars.** *Why not now:* window titles, the Meet page, remembered names and the name dialog are enough so far. Option (2026-11-06): read macOS Calendar (EventKit) after the author adds their Google or Microsoft account in System Settings → Internet Accounts. Local only, no sign-in inside Shepit; the event that runs now gives the name. It would give Zoom calls a name the first time. To be discussed again after the offer panel works.
- **Speaker labels live during the call.** *Why not now:* diarization needs the whole call to be accurate; labels come right after Stop.
- **On-screen live captions, meeting summaries.** *Why not now:* not needed for the notes; summaries would need a local LLM.
- **Only the meeting app's audio** instead of all system audio. *Why not now:* the app has to be picked per call; headphones and muting other sound work for now. Worth another look once Shepit knows which app the call is in.
- **Echo cancellation**, so speakers (not headphones) give clean attribution. *Why not now:* headphones solve it, and mic phrases that repeat the call within 5 s are dropped by their words (Test4: 17 of 19 repeats).
- **Finishing an interrupted session** after a quit or crash. *Why not now:* audio is deleted on purpose; the note keeps what was written.

### Security and housekeeping

From the audit of 2026-10-06. The items about the old Lua tool (whisper-server, sox, curl, `killStale`, `serverPort`) went away with the native app.

- **Tighter file permissions** *(declined for now)*. Config and history are `0644` and their folders `0755`. The home folder is already closed to other users, so this is defence in depth.
- **Recent menu reads the last 64 KB of history** (`History.tailBytes`); one huge transcript can push older ones out of the menu.
- **Pre-commit guard** against force-adding `tools/accuracy/recordings/`.
- **Integration tests** for the running app (capture, engines, a long soak run): covered by unit tests and manual checks only.
