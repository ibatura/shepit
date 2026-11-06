# Shepit Phase 3 — Meeting Transcription Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** From the 🎙 menu the user starts a meeting transcript. Shepit records the microphone and the call audio (Core Audio process tap) as two streams and writes a Markdown note for Obsidian that fills a few seconds behind the conversation. After Stop, remote voices are relabelled `Person 1, Person 2, …` by local diarization and the call audio is deleted.

**Architecture:** Same SwiftPM package. Pure logic goes in `ShepitCore` and is fully unit-tested: meeting settings, file-name template, note format and writer, phrase cutter over VAD probabilities, transcription queue with the chronological-flush rule, speaker mapping, relabel/rename, and window-title parsing. System code goes in `Shepit` behind small protocols: process tap, shared microphone, Silero VAD and FluidAudio diarizer adapters, AX window titles, dialogs and menu. A `MeetingSession` in core runs one session from Start to "Transcript ready" through those protocols, so the whole flow is tested with fakes. Recognition goes through the existing `ModelHost` (`.meetings` task, dictation first).

**Tech Stack:** as phase 2, plus Core Audio process taps (`CATapDescription`, `AudioHardwareCreateProcessTap`, aggregate device, IOProc), `AVAudioConverter`, FluidAudio `VadManager` (Silero) and `OfflineDiarizerManager` (already a dependency at 0.17.7), `NSAlert` text prompts, `NSOpenPanel`.

**Spec:** `docs/superpowers/specs/2026-10-17-meeting-transcription-design.md` (rev. 2, "the spec" below; section numbers refer to it). Also `2026-10-18-native-app/02-engines.md` §3–4 (the `meetings` task), `04-settings.md` (Meetings section), `05-statistics.md` §1–2 (meeting row, tile, stacked chart), `01-app-build-signing.md` (permission, purge).

**Branch:** `shepit-phase3`, cut from `main` (aa19fd9). The user merges into `main` themselves; ask first.

## Execution notes

- Same as phase 2: **the controller implements inline**, one task at a time. A reviewer subagent runs only for the risky tasks: 8 (capture), 9 (session) and 6 (note rewriting).
- Ponytail style (full): smallest complete change, a test for every non-trivial branch, no speculative options.
- **User gates: Tasks 0, 11 and 15.** Stop and run them with the user. Task 0 can stop the phase.
- Ledger: `.superpowers/sdd/2026-10-25-shepit-phase3/progress.md`, same format as phase 2.
- Before any temporary CLI command, check that the build succeeded. A failed build used to run the old binary as a second app instance.

## Deviations from the spec (already decided in phases 1–2)

- The microphone recorder is **AVCaptureSession**, not AVAudioEngine (§5.1 says AVAudioEngine). AVAudioEngine was dropped in phase 2: it hung on device switch, gave garbage audio and kept Bluetooth headsets in HFP mode. The meeting reuses `AudioRecorder`, extended to run continuously and give dictation a slice (Task 8).
- Silero VAD in FluidAudio 0.17.7 is the unified 256 ms model (4096 samples per frame). Phrase constants (§5.2) are converted to frames: pause 0.6 s ≈ 3 frames, blip 0.4 s ≈ 2 frames, cut at 25 s ≈ 98 frames. The cutter takes the frame length as a parameter, so a finer VAD can replace it later.
- The default meetings engine is whisper.cpp `large-v3-turbo`, as decided on 2026-10-23 (the spec example says `large-v3`).

## Global Constraints

