# Future ideas

What comes next, and what was set aside and why. Reviewed with the author on 2026-11-11.

## Planned, in this order

Build order agreed on 2026-11-11:

1. **Visual style with mockups**: done, `docs/superpowers/specs/2026-11-11-visual-style/`.
2. **Offer to record when a call starts**: built on branch `call-offer`; manual checks C1–C10 and the three end-of-branch reviews are done (2026-11-13). Merged into `main` on 2026-11-13. Left: the list under "Call offer: left open" below.
3. **Window shell** with Home and Settings: built on branch `window-shell`; the three end-of-branch reviews are done and their findings fixed. Merged into `main` on 2026-11-14. Left: the list under "Window shell: left open" below.
4. **Meetings**: the database, names, merging people, giving a line to another person. Built on branch `meetings`; the three end-of-branch reviews are done and their findings fixed. Merged into `main` on 2026-11-16. Left: the list under "Meetings: left open" below.
5. **Dictations and Dictionary**: `dictations.sqlite` with the app of each dictation instead of `history.log`, the Dictations section with a period menu, the Dictionary section as in mockup 5, one `databasesFolder` setting. Built on branch `dictations-dictionary`; the three end-of-branch reviews are done and the author's picks fixed. Merged into `main` on 2026-11-17. Left: the list under "Dictations and Dictionary: left open" below.
6. **Statistics**, with the new numbers.
7. **Voices**: voice prints and the People section.
8. **Import names** from a transcript; the Meet `.txt` format last.

Each gets its own spec and plan.

### Call offer: left open (2026-11-13)

Found by the reviews of the branch and not changed; none blocks the merge except the first, which needs a check on a call.

- **Mute in Zoom and Meet (check before relying on it).** A call's end is the app releasing the microphone for 3 s. If Zoom or Meet releases it while the author is muted, the transcript stops mid-call. Teams keeps it (a 32-minute call, 2026-11-13). Check: start a transcript, mute for 30 s, see whether "Call ended" appears. Teams checked this way by the author on 2026-11-13 (a 63-second call, no stop while muted, the note has no pre-join name); Zoom and Meet are still to check.
- Arc, Edge and Brave: their helper bundle IDs were never probed (`Shepit call-watch` during a Meet call shows them); the match is a case-sensitive prefix.
- A browser holding the microphone with no Meet tab is looked at every 10 s for as long as it holds it.
- The Teams pre-join title is ignored in English only ("Meeting join").
- Removing an empty call transcript leaves a folder that was created for it (`meetingFileName` with folders).
- "Transcript ready" and "Call ended" panels also show with `callOffer` off.
- Whether the panel's buttons take a click while a dialog is open was not tried (its countdown runs).
- Speech in the first seconds after Start on a pre-join screen: one test note had only the line said after Cancel; not looked into.
- Structure: the call app is now a `CallApp` from window detection to the session (Meetings part, 2026-11-15); `Settings.callApps` keeps strings, there are still two browser lists, and the menu's Start and the panel each have their own name lookup.

### Window shell: left open (2026-11-14)

Not blockers; the reviews of the branch found them and they were left as they are.

