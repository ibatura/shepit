# Meeting transcription — Design

Date: 2026-10-17, revised 2026-10-18 (twice: second revision moves it to the native app)
Status: Draft, awaiting review

**Revision 2 (2026-10-18):** the tool is being rewritten as a native Swift app
(`2026-10-18-native-app/`). This feature is **phase 3** of that rewrite and is built
in the native app, not in Lua. What the user sees (note format, file names,
settings, menu items, speaker labels after the call) is unchanged. How it works
inside (§5.1–5.3, §5.8, §5.10, §6, §7, §8) is revised: no helper process, no
growing WAV files, no whisper-server, Silero VAD instead of an energy detector.

## 1. Intent

The user has work calls in Microsoft Teams (desktop app) and Google Meet (browser),
often mixing English and Ukrainian. They want the conversation transcribed live,
locally, into a Markdown note for Obsidian, in a folder they choose, so they can
read or copy it later. Remote participants should be told apart by voice (Person 1,
Person 2, …) so the user can match them against the Teams transcript afterwards and
put real names in.

This is a new mode of the dictation tool, built in the native app
(`2026-10-18-native-app/00-overview.md`). Everything stays on the Mac.

## 2. Decided by the user

- Live transcription of Teams / Google Meet calls, written to a file as it goes; the
  text can be copied afterwards.
- Call audio is captured with a **Core Audio process tap** (macOS 14.2+), not a
  virtual audio driver (BlackHole) and not the meeting app's own captions.
- Output is a **Markdown note for Obsidian**. Entry format, from the user's sample:
  ```
  [Ivan Kan] 2026-07-31 18:22:37
  all 40 years history of public data, right, or whatever, financials, probably less, but…
  [Olha Barbara] 2026-07-31 18:22:45
  One. What's the urgency in Friday evening?
  ```
- Notes must **not** go to iCloud by default. The folder is a setting in
  `settings.json` with a local default; the user will point it where they want later.
- The note's file name is configurable in `settings.json` from parts such as date,
  time and the meeting name; the user asked for the full set of options (§5.4).
- Remote speakers labelled **Person 1, Person 2, …** by a small **local** model that
  tells voices apart; real names are fixed by the user afterwards by matching with
  the Teams transcript.
- Approved: Person labels appear **after the call ends**. During the call the note
  shows the user's own name and `[Співрозмовники]` for everyone else. Call audio is
  kept on disk only until speaker detection finishes (~115 MB per hour), then
  deleted. The model is downloaded at install time, so calls need no network.
  A menu item renames speakers in the note.