- No audio or text leaves the Mac. The only network use is a model download the user started (Settings or `install.sh`). FluidAudio must load in **offline mode** and must never download on its own (Task 7 pins this).
- Dictation (⌥Space) keeps working during a meeting and is not slowed down. `ModelHost` already runs `.dictation` before queued `.meetings` requests; Task 4 adds a test for it. Microphone audio from hotkey down to stop/cancel is skipped by the meeting's phrase cutter.
- Transcript text is never lost: each entry is appended (and flushed) as soon as the chronological rule allows. Post-call steps rewrite only header lines that still read exactly `[Співрозмовники] <time>`, via temp file + rename.
- Audio is never left on disk: the session dir is deleted after diarization, whether it succeeded or not. Leftover `meeting-*` dirs are deleted at launch.
- `meetingsFolder` defaults to `~/.local/share/dictation/meetings`, never iCloud (user memory: local storage by default). The user's own `settings.json` is not changed.
- `stats.sqlite` gets one row per meeting with numbers only, no text and no speaker names.
- Constants from the spec, not re-invented: pause 0.6 s, max phrase 25 s, min speech 0.4 s, nearest speaker within 2 s, auto-stop after 30 min of silence or 4 h, silent-call notice after > 2 min of mic speech, `{title}` capped at 80 characters, template 1–200 characters.

## Review Focus

1. **Dictation is never delayed by a meeting chunk** beyond the one already running, and dictated audio is not in the transcript. Pinned by the `ModelHost` test (Task 4) and the cutter skip-range tests (Task 3).
2. **The user's edits survive relabel and rename.** Only exact live header lines change; a header the user edited stays as is. Pinned by Task 6 tests.
3. **Entries come out in time order across the two streams** and none is lost when one stream dies or the note is deleted mid-call. Pinned by Tasks 4 and 5.
4. **No audio after the session**, including after a failed diarization and after a crash (next launch). Pinned by Task 9 tests with fakes, and checked by hand in Task 15.
5. **Correct speed of call audio** with Bluetooth and built-in output: the converter uses the aggregate's nominal rate (spec §4.1 sample-rate trap). Checked in Task 0 and again in Task 8.

---

## File Structure

```
app/Sources/ShepitCore/
  Settings.swift / SettingsValidation.swift   + meeting keys (Task 1)
  MeetingFileName.swift     template fill, cleanup, safe parts, collisions, validation (Task 2)
  MeetingNote.swift         front matter, entry lines, append writer, recreate, interrupted line, strip for Copy (Task 5)
  PhraseCutter.swift        VAD probabilities → phrases; 25 s cut; blips; skip ranges (Task 3)
  MeetingQueue.swift        chunks in start order, chronological flush rule (Task 4)
  Speakers.swift            diarization segments → Person N per entry; relabel and rename header lines (Task 6)
  MeetingTitle.swift        window titles → (title, app) (Task 10)
  MeetingSession.swift      one session: Start → capture → queue → note → Stop → diarize → relabel → cleanup (Task 9)
  ModelCatalog.swift        + diarization and VAD models (Task 7)
  Stats.swift / StatsDatabase.swift   + meetings table and aggregations (Task 13)
app/Sources/ShepitEngines/
  MeetingModels.swift       Silero VAD and offline diarizer adapters, offline mode (Task 7)
app/Sources/Shepit/
  CallTap.swift             process tap + aggregate + converter → 16 kHz mono stream, device change restart (Tasks 0, 8)
  AudioRecorder.swift       + continuous mode with dictation slices (Task 8)
  MeetingUI.swift           name dialog, rename prompts, note picker, quit confirmation (Tasks 10, 12)
  AppHost.swift / MenuController.swift / MenuModel  + meeting items, status line, ⏺ mark (Task 10)
  Settings/MeetingsSection.swift   keys, live file-name example, diarization download (Task 14)
scripts/models/diarization.sha256, silero-vad.sha256   pinned manifests (Task 7)
scripts/download-models.sh, install.sh, uninstall.sh   + meeting models (Task 7, 14)
```

---

### Task 0: GATE — process tap and permission in Shepit.app (with the user)

**Files:** Create `Shepit/CallTap.swift` (first version), a `tap-test <seconds> <out.wav>` command in `main.swift`; modify `app/Info.plist` (or `build-app.sh` plist) with `NSAudioCaptureUsageDescription`.
**Spec:** §4.1, §9 "Phase 3 gate", §6 row "Tap can't be created".

