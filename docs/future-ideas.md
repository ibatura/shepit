# Future ideas

What comes next, and what was set aside and why. Reviewed with the author on 2026-11-11.

## Planned, in this order

Build order agreed on 2026-11-11; items 8–13 ordered with the author on 2026-11-20, item 9 put first on 2026-11-21:

1. **Visual style with mockups**: done, `docs/superpowers/specs/2026-11-11-visual-style/`.
2. **Offer to record when a call starts**: built on branch `call-offer`; manual checks C1–C10 and the three end-of-branch reviews are done (2026-11-13). Merged into `main` on 2026-11-13. Left: the list under "Call offer: left open" below.
3. **Window shell** with Home and Settings: built on branch `window-shell`; the three end-of-branch reviews are done and their findings fixed. Merged into `main` on 2026-11-14. Left: the list under "Window shell: left open" below.
4. **Meetings**: the database, names, merging people, giving a line to another person. Built on branch `meetings`; the three end-of-branch reviews are done and their findings fixed. Merged into `main` on 2026-11-16. Left: the list under "Meetings: left open" below.
5. **Dictations and Dictionary**: `dictations.sqlite` with the app of each dictation instead of `history.log`, the Dictations section with a period menu, the Dictionary section as in mockup 5, one `databasesFolder` setting. Built on branch `dictations-dictionary`; the three end-of-branch reviews are done and the author's picks fixed. Merged into `main` on 2026-11-17. Left: the list under "Dictations and Dictionary: left open" below.
6. **Statistics** with the new numbers: the period menu shared with Dictations plus Custom…, the Overview, Dictation and Meetings views, the meeting's call app in `stats.sqlite`. Built on branch `statistics`; the three end-of-branch reviews are done and their findings fixed. Merged into `main` on 2026-11-17. Left: the list under "Statistics: left open" below.
7. **Voices**: voice samples in `meetings.sqlite`, prints that follow the author's corrections, recognition when a transcript is ready, and the People section (rename and merge across meetings, Delete voice, May also be in, who talked how much, your voice from the microphone). Built on branch `voices`; the three end-of-branch reviews are done and the author's picks fixed (2026-11-19). Merged into `main` on 2026-11-20. Left: the list under "Voices: left open" below.
8. **Import names** from a transcript: Teams and Zoom `.vtt` in this part (spec `docs/superpowers/specs/2026-11-20-import-names-design.md`), Teams `.docx` and the Meet `.txt` format later. Built on branch `import-names`; the three end-of-branch reviews are done and the author's picks fixed (2026-11-20). Merged into `main` on 2026-11-21 as release `v0.2.0`. Left: the list under "Import names: left open" below.
9. **Version and About Shepit** (the author, 2026-11-21: next, before everything else below): see "Version and About Shepit" under "New ideas". Done on branch `import-names`, merged on 2026-11-21: version 0.2.0, the build's commit, About Shepit, and a workflow that makes the tag and release when a merge raises the version (it made `v0.2.0`). The check for new versions is set aside (the author, 2026-11-22): see "Security and housekeeping" under "Set aside".
10. **Every setting reviewed** with the author, with automatic start per app, rules by meeting name, what each engine is for and the voice numbers: see "Every setting reviewed" under "New ideas". Built on branch `settings-review` (2026-11-23), version 0.4.0: seven Settings pages, Home as a status page, the 🎙 menu in groups, Auto · Offer · Off per call app with rules by meeting name, every model in Engines and models, one period menu, and the same controls everywhere. Spec `docs/superpowers/specs/2026-11-23-settings-review-design.md`, plan `docs/superpowers/plans/2026-11-23-settings-review.md`. Left: the list under "Settings review: left open" below.
11. **L3 again** with the author (Cancel on the merge question): see "Meetings: left open".
12. **Fix: no call offer for Google Meet in Chrome** (found by the author on 2026-11-17): see the last item under "Call offer: left open". Task 9 of the settings review, on a real Meet call with the author. Done on branch `settings-review` (2026-11-23).
13. **Every database query on an index, every index used** (the author, 2026-11-17): see the item under "New ideas"; `stats.sqlite` is checked.
14. **Back and forward in the window** (the author, 2026-11-20; on 2026-11-22: now, before items 10–13), with a sidebar that collapses to its icons (asked on 2026-11-22 while trying it). Built on branch `back-forward` (2026-11-22), version 0.3.0. Merged into `main` on 2026-11-22 as release `v0.3.0`. The spec is `docs/superpowers/specs/2026-11-22-back-forward-design.md`. Left: the list under "Back and forward: left open" below.

Each gets its own spec and plan.

### Call offer: left open (2026-11-13)

Found by the reviews of the branch and not changed; none blocks the merge except the first, which needs a check on a call.