- Implementation: everything in the native Swift app (revision 2; supersedes "capture
  and speaker detection in Swift, the rest in Lua"). The meeting transcript uses the
  engine chosen for the `meetings` task (`2026-10-18-native-app/02-engines.md`).

## 3. Goals, non-goals, anti-goals

**Goals**
- Start/stop a meeting transcript from the 🎙 menu; the note appears in the meetings
  folder at once and fills a few seconds behind the conversation.
- The user's own speech (microphone) and the call (system audio) are recorded as two
  separate streams, so the user's entries are always labelled with their name.
- After stop: remaining phrases are finished, remote speakers are detected and the
  `[Співрозмовники]` labels become `[Person N]`.
- Copy the transcript, rename speakers, open the meetings folder — from the menu.
- Dictation (⌥Space) keeps working during a meeting.

**Non-goals (v1)** — candidates for `docs/future-ideas.md`
- Real names from Teams/Meet (UI scraping, Graph API) or automatic matching with an
  exported Teams transcript.
- Meeting names from calendars (Outlook, macOS Calendar).
- Speaker labels live during the call.
- On-screen live captions; auto-start when a call begins; meeting summaries.
- Capturing only the meeting app's audio (v1 records all system audio except
  the app's own sounds).
- Echo cancellation — headphones are required for clean attribution (see §4.5).
- Finishing an interrupted session after the app quits or crashes.

**Anti-goals** — failure even if it "works"
- Any audio or text leaving the Mac through the tool.
- Dictation becoming noticeably slower or unreliable during a meeting.
- Losing transcript text: phrases are appended as they are recognized; a crash may
  lose only the phrases still in progress.
- Overwriting the user's edits to the note: post-call steps change only the speaker
  label in header lines.
- Audio left on disk after the meeting is processed.

## 4. Constraints and facts

### 4.1 Spike results (2026-10-17, throwaway code, not in the repo)
The spike ran as a helper launched by Hammerspoon. In the native app the tap runs
inside `Shepit.app`, which declares its own `NSAudioCaptureUsageDescription` and
gets its own Screen & System Audio Recording permission, so the "unverified
permission" question below goes away; the API sequence and the sample-rate trap
still apply.

- A Swift command-line program launched by Hammerspoon via `hs.task` captured system
  audio on macOS 26.4 with a Core Audio process tap, **without any prompt**.
  Hammerspoon already has Screen Recording permission (`hs.screenRecordingState()`
  is true). Hammerspoon's Info.plist has no `NSAudioCaptureUsageDescription`; how
  permission works on a Mac that never granted it is **unverified**.
- API sequence that worked: `CATapDescription(monoGlobalTapButExcludeProcesses: [])`,
  `isPrivate = true`, `AudioHardwareCreateProcessTap`, read `kAudioTapPropertyFormat`,
  `AudioHardwareCreateAggregateDevice` with the tap in `kAudioAggregateDeviceTapListKey`
  (`kAudioSubTapUIDKey`, drift compensation on), private, `TapAutoStart`;
  `AudioDeviceCreateIOProcIDWithBlock`; `AVAudioConverter` to 16 kHz mono; 16-bit PCM
  WAV written as it goes; SIGINT/SIGTERM finalize the header.
- **Sample-rate trap:** with Bluetooth headphones (MOMENTUM 4) the tap reported
  48 kHz, but an aggregate that also contained the output device ran at 44.1 kHz, so
  the audio came out 8% fast. Fix: configure the converter with the aggregate
  device's `kAudioDevicePropertyNominalSampleRate`. A tap-only aggregate (no output
  sub-device) ran at 48 kHz and was correct too. Both gave a speech duration equal
  to the source clip to the millisecond.
- The captured clip, sent to the local `large-v3`, gave exactly the same text as the
  source file.

### 4.2 whisper-server (v1.9.4, patched, already used by the tool)
*Revision 2: there is no server in the native app; this section is kept as
background on whisper's segment behaviour, which also applies to whisper.cpp
in-process. Engines and their segment output are in `2026-10-18-native-app/02-engines.md`.*

- One inference at a time; requests queue. The server starts with `-nt` (no
  timestamps), but each request can override fields.
- `response_format=verbose_json` + `no_timestamps=false` returns `segments[]` with
  `text`, `start`, `end` (seconds; mapped back to the original audio when VAD is on)
  and the detected `language`.
- With `verbose_json`, token timestamps default on, which makes whisper wrap
  segments at 60 characters mid-word — send `token_timestamps=false`. Send
  `no_language_probabilities=true` to skip an extra detection pass.
- Cost per request is roughly constant (~1–3 s on the M1 Pro for `large-v3`)
  because the encoder always processes a 30 s window.

### 4.3 Speaker detection: FluidAudio
- Swift package (Apache-2.0, macOS 14+). Its offline pipeline (`OfflineDiarizerManager`
  per its docs: pyannote community-1 segmentation + WeSpeaker embeddings + VBx
  clustering) is its best-quality option; input is 16 kHz mono Float32, output is
  speaker segments with times and speaker IDs. Models come from Hugging Face
  `FluidInference/speaker-diarization-coreml` (licence "scoped-cc-by-4.0"), can be
  prepared into a chosen directory, and the library has an offline mode.
  **Exact API names must be verified against the pinned version.**
- Streaming diarizers (LS-EEND, Sortformer) were rejected: weaker, and speaker
  numbering drifts over long meetings.