- Manual checks W1–W10 were not done one by one; the author clicked through the window on the installed app (2026-11-14) and it worked. Not seen on screen: the shortcut recorder ending when the window closes, ⌘Q with no window, Home's Start after "Not this call" and with call offers off, the banner's Open dictionary file.
- `Shepit panel-test` does not read `settings.json`, so its panel always follows the macOS theme (W9 can't show the theme there).
- `examples/settings.json` has `theme` and `accentColor` but not `meetingHotkey` (the spec asked for all three).
- The test that every settings key is in exactly one Settings section only checks "at most one".
- Structure, for the next parts: the `engines` object is written in two places (`AppHost.perform(.setEngine)` and `SettingsModel.setEngine`); the job titles and hints are in `HomeModel` and `EnginesSection`, and differ; engine names are in three switches; the warnings list is in both `HomeModel` and `MenuModel`; `AppHost.Lookups` repeats six `AppSnapshot` fields; `Placeholder` has a separate optional button title and action; Settings → Dictation lists microphones from its own CoreAudio query in `body`, not from the lookups.
- Home greys out Mode, Language, Microphone and the engine pickers while their job runs, but the same keys stay editable in Settings.
- A minimized window shows its old Home for up to 2 s after it comes back.

### Meetings: left open (2026-11-16)

Found by the reviews of the branch and by the author's checks, and left as they are.

- Manual checks: L1, L2, L11 and L12 pass (2026-11-16). L3 found the Cancel bug, fixed in commit 8211d5d, to look at again. L4–L10 the author will check in use. Not seen on screen: the name list opening while typing, Escape on it, the warning when a finished transcript can't be listed.
- Notes edited by other tools: a `title` written as a multi-line YAML block, YAML escapes other than `\"` and `\\`, and a UTF-8 BOM before the front matter are not read as Shepit writes them.
- A change to people or lines reads and writes the note on the main thread (opening a meeting reads it off the main thread). A note in iCloud Drive that macOS offloaded would hold the window, and dictation hotkeys, while it downloads.
- Locate note… compares paths as written: the same note picked through a symlink or another letter case reaches the store, which refuses it with SQLite's own message.
- Word shares count only entries paired with the store: a second edited in Obsidian drops out of every share.
- `MeetingStore.add` uses `INSERT OR IGNORE`, so any constraint failure would read as "already listed".
- The question alert may answer twice (Cancel from the binding, then the button); harmless today.

### Dictations and Dictionary: left open (2026-11-17)

Found by the reviews of the branch and not changed: the author fixed points 1–4 of the thermo-nuclear review and went on.

- Manual checks: D3 passes (2026-11-16, a test home with 5000 entries); D1, D2 and D4–D9 not checked one by one yet.
- A new dictation, with the window open on Dictations, reloads every loaded entry and rebuilds every line before the text is pasted: with All history scrolled to 5000 entries that delays the paste. Each next page also rebuilds the lines of every loaded entry. Reading only the newer entries, or reloading after the paste, would keep a dictation at one INSERT.
- "Today" and "Yesterday", and a period's start, are fixed when the list is built: a window left open over midnight shows them stale until the next change.
- Dictionary section: a replace row saves on Enter or when its focus leaves; switching section or closing the window with an edit in a field may drop it. Terms are identified by their text, so a hand-edited file with a term twice gives one id to two chips and × removes both. Text dragged in from another app that equals a term moves that term. A chip's × is only transparent until hover, so Full Keyboard Access can reach and press it unseen (the plan's open question for Task 5).
- A drag right after a hand edit of `dictionary.json` no longer loses the edit (fixed with point 2 of the review).
- `history.log` from older versions is no longer read, pruned or deleted by Clear history…: its dictations stay on disk until the user deletes the file (the README says it can be deleted). Clear history… could delete it too.
- Structure, from the thermo-nuclear review (points 5–10, not done): `addToDictionary(readSelection:)` is a boolean mode (the caller could read the selection); `FolderRow` takes the key, the key path and a URL closure for one setting; terms and drop phrases repeat the chip list code; `DateFormatter.english` lives at the end of `MeetingPage.swift` though three files use it; `DictationStore.Entry` splits `AppRef` into two optionals and `appBundleID` is never read; `period`'s didSet empties `entries` to steer `reload()`'s limit. Each window section's model is threaded by hand through `AppHost`, `MainWindow` and `MainView`.

### New ideas (the author, 2026-11-15; not ordered yet)

Done 2026-11-16: Open Shepit brings an open window to the front (W11); Reveal in Finder and Copy path in a meeting's menus (L14). Other dialogs (Add word, the meeting name, Quit during a meeting) still call `NSApp.activate()`, which macOS 26.4 refuses while another app is active; no trouble reported with them so far.