- [ ] **Step 1:** `CallTap` per §4.1: `CATapDescription(monoGlobalTapButExcludeProcesses: [own process object])`, private; tap-only aggregate (no output sub-device, preferred by §10), drift compensation on, `TapAutoStart`; IOProc block → `AVAudioConverter` set up from the aggregate's `kAudioDevicePropertyNominalSampleRate` → 16 kHz mono Float32 callback. `stop()` tears everything down in reverse order.
- [ ] **Step 2:** The command runs **inside the app bundle** so that TCC attributes it to Shepit and not to the terminal: `open -n -a ~/Applications/Shepit.app --args tap-test 10 /tmp/…/call.wav`. It writes a WAV and logs the input rate and the sample count to a file next to it.
- [ ] **Step 3 (user):** with the installed app, while `afplay` plays a known clip: (a) the first run shows the Screen & System Audio Recording prompt under the name Shepit; (b) after Allow the WAV has the clip at the right speed (duration equal to the clip ±50 ms) with MOMENTUM 4 and with the built-in speakers; (c) after Deny (reset with `tccutil reset AudioCapture com.….shepit`) what the API returns, so that §6 can show the right notice. The clip from (b) goes through `Shepit bench` with the meetings engine and must give the same text as the source file.
- [ ] **Step 4:** Record results in the ledger. **If the app can't get the permission, stop the phase and report.** Commit `Shepit: call audio capture through a process tap`.

### Task 1: Meeting settings

**Files:** Modify `ShepitCore/Settings.swift`, `SettingsValidation.swift`, `examples/settings.json`; tests in `SettingsTests.swift`.
**Spec:** §5.9.

**Interfaces:** `Settings` gets `meetingsFolder: String`, `meetingFileName: String`, `meetingAskTitle: Bool`, `meetingMyName: String`, `meetingLanguage: Language`, plus `meetingsFolderURL(home:)` (expands `~/`) and `myName(fullName:)` (`""` → macOS account full name).

- [ ] Tests: defaults; each key's allowed and rejected values (folder must be absolute or start with `~/`); template validation delegated to `MeetingFileName.validate` (so Task 2 is done before this one); unknown keys kept on update; the user's real `settings.json` still loads. → FAIL → implement → PASS.
- [ ] `examples/settings.json` gets the keys with the default values. Commit `Shepit: meeting settings`.

### Task 2: Note file name from the template

**Files:** Create `ShepitCore/MeetingFileName.swift`, `Tests/ShepitCoreTests/MeetingFileNameTests.swift`.
**Spec:** §5.4 "Folder and file name", §5.9 validation.

**Interfaces:** `enum MeetingFileName { static func validate(_ template: String) -> String? /* error */; static func relativePath(_ template: String, start: Date, title: String?, app: String?, calendar: Calendar) -> String /* "a/b/name.md" */; static func unique(_ relative: String, in folder: URL, exists: (URL) -> Bool) -> URL }`.

- [ ] Tests, one per row of the spec tables: every placeholder; `{weekday}` is English whatever the locale; `{time}` has no colon; `/` makes folders; cleanup of spaces and separators at both ends of each part; empty parts dropped; all empty → `{date} {time}`; unsafe characters in `{title}`/`{app}` become spaces; 80-character cap on Cyrillic text; collisions give ` (2)`, ` (3)`; `.md` appended once; all four spec examples. Validation: length 1–200, unknown placeholder, forbidden characters outside placeholders, leading `/`, empty / `.` / `..` parts. → FAIL → implement → PASS.
- [ ] Commit `Shepit: meeting note file names`.

### Task 3: Phrase cutter

**Files:** Create `ShepitCore/PhraseCutter.swift`, tests `PhraseCutterTests.swift`.
**Spec:** §5.2, §5.8.

**Interfaces:** `struct PhraseCutter { init(frameSamples: Int, pause: Double = 0.6, maxPhrase: Double = 25, minSpeech: Double = 0.4, padding: Double, threshold: Float); mutating func push(probability: Float, frameStart: Int) -> [Phrase]; mutating func skip(_ range: Range<Int>); mutating func finish() -> [Phrase] }`, where `Phrase { start: Int; end: Int }` are sample offsets in the stream. The caller keeps the audio ring and slices it.