### 4.4 Machine
Apple M1 Pro, 32 GB, macOS 26.4, Swift 6.3.3. Both whisper models stay loaded
(~5.3 GB). Account full name: "Ivan Batura".

Documents, Desktop, Downloads and iCloud Drive are protected by macOS privacy
controls: an app's first access shows a one-time prompt, and the call blocks until
it is answered (seen 2026-10-17: listing a folder in iCloud Drive from the terminal
hung). The default meetings folder is outside them. If the user points
`meetingsFolder` at one of them, the first access must happen when they expect it —
at Start, by creating the note before any capture begins, off the main thread so
the UI doesn't freeze — and the README tells them to click Allow.

### 4.5 Known limitations (to document)
- All sound playing on the Mac (music, videos, notification sounds) is captured and
  transcribed as call audio, except the app's own sounds.
- With speakers instead of headphones the microphone hears the call, and remote
  speech also appears under the user's name.
- The microphone is recorded even when muted in Teams.
- Overlapping speech and similar voices reduce speaker accuracy; a whisper segment
  that spans a speaker change gets one label.
- Teams/Meet do not notify participants about this recording — the user should
  tell them and follow company policy.

## 5. How it works

```
 🎙 menu ─ Start/Stop ─▶ meeting session (in Shepit.app)
                          ├─ process tap ─▶ call stream (system audio)
                          ├─ AVAudioEngine ─▶ mic stream (microphone)
                          ├─ Silero VAD ×2: cut phrases from each stream
                          ├─ queue ─▶ `meetings` engine ─▶ segments
                          └─ note writer ─▶ <meetingsFolder>/<file name>.md
 after Stop:  finish queue ─▶ FluidAudio diarization of call.wav ─▶ relabel note ─▶ delete audio
```

### 5.1 Capture
- **Call audio — Core Audio process tap**, inside the app. Global mono tap of all
  processes except the app itself (so its sounds are not captured), set up as in
  §4.1. Converted to 16 kHz mono Float32. Must keep recording when the output device
  changes (headphones ↔ speakers, Bluetooth disconnect) — re-read the rate and
  rebuild the converter, or restart the tap while continuing the same stream.
- **Microphone — the same recorder as dictation** (`AVAudioEngine`, `microphone`
  setting, device fallback), running for the whole session. Dictation during a
  meeting shares this input (§5.8).
- Each stream keeps a monotonic sample counter and the wall-clock time of its first
  sample; offsets are in samples from the stream start.
- The call stream is also appended to `call.wav` (16 kHz mono 16-bit) in a private
  session dir `$TMPDIR/dictation/meeting-<id>/`, for speaker detection after the
  call. The microphone stream is not written to disk.

### 5.2 Phrase detection
- Silero VAD (via FluidAudio, already a dependency) on each stream, in memory: a
  phrase ends after a pause of ~0.6 s; a phrase longer than ~25 s is cut at the
  lowest-speech-probability point near the limit; blips with less than ~0.4 s of
  speech are dropped. Small padding before/after.
- Each phrase is queued with: stream, offsets in the stream, wall-clock start time,
  and its samples (in memory).
- The phrase cutter is pure logic over VAD probabilities and unit-tested with
  synthetic probability sequences.

### 5.3 Transcription queue
- One queue for both streams, ordered by phrase start; one request in flight on the
  `meetings` model. If that model is the same one dictation uses, a dictation goes
  first: no new chunk starts while a dictation is waiting or running, so it waits
  for at most the one chunk already in flight (~1–3 s with `large-v3`).
- Request: `language` from `meetingLanguage` (default `auto`), the same prompt as
  dictation (style prompt + dictionary terms), segment times wanted. With whisper
  engines this means timestamps on and token timestamps off (see §4.2). Each
  returned segment goes through the dictionary post-processing; empty ones are dropped.
- If the `meetings` engine can't give segment times, the whole phrase is one entry.
- Every whisper segment becomes one entry: label, wall-clock start, stream offsets
  (start/end), text.