From a team call of 2026-11-13 (colleagues' questions, and how Shepit wrote that call: 283 entries), picked by the author on 2026-11-16:

- **Screen sharing in the note.** When someone shares a screen during a call, take screenshots, or at least mark in the note what was shown and when.
- **Automatic start per app.** "Start automatically" only for Teams, only for Zoom, and so on; today `callAutoStart` is one switch for every app, and `callApps` only picks where the panel appears. Asked for again by the author on 2026-11-16: for each of Teams, Zoom and Google Meet, choose whether a call starts a transcript on its own, offers one, or does nothing.
- **Rules by meeting name** (the author, 2026-11-16). A list of meeting names with what to do for each: offer instead of starting on its own, or do nothing at all. It needs a name when the call starts, so it works for Teams and Meet, not for Zoom, which shows no topic (`meeting-names.json` already remembers names of repeating meetings).
- **Statistics the colleagues asked about:** how many transcripts, how much you talked, who talked how much, the share of time in meetings, by app. Most of it is already in part 6 (Statistics); "who talked how much" by name needs part 7 (Voices).
- **A build colleagues can install.** They asked for a link to try Shepit. Today it is built from source and signed with a local certificate; a downloadable build they can install would need its own signing story.
- **Lines speaker detection could not place.** 23 call entries stayed `[Співрозмовники]` after Stop. Give them to the nearest voice, or show them in the window as an "Unknown" person that is easy to name.
- **Whisper's inventions on near-silence.** 63 entries had one or two words, among them English "Thank you.", "Okay", "Super" in a Ukrainian call and a few "Дякую." under your own name. Widen the filler list, or drop very short entries the model was unsure of.
- **Entries cut mid-sentence.** The end of a phrase lands in the next entry, sometimes under another person. Join short neighbouring entries of one person, or cut phrases at better places.
- **The call panel should slide in finished.** Today the offer, stop and "Transcript ready" panels appear in pieces: the text and the card are drawn apart, and the card flies in from the top left before it lands in the top right. It should slide in from the right edge, already fully drawn. A likely cause: `CallPanel.show` orders the panel front at its old frame (`.zero` the first time) before SwiftUI has drawn the new state, and places it again on the next pass.
- **A new look for the dictation overlay.** After the window's redesign the overlay (recording, transcribing, live draft) looks as if it came from another app. Redesign it in the style of the window and the call panel (`2026-11-11-visual-style/`), and make it better while at it.
- **What each engine is for** (the author, 2026-11-16). Settings → Engines and models lists engines and models without saying why there is more than one: the author's Mac has two whisper.cpp models on disk (`large-v3` and `large-v3-turbo`) and three tasks that can each pick any of them. Say in the window what each engine and model is good at (speed, accuracy, memory, languages), which one is recommended for which task, and when a model on disk is not used by anything and can be deleted.
- **Every setting reviewed** (the author, 2026-11-16). Go through all of Settings with the author: is each setting still valid and still needed, is its text clear, can it be better. Drop what nobody uses, merge what overlaps, and fix the hints. The two items above (auto-start per app, rules by meeting name) and "What each engine is for" fit into this pass. A spec first, as for the window's other parts.
- **Every database query on an index.** Check each query of `meetings.sqlite` and `stats.sqlite` with `EXPLAIN QUERY PLAN`; where one scans a whole table, add the index it needs. Known at the time of writing (2026-11-15): in `meetings.sqlite`, `people` and `lines` are keyed by meeting first and `meetings.path` is unique, but the list sorts `meetings` by `start` with no index, and the name suggestions read all of `people` on purpose; in `stats.sqlite`, `dictations` and `meetings` have an index on `time`, `offers` and `model_events` none.

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

## Minor ideas

Small things to come back to; none blocks the next part.

- **A better look for the Dictations section.** The author has design remarks after trying it on 2026-11-16 (Task 4 of the Dictations and Dictionary plan) and wants the section to look better. To go through with the author; the section works as it is.