- [ ] Tests with synthetic probability sequences: one phrase ends after the pause; padding before and after, clamped at the stream start; a blip below 0.4 s is dropped; a phrase over 25 s is cut at the lowest-probability frame in the last few seconds before the limit, and the rest continues as a new phrase; `finish()` closes an open phrase; skip ranges (dictation) are left out, and a phrase that overlaps one is split around it; no phrase from silence. → FAIL → implement → PASS.
- [ ] Commit `Shepit: phrase cutter for meeting streams`.

### Task 4: Transcription queue and chronological flush

**Files:** Create `ShepitCore/MeetingQueue.swift`, tests `MeetingQueueTests.swift`; add a test to `ModelHostTests.swift`.
**Spec:** §5.3, §5.4 "Chronological order".

**Interfaces:** `enum Stream { case mine, call }`; `struct Chunk { stream; start: Int; end: Int; wallStart: Date; samples: [Float] }`; `struct Entry { stream; wallStart: Date; offsets: Range<Double>; text: String; failed: Bool }`; `struct MeetingQueue { mutating func add(_ chunk: Chunk); mutating func next() -> Chunk? /* oldest start first */; mutating func done(_ chunk: Chunk, entries: [Entry]); mutating func openPhrase(_ stream: Stream, startsAt: Date?); mutating func ready() -> [Entry] /* safe to write now, in order */; var waiting: Int }`.

- [ ] Tests: chunks come out in start order across streams; an entry waits while the other stream has an open phrase or queued chunk that starts earlier, and is released once it doesn't; entries from one chunk keep segment order; a failed chunk gives one `⚠ не вдалося розпізнати` entry; when a stream stops (capture died), its pending state no longer blocks; `finishAll` releases everything in order. In `ModelHostTests`: `dictationRunsBeforeQueuedMeetingChunk` (a meeting request queued during a dictation runs after it). → FAIL → implement → PASS.
- [ ] Commit `Shepit: meeting transcription queue`.

### Task 5: The note

**Files:** Create `ShepitCore/MeetingNote.swift`, tests `MeetingNoteTests.swift`.
**Spec:** §5.4 "Content", §5.7 Copy, §5.10 interrupted line, §6 "note disappears".

**Interfaces:** `enum MeetingNote { static func frontMatter(start: Date, title: String?, app: String?) -> String; static func entry(label: String, at: Date, text: String) -> String; static func stripFrontMatter(_ note: String) -> String; static func interruptedLine(at: Date) -> String }`; `final class NoteWriter { init(file: URL, frontMatter: String); func create() throws; func append(_ text: String) throws /* recreates file with front matter if missing */ }`.

- [ ] Tests: front matter with and without title/app, quoted time, `tags: [transcript]`; the entry format is exactly the user's sample (`[Label] YYYY-MM-DD HH:MM:SS\ntext\n`, no blank lines); text is joined to one line, and a line that starts with a Markdown marker (`#`, `-`, `>`, `[`) is escaped (§10, builder's choice: a leading backslash); append after the file was deleted recreates it with the same front matter, then the entry; `stripFrontMatter` keeps the body and is a no-op without front matter; folders on the path are created. → FAIL → implement → PASS.
- [ ] Commit `Shepit: meeting note writer`.

### Task 6: Speakers, relabel and rename (review)

**Files:** Create `ShepitCore/Speakers.swift`, tests `SpeakersTests.swift`.
**Spec:** §5.5 steps 4–5, §5.7 rename.

**Interfaces:** `struct SpeakerTurn { speaker: String; start: Double; end: Double }`; `enum Speakers { static func assign(_ entries: [(at: Date, offsets: Range<Double>)], turns: [SpeakerTurn]) -> [String?] /* "Person N" or nil */; static func relabel(_ note: String, live: String, labels: [(at: Date, label: String?)]) -> String; static func labels(in note: String) -> [(label: String, firstAt: String, firstText: String)]; static func rename(_ note: String, _ names: [String: String]) -> String }`.