- A failed chunk (after the transcriber's existing retry) becomes an entry with the
  text `⚠ не вдалося розпізнати` so the gap is visible.

### 5.4 The note

**Folder and file name**
- Notes go to `meetingsFolder` (§5.9), created if missing. The file name comes from
  the `meetingFileName` template, filled in with the session's start time (local
  time); `.md` is added.
- Placeholders:

  | placeholder | example | value |
  |---|---|---|
  | `{date}` | `2026-10-18` | start date |
  | `{time}` | `14-30` | start time, hours and minutes (no colon: Obsidian forbids it in file names) |
  | `{year}` `{month}` `{day}` | `2026` `10` `18` | parts of the date |
  | `{hour}` `{minute}` | `14` `30` | parts of the time |
  | `{weekday}` | `Sat` | `Mon` … `Sun`, independent of the system language |
  | `{title}` | `Weekly sync` | meeting name (below); may be empty |
  | `{app}` | `Teams` | `Teams` or `Meet` if detected at Start; may be empty |

- `/` in the template makes subfolders, created as needed.
- Cleanup after filling in: in each folder or file part, repeated spaces are
  collapsed and spaces and separators (`-` `–` `—` `_` `·` `,` `.`) are trimmed at
  both ends; parts left empty are dropped. If nothing is left, `{date} {time}` is used.
- `{title}` and `{app}` values are made file-name safe: characters Obsidian forbids
  or uses for links (`/ \ : * ? " < > | # ^ [ ]`) and control characters become
  spaces; at most 80 characters.
- If the name is taken, ` (2)`, ` (3)`, … is added.
- Examples:

  | `meetingFileName` | result |
  |---|---|
  | `{date} {time} {title}` (default) | `2026-10-18 14-30 Weekly sync.md`; without a name `2026-10-18 14-30.md` |
  | `{date} {title}` | `2026-10-18 Weekly sync.md` |
  | `{year}/{month}/{date} {time} {app} {title}` | `2026/10/2026-10-18 14-30 Teams Weekly sync.md` |
  | `Meeting {date} {time}` | `Meeting 2026-10-18 14-30.md` |

**Meeting name (`{title}`)**
- Detected at Start, best effort, from window titles (read through the
  Accessibility API, which the app already has for pasting): a Teams meeting window (with the
  ` | Microsoft Teams` suffix removed; main-window views such as Chat, Calendar or
  Activity are ignored) or a browser window showing Google Meet (with the browser
  suffix removed). A bare Meet code like `abc-defg-hij` is not used as a name. The
  same detection gives `{app}`. The exact title patterns are taken from a real call
  (§8).
- With `meetingAskTitle` on (default) and `{title}` in the template, Start shows a
  small "Meeting name" dialog prefilled with the detected name: Enter accepts, an
  empty field means no name, Cancel doesn't start the session. Capture starts after
  the dialog; focus then returns to the app that was in front.
- With `meetingAskTitle` off, the detected name is used as is (empty if none).
- The name can't be changed from the tool after Start; rename the file in Obsidian
  after the call.

**Content**
- Created at Start with front matter only. `title` and `app` lines are written only
  when known; `time` is quoted so YAML doesn't read 14:30 as a number:
  ```
  ---
  date: 2026-10-18
  time: "14:30"
  title: "Weekly sync"
  app: Teams
  tags: [transcript]
  ---
  ```
- Each entry is appended as `[<label>] YYYY-MM-DD HH:MM:SS` + newline + text
  (one line) + newline; no blank lines, exactly like the user's sample. Labels:
  `meetingMyName` (default: macOS account full name) for the microphone,
  `Співрозмовники` for the call.
- **Chronological order:** entries are appended in order of start time. An entry
  starting at t is written only when no stream can still produce an entry that
  starts before t (both streams' unfinished audio — open phrase or queued chunk —
  starts at or after t). So an interjection waits for the other side's open phrase,
  at most ~25 s plus recognition time.
- The note is append-only during the call. The user can keep it open in Obsidian;
  editing it is safer after the call. If the note disappears mid-call (renamed,
  moved, deleted), it is recreated at the same path with the same front matter and
  writing continues; the README says to rename or move the note only after
  "Transcript ready".