- **Mute in Zoom and Meet (check before relying on it).** A call's end is the app releasing the microphone for 3 s. If Zoom or Meet releases it while the author is muted, the transcript stops mid-call. Teams keeps it (a 32-minute call, 2026-11-13). Check: start a transcript, mute for 30 s, see whether "Call ended" appears. Teams checked this way by the author on 2026-11-13 (a 63-second call, no stop while muted, the note has no pre-join name), Zoom on 2026-11-23 (a 73-second call, muted and unmuted, no stop). The author's second call that night was a Teams meeting (68 s, no stop either), and the store, the note and `stats.sqlite` all say Teams. Meet on 2026-11-23 in Chrome (Task 9 of the settings review): Chrome kept the microphone from the offer until the author left, muted or not.
- Arc, Edge and Brave: their helper bundle IDs were never probed (`Shepit call-watch` during a Meet call shows them); the match is a case-sensitive prefix.
- A browser holding the microphone with no Meet tab is looked at every 10 s for as long as it holds it.
- The Teams pre-join title is ignored in English only ("Meeting join").
- Removing an empty call transcript leaves a folder that was created for it (`meetingFileName` with folders).
- "Transcript ready" and "Call ended" panels also show with `callOffer` off.
- Whether the panel's buttons take a click while a dialog is open was not tried (its countdown runs).
- Speech in the first seconds after Start on a pre-join screen: one test note had only the line said after Cancel; not looked into.
- Structure: the call app is now a `CallApp` from window detection to the session (Meetings part, 2026-11-15); `Settings.callApps` keeps strings, there are still two browser lists, and the menu's Start and the panel each have their own name lookup.
- ~~**No offer for Google Meet in Chrome (to fix).**~~ Done on branch `settings-review` (2026-11-23): On 2026-11-23, on a Meet call in Chrome with the author: Chrome's helper (`com.google.Chrome.helper`) took the microphone, the offer came with the call's name and Start worked; Chrome kept the microphone while the author was muted. Two things were found and fixed (7577aac): the first panel was drawn in pieces, the card growing from the top left (the countdown bar's animation took in the card's first layout, drawn after the panel was on screen), which may be why the offers went unseen; and Chrome now puts its tab strip at depth 7, below the depth-6 limit of the look for tab titles, so a Meet tab behind another tab was not found. The author, 2026-11-17: during a Meet call in Google Chrome the panel with Start never appears, so nothing starts. C1 passed in Chrome on 2026-11-12, so something changed since (Chrome, its helper's bundle ID, the tab title, or Shepit). Start with `Shepit call-watch` during a Meet call in Chrome: does it see Chrome holding the microphone, and which name does it find?
- **No name for a Zoom call (put off).** The author, 2026-11-23: a Zoom call got no name, while Teams and Meet find theirs. Zoom shows no topic in its windows or menus (probed in November), so Shepit names a Zoom call only when it repeats at a time it was named before, and the panel says "Zoom call". `meeting-names.json` has no Zoom entry yet, so no Zoom call gets a name today. Put off by the author on 2026-11-23: Zoom isn't in use now. Ways to fix it: the event running now in macOS Calendar ("Meeting names from calendars" under "Set aside"), or a new probe with `Shepit call-watch` during a Zoom call, in case a newer Zoom shows the topic.

### Window shell: left open (2026-11-14)

Not blockers; the reviews of the branch found them and they were left as they are.

- Manual checks W1–W10 were not done one by one; the author clicked through the window on the installed app (2026-11-14) and it worked. Not seen on screen: the shortcut recorder ending when the window closes, ⌘Q with no window, Home's Start after "Not this call" and with call offers off, the banner's Open dictionary file.
- `Shepit panel-test` does not read `settings.json`, so its panel always follows the macOS theme (W9 can't show the theme there).
- ~~`examples/settings.json` has `theme` and `accentColor` but not `meetingHotkey`~~: done in the settings review (2026-11-23).
- ~~The test that every settings key is in exactly one Settings section only checks "at most one"~~: done in the settings review (2026-11-23).
- Structure, for the next parts (the first two done in the settings review, 2026-11-23: Home has no engine pickers, so only `SettingsModel.setEngine` writes `engines`, and the job titles are `EngineTask.title`): ~~the `engines` object is written in two places~~; ~~the job titles and hints are in `HomeModel` and `EnginesSection`, and differ~~; engine names are in three switches; the warnings list is in both `HomeModel` and `MenuModel`; `AppHost.Lookups` repeats six `AppSnapshot` fields; `Placeholder` has a separate optional button title and action; Settings → Dictation lists microphones from its own CoreAudio query in `body`, not from the lookups.
- ~~Home greys out Mode, Language, Microphone and the engine pickers while their job runs, but the same keys stay editable in Settings~~: Home has no settings since the settings review (2026-11-23).
- A minimized window shows its old Home for up to 2 s after it comes back.

### Meetings: left open (2026-11-16)

Found by the reviews of the branch and by the author's checks, and left as they are.

- Manual checks: L1, L2, L11 and L12 pass (2026-11-16). L3 found the Cancel bug, fixed in commit 8211d5d, to look at again. L4–L10 the author will check in use. Not seen on screen: the name list opening while typing, Escape on it, the warning when a finished transcript can't be listed.
- Notes edited by other tools: a `title` written as a multi-line YAML block, YAML escapes other than `\"` and `\\`, and a UTF-8 BOM before the front matter are not read as Shepit writes them.
- A change to people or lines reads and writes the note on the main thread (opening a meeting reads it off the main thread). A note in iCloud Drive that macOS offloaded would hold the window, and dictation hotkeys, while it downloads. (People's changes read their notes off the main thread first since the Voices part, and Meetings' since the review of 2026-11-19; Rename, Add notes… and Locate note… still don't.)
- Locate note… compares paths as written: the same note picked through a symlink or another letter case reaches the store, which refuses it with SQLite's own message.
- Word shares count only entries paired with the store: a second edited in Obsidian drops out of every share.
- `MeetingStore.add` uses `INSERT OR IGNORE`, so any constraint failure would read as "already listed".
- The question alert may answer twice (Cancel from the binding, then the button); harmless today.

### Dictations and Dictionary: left open (2026-11-17)

Found by the reviews of the branch and not changed: the author fixed points 1–4 of the thermo-nuclear review and went on.

- Manual checks: D3 passes (2026-11-16, a test home with 5000 entries); D1, D2 and D4–D9 not checked one by one yet.
- A new dictation, with the window open on Dictations, reloads every loaded entry and rebuilds every line before the text is pasted: with All history scrolled to 5000 entries that delays the paste. Each next page also rebuilds the lines of every loaded entry. Reading only the newer entries, or reloading after the paste, would keep a dictation at one INSERT.
- "Today" and "Yesterday", and a period's start, were fixed when the list was built: a window left open over midnight showed them stale until the next change. (Fixed in the Statistics part, 2026-11-17: past midnight the open section reads its period again.)
- Dictionary section: a replace row saves on Enter or when its focus leaves; switching section or closing the window with an edit in a field may drop it. Terms are identified by their text, so a hand-edited file with a term twice gives one id to two chips and × removes both. Text dragged in from another app that equals a term moves that term. A chip's × is only transparent until hover, so Full Keyboard Access can reach and press it unseen (the plan's open question for Task 5).
- A drag right after a hand edit of `dictionary.json` no longer loses the edit (fixed with point 2 of the review).
- `history.log` from older versions is no longer read, pruned or deleted by Clear history…: its dictations stay on disk until the user deletes the file (the README says it can be deleted). Clear history… could delete it too.
- Structure, from the thermo-nuclear review (points 5–10, not done): `addToDictionary(readSelection:)` is a boolean mode (the caller could read the selection); `FolderRow` takes the key, the key path and a URL closure for one setting; terms and drop phrases repeat the chip list code; `DictationStore.Entry` splits `AppRef` into two optionals and `appBundleID` is never read; `period`'s didSet empties `entries` to steer `reload()`'s limit. (Done in the Statistics part, 2026-11-17: `DateFormatter.english` has its own file; the sections' models are one `WindowSections`.)

### Statistics: left open (2026-11-17)

Found by the reviews of the branch and not changed: the author had all eight points of the thermo-nuclear review and all five of `/code-review` fixed; `/security-review` found nothing.

- Manual checks: the author looked at the views on the installed app while they were built; S1–S8 not checked one by one yet.
- The previous period's call offers are read with the rest but not used: the Call offers table has no change against the previous period (`/code-review` of Task 4).
- Words per saved person (style spec §5.6) needs voice prints: part 7 (Voices). Decided in the voices spec (§3): Statistics → Meetings stays as it is; who talked how much is in People.
- Statistics → Meetings counts only what `stats.sqlite` recorded: notes added with Add notes… aren't in it, and meetings from before this part have no call app (Unknown in By app).

### Voices: left open (2026-11-19)

Found by the reviews of the branch and not changed: the author had all eight picked points of the thermo-nuclear review and all ten of `/code-review` fixed (one only in the README, one not a bug); `/security-review` found nothing.

- **Checks with real calls.** V2, V4–V7, V9 and V10 passed on 2026-11-20, V3 except the panel's count; V9 had nothing to merge (on speakers the author's voice didn't come back through the Teams call), so the merge of a recognised You is covered by tests only. The author left V1, V8 and the panel's count for everyday use.
- ~~**How much of the microphone.**~~ Settled with the author (2026-11-19): 10 minutes stay. On the call of 15:59 the author spoke 68 s in 25 lines and every line got a sample; their microphone voice was 0.9 alike across two meetings. Before: `micVoiceSeconds` is 600 (10 minutes of your speech) for now: Stop gets slower by the speaker detection of that audio (8.5 s for 5 minutes and 16.3 s for 10 on synthetic speech). Until 2026-11-19 it was the meeting's first 10 minutes: on the call of that day the author first spoke 17 minutes in, and no sample of theirs was kept. Now mic.wav keeps the whole microphone and detection hears only the author's lines. After the author's next real meeting with Remember voices on: count the microphone samples (read-only, numbers only) and settle the minutes with the author.
- ~~**Threshold, margin, mean or nearest.**~~ Settled with the author (2026-11-19), `voices-check` on 918 samples of 12 people, 4 of them in two meetings or more: a known person's voice was 0.78-0.95 like their print, no other print came closer than 0.55, and a voice with no print elsewhere was at most 0.55 like anyone. The threshold is 0.7 (0.8 missed a third of them), the margin 0.1 and 3 samples stay, and the mean stays: the nearest sample did no better than the mean at a lower threshold and needs every sample, so `Voices.Match` is gone. Your voice is now only your lines from the microphone: the 39 call lines given to you on 2026-11-18 were 0.14 alike your microphone and blurred your print (0.63-0.69 like your own meetings). Check again with `voices-check` as meetings add up (the author, from 2026-11-20). Before: recognition used the mean of a print, 0.8 and 0.1, and needs 3 samples. The author's store had 200 samples of 2 people and nobody in two meetings (2026-11-18), too few to settle them. Run `Shepit voices-check` after the meetings of the checks; then remove the losing match mode from `Voices.Match`, which only `voices-check` uses now (thermo-nuclear point 4).
- **Stop runs the two speaker detections one after the other** (call, then microphone). Running them side by side would shorten Stop, at the cost of memory; measure on a real meeting first (thermo-nuclear point 9, not picked).
- **The SQLite journal.** `secure_delete` overwrites deleted samples in `meetings.sqlite` itself, but the rollback journal held copies of the pages until it was deleted, and its blocks stay on disk until reused; so do Time Machine's local snapshots. An app can't overwrite them; FileVault encrypts them. The README says so. The same holds for deleted dictations in `dictations.sqlite`. `journal_mode = MEMORY` would keep the copies off disk at the cost of a damaged file after a crash mid-write.
- **One voice split into two `Person N`.** A print names at most one key per meeting, so when speaker detection splits a voice in two (the author's echo as Person 1 and Person 4), only the closer one is named.
- **Narrow window.** At the narrowest window long names in the People list are cut short, and the sidebar's "Meetings" can break as "Meet-ings".
- **Notes and labels** (from `/code-review` of Task 1): a label that is a name shows the person's spelling, which can differ from the note's header ("[olena]" shown as "ОЛЕНА"); clearing the name field of a person added from a note's label unlinks them, but the row still shows the label, so the field seems to do nothing; `personID` folds every person's name through `name_key` on each lookup (a full scan; fine at today's sizes).
- **Store and structure** (from `/code-review` of Tasks 3 and 5): `MeetingStore.merge` and `rename` don't refuse You as the source (only the view hides the controls); `PeopleModel` uses `MeetingsModel.Notice` for its alerts (a shared notice next to `WindowSections` would serve both); a failed change in Meetings shows the note's path twice (in the title and in the reason); the order of listing, recognition and the empty-note decision in `AppHost`'s `onFinished` has no test; nor has putting notes back when that fails (`NotesNotPutBack`), which a test can't cause without a hook in the middle of `change`.
- **Two people with one name** (Keep both) differ in People and in Merge into only by their meetings line ("6 meetings · last 10 Nov"); typing that name in a meeting goes to the one with the latest meeting. A way to pick between them in the name field is for a later part.

### Import names: left open (2026-11-20)

Found by the reviews of the branch and not changed: the author had all five points of the thermo-nuclear review and all six of `/code-review` fixed (one not a bug); `/security-review` found nothing.

- **Checks with real files.** I1 and I9 passed on 2026-11-20 ("everything works"), I2, I8 and I10 on 2026-11-21; I4 and I5 are open, I6 waits for names on the 29 Oct meeting. I3 (Zoom's `.cc.vtt`) and I7 (a Zoom call with its `.vtt`; the store has none yet) are put off for long (the author, 2026-11-22): "Need to test later" in `docs/manual-test-checklist.md`.
- **Teams `.docx` and the Meet `.txt` format**: later parts; the Meet format from a sample of the author's.
- **The numbers were settled on two meetings** (spec §11): lines up when every shift more than a minute away scores below 90% of the best; a match at 50% and 5 s. A transcript of 5 minutes or less may be refused. Look again if real files disagree.
- **A meeting under a minute** accepts any file: no shift lies a minute away from the best.
- **Whole seconds:** a cue or line counts every second it touches, so a 0.2-s "Yes." across a second boundary counts as 2 s. This is the method checked on the author's files.
- **Another time zone:** a line's time is read from the note in today's time zone, so a meeting recorded in another time zone (travel) shows "the file starts …" off by the difference; the matches are right, since the shift takes it up. A change of summer time is fine: each date gets its own offset.
- **Tests:** the alignment tests build 30-minute meetings and add about 2.5 s to `make test`.
- **The name** stays Import names… with a hint on hover (the author, 2026-11-20: the name alone didn't say where the names come from).

### Back and forward: left open (2026-11-22)

- **Checks with the author:**
  - B1–B4, B10 and B13 passed on 2026-11-22;
  - B3 in a name field wasn't confirmed on its own;
  - B5–B9, B11 and B12 are open.
- **Back to a person reads twice:** their talk and suggestions are read when the person is chosen, and again when People appears (from the review of Task 2; skipped).
- **What the arrows show:**
  - They ask the store whether a step's meeting or person still exists, with single-row reads, when they are drawn.
  - They aren't redrawn when the store changes under them, for example after an edit in Meetings. Until the next change of place, an arrow can name a step that a click then skips.
- **The collapsed column** is the same list as the sidebar, with icons only, beside the section; macOS's own sidebar returns when it is opened.
- **The arrows' place:** they sit next to the sidebar button. With the full sidebar shown, that is right of the sidebar, left of the section's name. The author kept it (B13).
- **Tests:** each `UserDefaults` suite the tests make is emptied but leaves a 42-byte file in `~/Library/Preferences`. The older model tests leave theirs full.

### Settings review: left open (2026-11-23)

- **Checks with real calls:** R6 (Teams: Offer, a rule's Off, a rule's Auto) and R7 (Zoom set to Off) need calls; R8 needs a copy of a 0.3.0 `settings.json` read by a test build. R1–R5 and R9–R11 passed on 2026-11-23.
- **The old call keys** `callOffer`, `callAutoStart` and `callApps` are still read while `callModes` is missing, and validated. They can go in a later version, once no file of the author's has them.
- **Zoom rules** match only a name Shepit remembers for a repeating meeting, since Zoom shows no topic ("No name for a Zoom call" above).
- **Dragging rules** doesn't work in a grouped `Form` (`.onMove` needs a `List`); each rule has ↑ and ↓ instead (the author, 2026-11-23).
- **People's period menu** sits beside Who talked how much, not in a top bar: the period is the chosen person's, and People's bar is Remember voices.
- **Font size and Bars** stay − + steppers: small ranges tuned by eye (the author's pick, 2026-11-23). Every other number is a menu; a value from the file that isn't in the menu is listed too.
- **Text fields outside Settings** (the Dictionary's replace rules, a meeting's people) still save on Enter or when the field is left, not with Save; the author's rule was for Settings. To look at with the author.
- **The Add word dialog** is English now; its hint keeps a Cyrillic example ("джира = Jira"), since the mishearing is Ukrainian.

### New ideas (the author, 2026-11-15; not ordered yet)

- **Version and About Shepit** (the author, 2026-11-21; next to build, the highest priority). Shepit must show which version it is: an About Shepit item, perhaps in the 🎙 menu, with the version. The version is kept on GitHub too, so each installed build can be found there. Checking for a new version with a request to GitHub is in question: it would be the first network call that isn't a model download the user asked for ("Everything stays local" in `CLAUDE.md`), so at most a button that asks GitHub only when clicked; to decide with the author in the spec.
  - Done on branch `import-names` (2026-11-21, the author: 0.2.0): `Info.plist` says 0.2.0, `build-app.sh` writes the commit it builds as `CFBundleVersion`, and About Shepit (🎙 menu and app menu) shows macOS's About panel, "Version 0.2.0 (ff170a9)". Also (the author: "automatically when the pull request is merged"): `.github/workflows/release.yml` runs when a push to `main` changes `Info.plist`, and makes tag `v<version>` and the release "Shepit <version>" with `docs/releases/<version>.md`, or GitHub's generated notes; a version already released is skipped. Its first run, on the merge of `import-names` (2026-11-21), made tag `v0.2.0` on the merge commit and the release with `docs/releases/0.2.0.md`, marked latest. The check for new versions is set aside (the author, 2026-11-22): see "Security and housekeeping" under "Set aside". Before: `Info.plist` said `0.1.0` and never changed, and the repository had no tags.
  - How it could be done (for the spec): the version in one place (`CFBundleShortVersionString`, or a `VERSION` file that `build-app.sh` writes into it), and the commit (`git describe`) as `CFBundleVersion`, so a build tells which commit it is; About as macOS's standard About panel (`orderFrontStandardAboutPanel`: name, version, build), in the 🎙 menu and the app menu; on GitHub a tag such as `v0.2.0` on `main` after each merged part, perhaps a release with notes; a check would read `https://api.github.com/repos/ibatura/shepit/releases/latest` (public, no sign-in) and compare.

Done 2026-11-16: Open Shepit brings an open window to the front (W11); Reveal in Finder and Copy path in a meeting's menus (L14). Other dialogs (Add word, the meeting name, Quit during a meeting) still call `NSApp.activate()`, which macOS 26.4 refuses while another app is active; no trouble reported with them so far.

From a team call of 2026-11-13 (colleagues' questions, and how Shepit wrote that call: 283 entries), picked by the author on 2026-11-16:

- **Screen sharing in the note.** When someone shares a screen during a call, take screenshots, or at least mark in the note what was shown and when.
- **Automatic start per app.** Done on branch `settings-review` (2026-11-23): Auto, Offer or Off per app (`callModes`). "Start automatically" only for Teams, only for Zoom, and so on; today `callAutoStart` is one switch for every app, and `callApps` only picks where the panel appears. Asked for again by the author on 2026-11-16: for each of Teams, Zoom and Google Meet, choose whether a call starts a transcript on its own, offers one, or does nothing.
- **Rules by meeting name** (the author, 2026-11-16). Done on branch `settings-review` (2026-11-23): `callRules`, each an app, contains or is, a text and Auto, Offer or Off. A list of meeting names with what to do for each: offer instead of starting on its own, or do nothing at all. It needs a name when the call starts, so it works for Teams and Meet, not for Zoom, which shows no topic (`meeting-names.json` already remembers names of repeating meetings).
- **Statistics the colleagues asked about:** how many transcripts, how much you talked, who talked how much, the share of time in meetings, by app. Most of it is already in part 6 (Statistics); "who talked how much" by name needs part 7 (Voices).
- **A build colleagues can install.** They asked for a link to try Shepit. Today it is built from source and signed with a local certificate; a downloadable build they can install would need its own signing story. The check for new versions comes back with it (set aside on 2026-11-22).
- **Lines speaker detection could not place.** 23 call entries stayed `[Співрозмовники]` after Stop. Give them to the nearest voice, or show them in the window as an "Unknown" person that is easy to name.
- **Whisper's inventions on near-silence.** 63 entries had one or two words, among them English "Thank you.", "Okay", "Super" in a Ukrainian call and a few "Дякую." under your own name. Widen the filler list, or drop very short entries the model was unsure of.
- **Entries cut mid-sentence.** The end of a phrase lands in the next entry, sometimes under another person. Join short neighbouring entries of one person, or cut phrases at better places.
- **The call panel should slide in finished.** Done on branch `settings-review` (2026-11-23, 7577aac): the panel is laid out before it is shown, slides in whole from beyond the screen's right edge (2026-11-24: the panel opens out leftwards from that edge with the card at its left, so the card never shows on a screen beside it), and only the countdown bar is animated. Before: the offer, stop and "Transcript ready" panels appear in pieces: the text and the card are drawn apart, and the card flies in from the top left before it lands in the top right. It should slide in from the right edge, already fully drawn. A likely cause: `CallPanel.show` orders the panel front at its old frame (`.zero` the first time) before SwiftUI has drawn the new state, and places it again on the next pass.
- **A new look for the dictation overlay.** After the window's redesign the overlay (recording, transcribing, live draft) looks as if it came from another app. Redesign it in the style of the window and the call panel (`2026-11-11-visual-style/`), and make it better while at it.
- **What each engine is for** (the author, 2026-11-16). Done on branch `settings-review` (2026-11-23): Engines and models lists every model by kind with what it is for and what uses it. Settings → Engines and models lists engines and models without saying why there is more than one: the author's Mac has two whisper.cpp models on disk (`large-v3` and `large-v3-turbo`) and three tasks that can each pick any of them. Say in the window what each engine and model is good at (speed, accuracy, memory, languages), which one is recommended for which task, and when a model on disk is not used by anything and can be deleted.
- **Every setting reviewed** (the author, 2026-11-16). Done on branch `settings-review` (2026-11-23); the voice numbers stay in code (spec §2). Go through all of Settings with the author: is each setting still valid and still needed, is its text clear, can it be better. Drop what nobody uses, merge what overlaps, and fix the hints. The two items above (auto-start per app, rules by meeting name) and "What each engine is for" fit into this pass. Also to discuss (the author, 2026-11-19): whether the voice numbers, now only in code, become settings: the threshold 0.7 (`Voices.threshold`), the margin 0.1 (`Voices.margin`), 3 samples (`Voices.enough`), 10 minutes of your speech (`MeetingConfig.micVoiceSeconds`) and 30 days for unnamed voices (`AppHost.forgetOldVoices`). My advice was to keep them in code, settled with `voices-check`, or at most hidden `settings.json` keys with nothing in the window. A spec first, as for the window's other parts.
  - **The author's remarks while looking through Settings (2026-11-22)**, for the spec. What is on each page today is in brackets.
    - *Where things are.* Several pages hold what belongs to another:
      - **Models.** Engines and models picks and downloads the engines for Dictation, Live draft and Meetings. The voice detection and speaker detection models are only in Meetings → Transcript → Models, where they can be downloaded and nothing can be chosen. All models belong in one place.
      - **Language.** The dictation language is the first thing in General ("Language"), not in Dictation; the meeting language is in Meetings. Why is a dictation setting in General?
      - **Overlay.** It isn't clear what it is or what it is for (it is the dictation panel: recording, transcribing, the live draft). It belongs to dictation, so why a page of its own next to Dictation? And its look (position, font size, meter) is apart from Appearance.
      - **Meetings and Calls.** What is a meeting and what is a call, and why are they two pages that don't refer to each other? (Meetings: notes, the file name, blocking dictation, the language, recognition, the models. Calls: the offer, automatic start and stop, the apps.)
      - **History and privacy.** Whose history: dictations' or meetings'? Statistics is on that page too. (History: save history, Recent menu items, failed audio, Clear history…; then Statistics, Voices, Databases.)
      - **Appearance.** It is good, but only the theme and the accent colour: little. Why isn't the overlay's look here? What else could go here?
      - **Hotkeys** is more or less fine.
    - *Calls → Apps.* Teams, Zoom and Google Meet each have an on/off switch, and nothing says what on or off means (today: which apps the offer and automatic start watch). The author wants three choices for each app: start automatically, offer a transcript, or do nothing. This is "Automatic start per app" above. The page also needs a line on what it is for.
    - *Every page* should say in a line what it is for and what its settings change.
    - *The 🎙 menu* (the menu of the menu-bar icon) is unclear: it has Start meeting transcript, Copy last dictation, and then the models and Language. Is that Language for dictation or for meetings? The menu should keep one order: the meeting items together, the dictation items together, then the app's own items (Open Shepit, About Shepit, Settings…, Quit). Open Shepit and Settings… both open the window: is one of them a duplicate? The author asked how best to lay it out. (Today, top to bottom, "|" for a separator: the status line, "Ready — whisper.cpp large-v3-turbo"; while a transcript runs, "⏺ Recording · name · 12:34"; ⚠ lines for settings errors, the hotkey, Accessibility and the microphone | Open Shepit ⌘O | Start or Stop meeting transcript | Copy last dictation, Recent (the last 10 dictations, `historyMenuItems`), Add word… | Mode, Language, Dictation engine | About Shepit, Settings… ⌘,, Quit Shepit ⌘Q. Language is the dictation language (`language`); the meeting language is only in Settings → Meetings. Mode is how the dictation hotkey works: Toggle or Hold to talk. Open Shepit opens the window on the section it had last, Settings… on Settings. `MenuModel.build`.)
      - *Recommendations (not decided):*
        - Groups split by separators, in the author's order, each led by its state as a line that can't be clicked, so the state says which group it belongs to. Meeting: "No call", the call found ("Weekly sync · Teams") or "⏺ Recording · Weekly sync · 12:34", then Start or Stop meeting transcript. Dictation: "Ready — whisper.cpp large-v3-turbo", then Copy last dictation, Recent dictations ▸, Add word to dictionary…. macOS 14 has small grey section headers for menus (`NSMenuItem.sectionHeader`), and Shepit needs 14.2, so each group can be headed "Meeting" and "Dictation" with its state line under it.
        - The ⚠ lines stay first, above both groups: they are what needs doing, and each opens its fix, as today.
        - Each item says what it acts on: "Add word to dictionary…" for Add word…, "Recent dictations" for Recent. Start and Stop meeting transcript and Copy last dictation already do.
        - Mode, Language and Dictation engine leave the menu. They are settings that rarely change, and a menu-bar app's menu is for what is used often; the window has all three (Hotkeys, General, Engines and models). If the author switches the dictation language often, keep only that one, in the dictation group, as "Dictation language ▸", so it can't be taken for the meetings' language.
        - Settings… stays next to Open Shepit, in the last group: Open Shepit ⌘O, Settings… ⌘,, About Shepit, Quit Shepit ⌘Q. It isn't a duplicate: Open Shepit goes back to where the author was (Meetings, say), Settings… goes straight to Settings. And Settings… ⌘, is where every Mac app has it, so it is where people look. If one has to go, it is Settings…, since the sidebar reaches Settings in one more click.
    - *Home* repeats settings that live on other pages. The author keeps the transcript's state (the running meeting), the status, and the last dictations. In question, in the author's words: "Mode": not sure it is needed; Language: why here?; Dictation: it is chosen in Dictation; Microphone: it is in Dictation; Reload model and Reload settings: what for?; the "Download models…" link: it is clear where models are anyway; the model choice: it is in Engines and models. The author thinks most of these don't belong on Home, and asked how Home is best laid out. (Today, four groups. *Dictation*: Status, the status line; a warning row each for a hotkey problem, Accessibility (Allow…) and microphone access (Open System Settings); Mode, Language, Microphone; "Changes apply at once" with Reload settings and Reload model. *Engines: which model does which job*: a picker each for Dictation, Live draft and Meetings, and the Download models… link to Engines and models. *Meeting*: no call, a call found or a transcript running, with Start transcript or a red Stop. *Last dictations*: the last 10 with time, app and Copy, and All dictations. Reload settings reads `settings.json` and `dictionary.json` again after an edit by hand, since nothing watches the files; Reload model unloads the dictation and live draft models and loads them again. Errors in the two files show in a bar above every section, Home included. `HomeModel`, `HomeSection`.)
      - *Recommendations (not decided):* Home is a status page: what Shepit is doing now, what needs attention, and what happened last. Settings live only in Settings; Home links there only from a problem. Top to bottom:
        - *Needs attention*, only when something is wrong, each with one button that fixes it: the hotkey problem, Accessibility (Allow…), microphone access (Open System Settings), and a model that is chosen but not downloaded (Download…, which opens Engines and models). Today's warnings stay; the missing model is new: today it shows only as an error in the status, or in the meeting row's hint.
        - *Dictation*: keep the status line. It already names the engine in use ("Ready — whisper.cpp large-v3-turbo"), so no picker is needed to see it.
        - *Meeting*: keep as it is: no call, a call found with Start transcript, recording with Stop, finishing.
        - *Recent*: keep Last dictations (10, Copy, All dictations). Add the last meeting: its name, app, day and length, a click opening it in Meetings.
        - Drop Mode: it is in Hotkeys, and it is how the hotkey works, set once.
        - Drop Language: it is in General today and goes to Dictation in this review. If it must be quick to switch, the 🎙 menu's "Dictation language" is the place, not Home.
        - Drop the engine pickers (Dictation, Live draft, Meetings) and the Download models… link: Engines and models has them, and a missing model comes up under Needs attention.
        - Drop Microphone: it is in Dictation. At most, the microphone in use as text next to the status, if the author wants to see it.
        - Drop Reload settings and Reload model. Reload settings goes next to Open settings file (General → Files), where an edit by hand starts; or Shepit watches the two files and the button goes. Reload model goes to Engines and models, or goes altogether if nobody needs it: a change of engine there already loads the new one.
    - *My first thoughts, to settle in the spec, not decided.*
      - Dictation gets its language, microphone, style and pasting, and the overlay as its "Panel" part. The overlay's look either stays with it or goes to Appearance.
      - One meetings page with the calls in it: per app start, offer or nothing; automatic stop; notes; language.
      - Engines and models with every model, the voice and speaker detection models included, each saying what it is for.
      - History and privacy names its parts after what they keep: Dictations, Meetings, Statistics, Voices.
- **App icon and name** (the author, 2026-11-22; not ordered yet: maybe a part of its own, or to think over more). Shepit has no proper icon, and that isn't nice. Today `app/Resources/` holds only `Info.plist`, with no `.icns` and no asset catalogue, and `Info.plist` has no `CFBundleIconFile`; so the Dock and ⌘Tab (while the window is open), Finder and the About panel show macOS's generic app icon. The window shell spec left it out on purpose ("The Dock shows the generic icon until the author supplies one"). The menu bar shows no image either: the status item's title is text, 🎙 when ready, 🔴 while recording, ⏳ while transcribing, 🎙⚠ with a problem, and ⏺ in front while a transcript runs (`MenuModel.title`, set as `statusItem.button?.title` in `MenuController`).
  - An icon is to be generated and discussed with the author: the app icon (an `.icns` that `build-app.sh` copies into the bundle, named by `CFBundleIconFile`), and maybe a template image for the menu bar in place of the emoji, which macOS tints for light and dark menu bars.
  - The name: check whether "Shepit" is already used by another app, in the Mac App Store or elsewhere, so that it is at least roughly unique. If it is taken, find a new name. Not checked yet. A new name changes `CFBundleName` and perhaps the bundle id `dev.shepit.Shepit`; a new bundle id means granting Accessibility, Microphone and System Audio Recording again. The data folders (`~/.config/dictation`, `~/.local/share/dictation`) don't carry the name.
- **The same controls look and sit the same everywhere** (the author, 2026-11-22). Done on branch `settings-review` (2026-11-23): one period menu, number settings as menus, text settings with Save, Clear… as sheets; see "Settings review: left open". The window should feel like one app: where a section has the same kind of control as another, it looks the same and is in the same place. The period menu, which the author noticed first, is different in each of three sections:
  - Dictations: a menu labelled "Show", on the left of the top bar;
  - Statistics: a menu with no label, on the right, after the view's tabs, with Custom…;
  - People: a picker labelled "Period", on the right, in the person's part.

  Go through every section for such differences (top bars, period menus, buttons at the bottom, empty states, questions and alerts) and make them one way. It fits the settings review's pass, but it covers the whole window.
- **Voice prints that learn** (the author, 2026-11-17; for part 7, Voices). In the People section, merge two saved voices into one (the same person saved twice, or under two names). And make each print better over time: every time the author names a person, merges people or gives a line to someone else in a meeting, the voice of those lines goes into that person's print, so the next meetings recognise them more often.
  - *Possible, from what Shepit already has* (looked at 2026-11-17): speaker detection is FluidAudio 0.17.7's offline diarizer (pyannote + WeSpeaker), and each segment it returns carries a 256-number voice embedding (`TimedSpeakerSegment.embedding`) that `MeetingModels.Diarizer` drops today. FluidAudio also has a `SpeakerManager` with known speakers, matching by cosine distance, `updateMainEmbedding` (a running print), raw samples per speaker and `mergeSpeaker`. A print is a list of such embeddings, not audio.
  - *What it needs:* keep the embeddings of each line when the meeting stops (the call audio is deleted then, `MeetingSession.cleanUpAudio`), in `meetings.sqlite` next to the lines, so a correction made days later can still feed the print. A print keeps its samples with the meeting they came from: a wrong name given by mistake, or a line given back, takes its samples out again, and deleting a meeting or a person deletes them. Skip short or low-quality segments (`qualityScore`). The author's own microphone could give the author's print without any naming, which would also find the author's voice heard through the call.
  - *To find out in the spec:* the distance at which a saved voice counts as recognised; whether a running mean or the nearest of several samples matches better across apps and microphones (Teams, Meet and Zoom compress audio differently); how many samples a print needs before it is offered; and a check on real meetings of how often the right person is found before and after a few corrections.
  - Voice prints are biometric data: off by default (decided 2026-11-11), only on this Mac, never in `stats.sqlite`, each person and all of them deletable.
- **Back and forward in the window** (the author, 2026-11-20, while checking Voices). Arrows at the top of the window, as in a browser or Finder: a click on a meeting in People opens it in Meetings, and there is no way back to that person. It should work across the whole window: every section, and the meeting or person chosen in it, is a step. To settle in a spec: what counts as a step (a section, a meeting, a person, a period?), the keys (⌘[ and ⌘], the mouse's back and forward buttons, a two-finger swipe), and what a step to a deleted meeting or person does. Decided with the author on 2026-11-22 and written in `docs/superpowers/specs/2026-11-22-back-forward-design.md`: a section and what is chosen in it is a step, each choice a step; ‹ › at the top, ⌘[ and ⌘], a hint on hover; gone steps skipped; the history lasts while Shepit runs, 50 steps. Built on branch `back-forward` (2026-11-22).
- **A sidebar that collapses to its icons** (the author, 2026-11-22, after trying back and forward). Today the sidebar button hides the whole sidebar. The author wants it to collapse to a narrow column of the sections' icons instead (Home, Meetings, Dictations, Dictionary, People, Statistics, Settings), as the Claude desktop app's sidebar does, with each section's name as a hint on hover. And the back and forward arrows could sit in the bar above the sidebar, next to its button, as in that app; to compare with where they are now (left of the section's name). SwiftUI's `NavigationSplitView` only hides its sidebar, so a collapsed one needs a sidebar of Shepit's own width and labels. Built on branch `back-forward` (2026-11-22): macOS's own sidebar when full; when collapsed, it is hidden and a column of Shepit's own icons takes its place, with the arrows next to the sidebar button in the window's bar (spec §10).
- **Every database query on an index, every index used** (the author, 2026-11-15; widened 2026-11-17). Check each query of `meetings.sqlite`, `dictations.sqlite` and `stats.sqlite` with `EXPLAIN QUERY PLAN`; where one scans a whole table or sorts in a temporary B-tree, add the index it needs. Then go through every index each database has and drop the ones no query uses (they only slow writes). Known at the time of writing (2026-11-15): in `meetings.sqlite`, `people` and `lines` are keyed by meeting first and `meetings.path` is unique, but the list sorts `meetings` by `start` with no index, and the name suggestions read all of `people` on purpose. `stats.sqlite` checked on 2026-11-17 (Statistics part, on the author's file at version 2): the reads of `dictations`, `meetings` and `offers` for a period each search their `time` index, which also gives the order; `offers` got its index in that part; `model_events` has none and is only written. Left: `meetings.sqlite`, `dictations.sqlite`, and whether each index is used.

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
- **Meeting names from calendars.** *Why not now:* window titles, the Meet page, remembered names and the name dialog are enough so far. Option (2026-11-06): read macOS Calendar (EventKit) after the author adds their Google or Microsoft account in System Settings → Internet Accounts. Local only, no sign-in inside Shepit; the event that runs now gives the name. It would give Zoom calls a name the first time. To be discussed again after the offer panel works. On 2026-11-23 the author saw a Zoom call with no name and put the fix off (see "Call offer: left open"); this would be the fix.
- **Speaker labels live during the call.** *Why not now:* diarization needs the whole call to be accurate; labels come right after Stop.
- **On-screen live captions, meeting summaries.** *Why not now:* not needed for the notes; summaries would need a local LLM.
- **Only the meeting app's audio** instead of all system audio. *Why not now:* the app has to be picked per call; headphones and muting other sound work for now. Worth another look once Shepit knows which app the call is in.
- **Echo cancellation**, so speakers (not headphones) give clean attribution. *Why not now:* headphones solve it, and mic phrases that repeat the call within 5 s are dropped by their words (Test4: 17 of 19 repeats).
- **Names from a screenshot of Teams' speaker timeline** (the author, 2026-11-20). *Why not:* Shepit has no vision model, only speech models; it would need Apple's Vision text recognition for the names plus its own reading of the coloured bars by pixel, which breaks with any change of Teams' layout, zoom, theme or scroll, and a `.vtt` gives the same names with exact times. The author doubted it would work; set aside in the import names spec (`docs/superpowers/specs/2026-11-20-import-names-design.md` §2). Worth another look only for meetings with the timeline and no transcript.
- **Finishing an interrupted session** after a quit or crash. *Why not now:* audio is deleted on purpose; the note keeps what was written.

### Security and housekeeping

From the audit of 2026-10-06. The items about the old Lua tool (whisper-server, sox, curl, `killStale`, `serverPort`) went away with the native app.

- **Tighter file permissions** *(declined for now)*. Config and history are `0644` and their folders `0755`. The home folder is already closed to other users, so this is defence in depth.
- **Recent menu reads the last 64 KB of history** (`History.tailBytes`); one huge transcript can push older ones out of the menu.
- **Pre-commit guard** against force-adding `tools/accuracy/recordings/`.
- **Checking GitHub for a new version** (the author, 2026-11-22). *Why not now:* only the author installs Shepit, built from source, and merges each release, so a check would tell nothing new; and it would be the first network call that isn't a model download the user asked for ("Everything stays local" in `CLAUDE.md`). Back to it with "A build colleagues can install"; then at most a Check for updates… button that reads `https://api.github.com/repos/ibatura/shepit/releases/latest` only when clicked.
- **Integration tests** for the running app (capture, engines, a long soak run): covered by unit tests and manual checks only.

## Minor ideas

Small things to come back to; none blocks the next part.

- **Clearer colours for the call panels' buttons** (the author, 2026-11-18). The panels shown when a transcript starts or ends (Start transcript, Not this call, Start now, Don't record, Keep recording, Stop now) could colour their buttons so the right one is quicker to find and press. To think over with the author.
- ~~**Highlight a person's lines in a meeting**~~ (the author, 2026-11-18): done on branch `voices` (2026-11-19), manual check L15.
- ~~**Delete a line, or all of a person's lines, from a meeting**~~: done on branch `voices` (2026-11-19), manual check L16. The author decided the window may delete lines (not edit them): Delete line at once, Delete all their lines… after a question. As asked (the author, 2026-11-19): Speaker detection sometimes makes a person of a single stray word (one "end", 0.01% of the words): the author wants to delete that line from the note, or at least delete every line of a person from the person's row in Meetings. This changes the transcript itself, which so far is read only in the window (decided 2026-11-11: editing happens in Obsidian), so it needs that decision first; the store's lines, words and samples would go with the note's entries.
- **A better look for the Dictations section.** The author has design remarks after trying it on 2026-11-16 (Task 4 of the Dictations and Dictionary plan) and wants the section to look better. To go through with the author; the section works as it is.