- [ ] Tests: largest overlap wins; no overlap → nearest turn within 2 s, else nil; Persons numbered by first appearance in the note, not by diarizer ID; relabel changes only lines that still read exactly `[Співрозмовники] <time>`, matched by timestamp and by order within the same second; a header the user edited and body lines that look like headers stay; rename rewrites header lines only; two labels mapped to one name merge; empty or unchanged names are skipped; `labels(in:)` gives the first sentence-length entry for each label. → FAIL → implement → PASS.
- [ ] Reviewer subagent (focus: user edits survive; Unicode; same-second order). Commit `Shepit: speaker labels and renaming in meeting notes`.

### Task 7: Meeting models: Silero VAD and diarization

**Files:** Create `scripts/models/silero-vad.sha256`, `scripts/models/diarization.sha256`, `ShepitEngines/MeetingModels.swift`, tests `MeetingModelsTests.swift`; modify `ModelCatalog.swift`, `scripts/download-models.sh`, `scripts/install.sh`, `scripts/build-app.sh` (bundles manifests already), `tests/install_test.sh`.
**Spec:** §4.3, §7.

**Interfaces:** `ModelCatalog` gets `meetingModels` (VAD, diarization), with folders under `models/diarization/` in FluidAudio's expected layout and `.complete` markers, downloaded by the existing `ModelDownloader`. `actor SileroVAD { init(folder:) async throws; func probabilities(_ samples: [Float]) async throws -> [Float] /* one per 4096 samples */ }`; `struct Diarizer { init(folder:); func turns(_ samples: [Float]) async throws -> [SpeakerTurn] }`.