### 5.5 After Stop
1. Stop both captures (`call.wav` header finalized); the open phrases become final
   chunks.
2. Drain the queue and write the remaining entries. Start is disabled until the
   session completes.
3. Run FluidAudio's offline diarization (§4.3) on `call.wav`, in the app, with the
   models from disk and no network (expected ~1 min per hour of audio).
4. Map each `[Співрозмовники]` entry to the speaker with the largest overlap with its
   stream offsets; if none overlaps, the nearest speaker segment within ~2 s;
   otherwise keep the live label. Speakers are numbered by first appearance in the
   note: the first remote voice is `Person 1`.
5. Relabel the note in place: only header lines that still read exactly
   `[Співрозмовники] <time>` are changed, matched to entries by timestamp (and order
   within the same second). Everything else stays as the user left it. Written via
   temp file + rename.
6. Delete the session dir (audio and chunks), whether speaker detection succeeded or
   not. Notify: transcript ready, N speakers.

### 5.6 Menu, status, notices
- New items: **Start meeting transcript** / **Stop meeting transcript**,
  **Copy last meeting transcript**, **Rename speakers…**, **Rename speakers in
  another note…**, **Open meetings folder**. English labels, like the rest of the menu.
- Status line while active: `Meeting: recording 12:34 · 2 phrases waiting`, then
  `Meeting: finishing (3 left)`, `Meeting: detecting speakers…`.
- The menu-bar title gets a `⏺` mark while a session is active, next to the usual
  dictation icon, which keeps its meaning.
- Start/stop/done/errors are shown the same way as dictation notices.
- Settings → Meetings shows the meeting keys (§5.9) with a live example of the file
  name; Statistics records one row per meeting (`2026-10-18-native-app/05-statistics.md`).

### 5.7 Copy, rename, open
- File names come from a template, so the last transcript can't be found by name:
  the tool keeps the path of the newest note in `~/.local/share/dictation/last-meeting`
  (one line of text). During a session that's the current note.
- **Copy last meeting transcript:** that note without its front matter, to the
  clipboard.
- **Rename speakers…:** on that note. For each distinct label, in order of first
  appearance, a text prompt shows the label, the time and text of its first
  sentence-length entry (to find it in the Teams transcript) and asks for a name.
  Empty or unchanged = skip; Cancel = stop. Only header lines are rewritten; mapping
  two labels to one name merges them.
- **Rename speakers in another note…:** the same, on a note picked in a file chooser
  that opens in `meetingsFolder` — for older notes.
- **Open meetings folder:** in Finder.

### 5.8 Dictation during a meeting
Works as usual, on the same microphone input. Microphone audio from hotkey down to
stop/cancel goes to the dictation and is skipped by the meeting's phrase detector,
so dictated text does not end up in the transcript.

### 5.9 Settings (`settings.json`, validated like existing keys)

| key | default | allowed | meaning |
|---|---|---|---|
| `meetingsFolder` | `"~/.local/share/dictation/meetings"` | absolute path, or starting with `~/` | Where notes go; created if missing. Point it at a folder in your Obsidian vault |
| `meetingFileName` | `"{date} {time} {title}"` | template, §5.4 | File name without `.md`; `/` makes subfolders |
| `meetingAskTitle` | `true` | `true`, `false` | Ask for the meeting name at Start, prefilled with the detected one |
| `meetingMyName` | `""` | string | Label for the microphone; `""` = macOS account full name |
| `meetingLanguage` | `"auto"` | `"uk"`, `"en"`, `"auto"` | Language for meeting phrases |

`meetingFileName` is valid when it has 1–200 characters, uses only the placeholders
above, has none of `\ : * ? " < > | # ^ [ ]` outside placeholders, does not start
with `/` and has no empty, `.` or `..` folder parts. Errors are reported like other
settings errors; the last good settings stay in use.

The user's own `settings.json` is not changed; they will set `meetingsFolder` and
`meetingFileName` themselves. `examples/settings.json` and the README get the new
keys with examples. The meeting engine is chosen with `engines.meetings`
(`2026-10-18-native-app/04-settings.md`).

### 5.10 Limits and housekeeping
- A session stops by itself after 30 minutes with no speech in either stream (the
  user probably forgot) or after 4 hours; a notice says so.
- At startup, leftover `meeting-*` session dirs are deleted.
- On app quit during a session: Quit asks first; if confirmed, both captures stop,
  the note keeps what was already written, and a final line
  `⚠ Запис перервано о HH:MM:SS` is appended. Same on logout/shutdown. No resume.
  While a session runs, the note's path is also kept in
  `~/.local/share/dictation/active-meeting`; it is removed when the session
  completes. After a crash, the next launch finds that file, appends the line to
  that note (if it still exists), deletes any leftover session dir with its audio,
  and removes the file. No audio survives a relaunch.

## 6. Error handling

| Situation | Behaviour |
|---|---|
| Diarization models not downloaded | Start works; a notice says speakers won't be detected and how to download them (Settings → Meetings) |
| `meetings` model not downloaded | Start shown disabled with "(download the model in Settings)" |
| Tap can't be created (macOS < 14.2, permission) | Session doesn't start; notice explains, mentions Screen & System Audio Recording |
| Call stream is exact silence while the mic has had > 2 min of speech | One notice: call audio may not be recorded — check the permission |
| Mic can't start | Session doesn't start; existing mic-permission message |
| One capture dies mid-session | The other continues; a `⚠ … stopped at HH:MM:SS` line goes in the note; notice |
| Chunk recognition fails | `⚠ не вдалося розпізнати` entry; session continues |
| Meeting-name dialog cancelled | Session doesn't start; no file is created |
| `meetingsFolder` in a protected location (Documents, iCloud Drive, …), first use | macOS asks the app for access once; the note is created before capture starts |
| Meetings folder can't be created / written | Session doesn't start (or stops), notice with the path and error |
| Last transcript moved or deleted | Copy / Rename say so; "Rename speakers in another note…" still works |
| Diarization fails / models missing | Labels stay `[Співрозмовники]`; notice with the reason |
| `meetings` engine changed in Settings mid-session | The session keeps the engine it started with; the change applies to the next session |

## 7. Build, install, uninstall

- Part of `Shepit.app` (`2026-10-18-native-app/01-app-build-signing.md`); no
  separate helper or build script. FluidAudio is already a pinned dependency
  (Parakeet engine).
- Diarization models into `~/.local/share/dictation/models/diarization/`, pinned to
  a fixed revision and verified like the other models; downloaded by `install.sh`
  and from Settings → Meetings (a Download button, like engine models).
- `uninstall.sh --purge` removes the data dir, which includes the default meetings
  folder but never a custom `meetingsFolder`. `tests/install_test.sh` stays green.
- README: requirements (macOS 14.2+), one-time permission (System Settings →
  Privacy & Security → Screen & System Audio Recording → Shepit), menu items,
  settings with file-name examples, limitations §4.5, privacy (notes are in
  `meetingsFolder`, local by default — a synced folder such as iCloud Drive uploads
  them; audio deleted after processing; consent), and that `--purge` deletes
  transcripts kept in the default folder.

## 8. Testing

- **Unit (Swift tests, like the rest of the app):** phrase cutter (synthetic VAD
  probability sequences: speech/pause patterns, 25 s cut, blips, dictation skip
  ranges); queue order, dictation priority and the chronological-flush rule; note
  format and front matter with and without title/app; file names (each
  placeholder, subfolders, cleanup of empty parts, unsafe characters,
  80-character cap on UTF-8 text, collisions, `.md`) and template validation;
  meeting-name detection as a pure function over sample window titles; front
  matter stripping for Copy; speaker mapping (overlap, nearest, numbering,
  unassigned); header-only relabel and rename, including merging and lines the user
  edited; new settings validation.