- [ ] **Step 1:** Pin both Hugging Face repos at a fixed revision (diarization: FluidAudio's own pinned `df2625ac…`; VAD: current commit of `FluidInference/silero-vad-coreml`, only the `silero-vad-unified-256ms-v6.2.1.mlmodelc` files and the offline-diarizer files) with `scripts/pin-model.sh`, same format as the other manifests.
- [ ] **Step 2:** Load with FluidAudio's offline mode and from our folder; verify against the pinned version that `ModelHub` finds the files and does not hit the network (revision marker file, if required, written by us). Test: a missing folder throws `modelMissing` (like `ParakeetEngine`). Smoke tests run only when downloaded: VAD on `hello.wav` gives speech frames and silence gives none; diarization on a two-voice fixture (two TTS clips concatenated, made with `say` once and committed, < 300 KB) finds 2 speakers.
- [ ] **Step 3:** `download-models.sh --with-meetings` (on by default in `install.sh`), Settings download comes in Task 14. Commit `Shepit: VAD and speaker models for meetings`.

### Task 8: Capture: call tap and shared microphone (review)

**Files:** Modify `Shepit/CallTap.swift`, `Shepit/AudioRecorder.swift`, `AppHost.swift` (dictation through the shared recorder).
**Spec:** §5.1, §5.8, §6 "one capture dies".

**Interfaces:** `protocol AudioStream: AnyObject { var onSamples: (@Sendable ([Float], _ firstSampleIndex: Int) -> Void)? { get set }; var onFailure: (@Sendable (String) -> Void)? { get set }; func start() throws; func stop() }`. `CallTap` and `MicStream` implement it. `AudioRecorder` gets a continuous mode: while a meeting runs, the capture session stays open; a dictation records a slice (start index → stop index) of the same input, and reports that range so the cutter can skip it. Without a meeting, dictation works exactly as now.

- [ ] **Step 1:** `CallTap` restarts on output-device change (`kAudioHardwarePropertyDefaultOutputDevice` listener and the aggregate's rate change): rebuild the aggregate and converter and continue the sample counter (§10: restarting is fine). A failed restart calls `onFailure`.
- [ ] **Step 2:** `AudioRecorder` continuous mode + dictation slices. The existing controller tests stay green; first-audio latency of a dictation during a meeting is ~0 (the session is already running).
- [ ] **Step 3:** Manual smoke (no user needed): a 2-minute run with `afplay` while switching output between built-in speakers and MOMENTUM 4, plus a Bluetooth disconnect. The WAV has no gap longer than the restart and the clip plays at the right speed.
- [ ] **Step 4:** Reviewer subagent (focus: threading of IOProc callbacks, teardown order, HFP not held after a meeting). Commit `Shepit: continuous call and microphone capture`.

### Task 9: Meeting session (review)

**Files:** Create `ShepitCore/MeetingSession.swift`, tests `MeetingSessionTests.swift`.
**Spec:** §5.1–5.5, §5.10, §6.

**Interfaces:** `@MainActor final class MeetingSession` with injected protocols: `MeetingCapture` (two `AudioStream`s), `VoiceDetector` (VAD), `MeetingTranscriber` (adapts `ModelHost` `.meetings` + dictionary post-processing), `SpeakerDetector`, `NoteWriter`, a clock and a session dir. States: `recording(elapsed, waiting)` → `finishing(left)` → `detectingSpeakers` → `done(speakers)` / `failed(reason)`, reported through `onState`. Produces a `MeetingRecord` for statistics (start, duration, words mine/call, speakers, engine, diarization seconds, failed chunks).

- [ ] **Step 1: Tests with fakes:** the note is created before capture starts; a folder error fails Start with the path; phrases from both streams reach the note in time order with the right labels; the call stream goes to `call.wav` and the mic stream does not; dictation ranges are skipped; a capture failure writes `⚠ … stopped at HH:MM:SS` and the other stream continues; Stop drains the queue, diarizes, relabels and deletes the session dir; failed diarization keeps live labels, deletes the dir and says why; missing diarization models → Start works with a notice; auto-stop after 30 min of silence and after 4 h; one notice when the call stream is exact silence while the mic has > 2 min of speech; the engine change mid-session doesn't affect the running session; `interrupt()` (quit) appends the interrupted line and deletes audio. → FAIL.
- [ ] **Step 2:** Implement. `active-meeting` and `last-meeting` files (§5.7, §5.10) are written here. → PASS.
- [ ] **Step 3:** Reviewer subagent (focus: no lost entries, no audio left, dictation priority). Commit `Shepit: meeting session`.

### Task 10: Menu, status, meeting name, launch cleanup

**Files:** Create `ShepitCore/MeetingTitle.swift`, tests `MeetingTitleTests.swift`, `Shepit/MeetingUI.swift`; modify `MenuModel.swift`, `MenuController.swift`, `AppHost.swift`, `main.swift`/`AppDelegate.swift` (quit confirmation).
**Spec:** §5.4 "Meeting name", §5.6, §5.7 (Copy, Open), §5.10, §6.

- [ ] **Step 1:** `MeetingTitle.detect(windows: [(app: String, title: String)]) -> (title: String?, app: String?)` with provisional patterns (Teams ` | Microsoft Teams` suffix, Chat/Calendar/Activity ignored; Meet in Chrome/Safari/Arc with the browser suffix removed; bare `abc-defg-hij` codes ignored). Tests over sample titles. The real patterns are fixed in Task 11.
- [ ] **Step 2:** Menu: Start/Stop meeting transcript (disabled while finishing, or with "(download the model in Settings)"), Copy last meeting transcript, Open meetings folder. Status line `Meeting: recording 12:34 · 2 phrases waiting` / `finishing (3 left)` / `detecting speakers…`; `⏺` in the menu-bar title. Name dialog when `meetingAskTitle` is on and the template has `{title}` (Enter accepts, empty = no name, Cancel = no session, focus returns to the previous app). MenuModel tests for item states.
- [ ] **Step 3:** At launch: delete leftover `meeting-*` dirs; if `active-meeting` exists, append the interrupted line to that note and remove the file. Quit during a session asks first (`applicationShouldTerminate`), then `interrupt()`. Notices reuse the dictation notice path. Stats row recorded on completion (table added in Task 13; until then a no-op).
- [ ] Commit `Shepit: meeting menu, status and name dialog`.

### Task 11: GATE — quality check (with the user)

**Spec:** §8 "Quality check", §10.

- [ ] Play a public multi-speaker recording (a podcast with 2–3 voices) through system audio for ~10 min. Report transcription quality and speaker attribution (share of entries with the right Person).
- [ ] One real Teams call with the user (and a Meet call if possible). Compare with the Teams transcript. Log the window titles during the call and fix the `MeetingTitle` patterns from them.
- [ ] Decide with the user from the results: merging very short consecutive chunks; re-running chunks detected as neither `uk` nor `en` with `language=uk`.
- [ ] **If attribution is poor, stop and report before building rename (Task 12).** Ledger entry with the numbers.

### Task 12: Rename speakers

**Files:** Modify `Shepit/MeetingUI.swift`, `MenuModel.swift`, `AppHost.swift`.
**Spec:** §5.7.

- [ ] **Rename speakers…** on the last note: for each label in order of first appearance, a prompt shows the label, the time and text of its first sentence-length entry and asks for a name (empty or unchanged = skip, Cancel = stop); then `Speakers.rename`, written via temp file + rename. **Rename speakers in another note…**: the same on a note from `NSOpenPanel` opened in `meetingsFolder`. Last note moved or deleted → notice. Logic is already tested in Task 6; here a MenuModel test for the new items.
- [ ] Commit `Shepit: rename speakers in meeting notes`.

### Task 13: Meeting statistics

**Files:** Modify `ShepitCore/Stats.swift`, `StatsDatabase.swift`, `Shepit/Settings/StatisticsSection.swift`; tests in `StatsTests.swift`, `StatsDatabaseTests.swift`.
**Spec:** `05-statistics.md` §1–2.

- [ ] `meetings` table (start, duration, words mine/call, speakers, engine, model, diarization seconds, failed chunks); insert and read back; existing databases get the table on open; `clear()` removes it too. Tile **Meetings · hours** with change vs the previous period; **Words per day** becomes stacked (dictation and meetings) — keep the phase 2 colours and apply the dataviz checks. Test: no text column exists (schema check).
- [ ] Commit `Shepit: meeting statistics`.

### Task 14: Settings → Meetings, docs, install

**Files:** Create `Shepit/Settings/MeetingsSection.swift`; modify `SettingsWindow.swift` (sidebar), `EnginesSection.swift` (drop "coming later"), `README.md`, `docs/manual-test-checklist.md`, `scripts/uninstall.sh`, `tests/install_test.sh`, `docs/future-ideas.md` (spec non-goals).
**Spec:** §5.6, §5.9, §7, `04-settings.md` Meetings row.

- [ ] Meetings section: the five keys with hints (like phase 2 sections), a live example of the file name from the current template (using `MeetingFileName`, with the validation error shown inline), diarization and VAD model state with Download / Delete (`ModelDownloads`), and an "Open meetings folder" button.
- [ ] README: requirements (macOS 14.2+), the one-time permission, menu items, settings with file-name examples, limitations §4.5, privacy (local folder by default, a synced folder uploads notes, audio deleted, tell participants), `--purge` deletes notes in the default folder only. Manual checklist: the §8 additions. `install_test.sh` stays green.
- [ ] Commit `Shepit: meetings settings and docs`.

### Task 15: GATE — manual checklist and phase review (with the user)

- [ ] Run the meeting part of `docs/manual-test-checklist.md` with the user: start/stop; note fills while open in Obsidian; name dialog (accept, empty, cancel); dictation during a meeting not in the transcript; output switch and Bluetooth disconnect mid-call; quit mid-call; a 1-hour call (no growing backlog, speaker detection < 2 min); copy; rename/merge in the last and an older note; missing models; permission denied.
- [ ] Phase-end review of the whole phase diff (reviewer subagent), fix, ledger "Phase 3: complete". Ask the user before merging into `main`.

---

## Open questions to raise when the task starts (not blockers)

- Task 0: whether the tap needs the app's own process object excluded explicitly or `isPrivate` is enough to keep Shepit's sounds out.
- Task 7: whether FluidAudio's offline mode needs its revision marker file in our folder, or a different folder layout.
- Task 8: whether keeping the AVCaptureSession open for an hour keeps MOMENTUM 4 in HFP (lower playback quality during the call). If so, tell the user; it's expected for any app that uses the headset mic during a call.
- Task 11: which browser the user runs Meet in, for the title patterns.