- **Capture smoke test (manual):** capture while `afplay` plays a known clip;
  check duration and that the engine gives the expected text — with Bluetooth
  headphones and with the built-in speakers.
- **Quality check, before polishing the UI:** play a public multi-speaker recording
  (e.g. a podcast) through system audio, then do one real Teams call with the user.
  Report transcription quality and speaker attribution against the Teams
  transcript (share of remote entries with the right Person). If attribution is
  poor, stop and report before building rename. During the call (and a Meet call if
  possible) note the window titles to set the meeting-name patterns.
- **Manual checklist additions:** start/stop; note fills while open in Obsidian;
  meeting-name dialog (accept, empty, cancel); dictation during a meeting is not in
  the transcript; output device switch and Bluetooth disconnect mid-call; quitting
  the app mid-call; 1-hour call (no growing backlog, speaker detection < 2 min);
  copy; rename/merge in the last and in an older note; missing models; permission
  denied; first-time permission flow (the app gets its own permission, so this is
  tested on this Mac by granting it on first meeting start).

## 9. My calls (shown to the user, not explicitly confirmed)

- Default `meetingsFolder` is `~/.local/share/dictation/meetings`: local, not
  synced, no macOS permission prompt, next to `history.log`. It is hidden in Finder
  (the menu opens it) and `uninstall.sh --purge` deletes it, like the history.
- Default `meetingFileName` is `{date} {time} {title}`; `.md` is added; `/` makes
  subfolders; extra placeholders `{year}`, `{month}`, `{day}`, `{hour}`, `{minute}`,
  `{weekday}`, `{app}`.
- Meeting name: detected from window titles, plus a dialog at Start (on by default);
  Cancel doesn't start; no renaming from the tool after Start.
- Front matter: date, quoted time, title and app when known, `tags: [transcript]`.
- The last transcript's path is kept in a small state file; older notes are renamed
  through a file chooser.
- A note that disappears mid-call is recreated at the same path.
- One entry per whisper segment, even for consecutive phrases by the same person.
- `meetingLanguage` defaults to `auto` (calls mix English and Ukrainian).
- Live label text `Співрозмовники`; own label from the macOS account name.
- English menu labels; Start disabled while the previous session is finishing.
- Microphone audio during a dictation is excluded from the transcript.
- Auto-stop after 30 min of silence or 4 h; no resume after quit or crash; audio
  deleted even when speaker detection fails.
- The app's own sounds excluded from the tap.
- Copy omits front matter.
- Phase 3 gate: before building the rest of the meeting feature, verify on this Mac
  that `Shepit.app` gets the Screen & System Audio Recording prompt at first tap
  creation, that capture works after Allow, and what happens after Deny (the notice
  in §6 then says how to turn it on in System Settings). If the app can't get the
  permission, stop and report.
- Protected `meetingsFolder` (iCloud Drive, Documents…): the app is not sandboxed,
  so plain file access works after the one-time macOS prompt; no security-scoped
  bookmarks.
- Permission: the app declares `NSAudioCaptureUsageDescription` and asks for Screen
  & System Audio Recording under its own name at the first meeting start
  (revision 2; replaces the Hammerspoon permission plan).
- Revision 2: the call stream is kept on disk (for diarization) but the mic stream
  is not; phrase detection uses Silero VAD; a crashed session's note gets the
  "interrupted" line on next launch; changing the `meetings` engine mid-session
  applies to the next session.
- The quality check (§8) needs one real Teams call with the user.

## 10. Left to the builder

Module and file layout in the app; phrase-detection constants; tap-only vs
output-device aggregate (tap-only preferred; whichever survives device switching);
how to restart the tap on device change; exact menu wording and placement; escaping
of Markdown markers at the start of a text line; how wall-clock times stay right
after the Mac sleeps mid-call; whether to merge very short consecutive chunks to
reduce engine load; whether to re-run chunks detected as neither Ukrainian nor
English with `language=uk` (decide from the quality check); exact window-title
patterns, and how to find a Meet tab that isn't the active one (the accessibility
tree is fine; no Apple Events, which would need another permission).
