# Shepit Phase 2 — Dictation Parity, Settings Window, Statistics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Shepit does everything today's Hammerspoon tool does (dictation, live draft, dictionary, add-word, history, menu), plus a Settings window and local statistics, so the user can switch over and retire the Lua tool.

**Architecture:** Same SwiftPM package as phase 1. Pure logic (dictionary, history, controller state machine, spectrum, overlay layout, statistics queries, model host scheduling) lives in `ShepitCore` and is ported test-for-test from the Lua modules in `src/dictation/`. Everything that touches the system (audio, hotkeys, paste, panel, menu, SwiftUI window, SQLite file) lives in the `Shepit` target behind small protocols, so the controller is tested without audio or UI. Engines from phase 1 are reached only through a `ModelHost` that shares instances and orders requests.

**Tech Stack:** as phase 1, plus AVAudioEngine, Carbon `RegisterEventHotKey`, `CGEvent`, AppKit `NSPanel`, SwiftUI hosted in `NSWindow`, Swift Charts, system SQLite (`import SQLite3`, no package), `SMAppService`, CryptoKit (SHA-256 for in-app downloads).

**Spec:** `docs/superpowers/specs/2026-10-18-native-app/` — `03-dictation.md`, `04-settings.md`, `05-statistics.md`, `01-app-build-signing.md` §4–6, `02-engines.md` §3–5. "As today" means `../2026-10-04-dictation-tool-design.md` (incl. §11 overlay addendum), the README, and the Lua source named in each task. Phase 1 results and the user's engine decision: `02-engines.md` §6–7.

**Branch:** continue on `shepit-phase1` or a new `shepit-phase2` cut from it (the user left phase 1 unmerged; ask before merging anything into `main`).

## Execution notes

- The previous phase ran out of API budget mid-task when every task went through implementer + reviewer subagents. Default here: **the controller implements inline**, one task at a time, and uses a reviewer subagent only for Tasks 4, 6, 10 and 15 (state machine, hotkeys/paste, statistics, downloads). Ask the user before switching to full subagent-driven execution.
- Ponytail style (level full): smallest complete change, a test for every non-trivial branch, no speculative options.
- **Tasks 9 and 17 are user gates**: stop and run them with the user.
- Port Lua tests case-for-case (same inputs, same expected outputs) unless a task says a case is dropped. Name Swift tests after the Lua `test("…")` strings so they can be matched.
- Ledger: `.superpowers/sdd/2026-10-24-shepit-phase2/progress.md`, same format as phase 1.

## Global Constraints

- The Lua tool keeps working untouched until Task 17; nothing in `src/`, `tests/*.lua` or the Hammerspoon loader changes before then.
- While the Lua tool holds the hotkey, Shepit must not steal it: registration failure → menu shows "Hotkey taken" and a ⚠ line, no crash, no retry loop (`01` §6).
- No audio or text leaves the Mac. The only network use is a model download the user clicked (Task 15). Engines never download on their own.
- `history.log` gets every result **before** paste; its format stays `YYYY-MM-DD HH:MM:SS<TAB>text` (`history.lua`).
- The statistics database never contains dictated text or audio (`05` §1). Only dictionary `replace` targets the user wrote may appear.
- Settings and dictionary files: only the changed key is written, via temp file + rename; invalid input never reaches disk; with a broken file the UI is read-only (`04` §1). Reuse `SettingsStore.update`.
- Defaults (user decision 2026-10-23): whisper.cpp `large-v3-turbo` for dictation, preview and meetings.
- Constants copied from Lua, not re-invented: `HOLD_MIN 0.3`, `MIN_SECONDS 0.5`, `TRANSCRIBE_TIMEOUT 120`, preview `INTERVAL 2`/`WINDOW 20`, paster `REFOCUS_DELAY 0.2`/`RESTORE_DELAY 1.0`/`KEYCODE_V 9`, add-word `MAX_WORDS 6`, overlay `PAD`/`MARGIN`/`METER_GAP`/`MIN_TEXT`/`MIN_BAR`/`FRAME_SECONDS`/`FFT_SAMPLES`, spectrum `PROBES`/`FLOOR_DB`/`CEIL_DB`.
- Success criterion (`03` §8): stop-to-paste for a 30 s dictation ≤ ~6 s and not slower than the Lua tool with the same model — measured in Task 9.

## Review Focus

1. **Text is never lost**: recognition fails twice → WAV in `failed/`, notice names it; paste without Accessibility → text stays on the clipboard and the notice says "copied" — pinned by controller tests in Task 4.
2. **Running next to the Lua tool**: hotkey already registered by Hammerspoon → "Hotkey taken", app stays usable from the menu — pinned by a Task 6 test with a fake registrar returning `eventHotKeyExistsErr`.
3. **A dictation is never delayed by the live draft**: preview requests queued behind a dictation are dropped or wait, never run first — pinned by `ModelHost` ordering tests in Task 3.
4. **The user's real `settings.json` and `dictionary.json`** load and round-trip through the Settings window without losing unknown keys — pinned by store tests in Tasks 1 and 11.
5. **No text in `stats.sqlite`** — pinned by a Task 10 test that dictates a known sentence through a fake pipeline and greps the database bytes for it.

---

## File Structure

```
app/Sources/ShepitCore/
  Dictionary.swift            buildPrompt, estimateTokens, applyReplacements (+fired terms), stripHallucinations, process
  DictionaryStore.swift       load / validate / last-good / update for dictionary.json
  History.swift               format, append, recent, label, prune, clear
  WAV.swift                   16-bit PCM WAV writer (failed audio)
  Spectrum.swift              band edges, bands (vDSP), smooth
  OverlayLayout.swift         formatElapsed, tailText, barHeight, color, recordingTitle, geometry, panelFrame
  Controller.swift            idle → recording → transcribing state machine, all effects via protocols
  ModelHost.swift             shared engine instances, load/unload, idle unload, priority queue
  KeyNames.swift              Hammerspoon key/mod names ⇄ Carbon key codes / modifiers
  AddWord.swift               prompt, parse
  Stats.swift                 StatsEvent types, time-saved, period buckets, queries over rows
  ModelDownloader.swift       manifest parse, per-file SHA-256, .part → folder, .complete (Swift port of fetch_dir)
app/Sources/Shepit/
  AudioRecorder.swift         AVAudioEngine capture → 16 kHz mono [Float], device by name, device-lost handling
  HotkeyCenter.swift          Carbon registration, press/release, cancel key while recording
  Paster.swift                refocus, clipboard save/restore, ⌘V via CGEvent, selection read for add-word
  OverlayPanel.swift          NSPanel + meter + draft text
  LivePreview.swift           every 2 s the last 20 s → preview engine
  MenuController.swift        status item, icon states, all menu items (replaces phase 1 AppDelegate menu)
  StatsDatabase.swift         SQLite file, schema, insert, fetch rows for a period, clear
  Settings/SettingsWindow.swift   NSWindow + NSHostingController, sidebar
  Settings/*Section.swift     General, Hotkeys, Engines, Dictation, Overlay, Dictionary, HistoryPrivacy, Statistics
  LaunchAtLogin.swift         SMAppService.mainApp
app/Resources/models/*.sha256 copied from scripts/models at build time (build-app.sh)
scripts/install.sh            rewritten at switchover (Task 17)
scripts/uninstall.sh          new
docs/manual-test-checklist.md native version
```

---

### Task 1: Dictionary and dictionary store

**Files:** Create `ShepitCore/Dictionary.swift`, `ShepitCore/DictionaryStore.swift`, `Tests/ShepitCoreTests/DictionaryTests.swift`, `DictionaryStoreTests.swift`.
**Port:** `src/dictation/dictionary.lua`, `utf8util.lua`, dictionary parts of `config.lua`; tests `tests/test_dictionary.lua` (21), `test_utf8util.lua` (9), dictionary-store cases of `test_config.lua`.
**Spec:** `03` §5.

**Interfaces:**
- `struct DictionaryFile: Equatable, Sendable { terms: [String]; replace: [String: String]; dropPhrases: [String] }`
- `enum DictionaryRules { static func estimateTokens(_:) -> Int; static func buildPrompt(style:terms:maxTokens:) -> String; static func applyReplacements(_ text: String, _ replace: [String: String]) -> (text: String, fired: [String]); static func stripHallucinations(_:extra:) -> String; static func process(_ text: String, _ dict: DictionaryFile) -> (text: String, fired: [String]) }` — `fired` = replace targets that matched (for statistics, Task 10).
- `final class DictionaryStore` mirroring `SettingsStore` (`load() -> Bool`, `errors`, `update`).

- [ ] **Step 1:** Port the tests; add `firedTermsListEveryMatch` (every match appends its replacement to `fired`, in order). Run `swift test --filter Dictionary` → FAIL.
- [ ] **Step 2:** Implement. Case-insensitive whole-word matching with Swift's Unicode lowercasing; utf8util cases become tests of the same behaviour, not a port of byte helpers that Swift doesn't need (drop those cases with a note in the ledger).
- [ ] **Step 3:** Run → PASS. `examples/dictionary.json` and the user's real file (read-only, from `Paths.dictionaryFile` if present) load with no errors.
- [ ] **Step 4:** Commit `Shepit: dictionary rules and dictionary.json store`.

### Task 2: History, failed audio, WAV writer

**Files:** Create `ShepitCore/History.swift`, `ShepitCore/WAV.swift`, tests `HistoryTests.swift`, `WAVTests.swift`.
**Port:** `history.lua` (11 tests), `wav.lua` (11 tests; keep writer + header cases, drop reader cases that only served sox files), failed-audio retention from `platform.lua` (`keepFailed`, `cleanupFailed`).
**Spec:** `03` §3, §6.

**Interfaces:** `enum History { format, append(_:to:at:) throws, recent(_:count:) -> [Entry], label(_:today:maxChars:), prune(_:before:), clear(_:) }`; `enum FailedAudio { static func keep(_ samples: [Float], in dir: URL, now: Date) throws -> URL; static func cleanup(_ dir: URL, olderThanHours: Int, now: Date) }`; `enum WAV { static func data(samples: [Float], sampleRate: Int) -> Data }`.

- [ ] Port tests → FAIL → implement → PASS. Add `wavRoundTripsThroughAudioFile`: `WAV.data` written to a temp file and read back with phase 1 `AudioFile.load` gives the same length.
- [ ] Commit `Shepit: history log and failed-audio retention`.

### Task 3: Model host (shared engines, priority, idle unload)

**Files:** Create `ShepitCore/ModelHost.swift`, `Tests/ShepitCoreTests/ModelHostTests.swift`.
**Spec:** `02` §3–4.

**Interfaces:**
- `actor ModelHost { init(factory: @Sendable (EngineChoice) throws -> any SpeechEngine, clock: any Clock<Duration>); func setChoices(_ engines: [EngineTask: EngineChoice]) async; func preload(_ tasks: [EngineTask]) async; func transcribe(_ task: EngineTask, _ request: TranscriptionRequest) async throws -> Transcript; func setIdleUnload(minutes: Int); var loadState: [EngineChoice: LoadState] { get } }`
- One engine instance per distinct `EngineChoice`; one request at a time per instance; `.dictation` requests jump ahead of queued `.preview`/`.meetings`; a `.preview` request that is still queued when a newer `.preview` arrives is cancelled with `CancellationError`.
- `setChoices` loads newly chosen engines in the background and unloads ones no task uses.

- [ ] **Step 1: Tests with a fake engine** (records call order, controllable delay): `sameChoiceSharesInstance`, `dictationRunsBeforeQueuedPreview`, `newerPreviewCancelsQueued`, `differentModelsRunInParallel`, `changingChoiceUnloadsUnused`, `idleUnloadAfterMinutes` (test clock), `loadsAgainAfterIdleUnload`. → FAIL.
- [ ] **Step 2:** Implement. → PASS. Commit `Shepit: model host shares engines and puts dictation first`.

### Task 4: Controller state machine (review)

**Files:** Create `ShepitCore/Controller.swift`, `Tests/ShepitCoreTests/ControllerTests.swift`.
**Port:** `controller.lua` + `tests/test_controller.lua` (26 cases), retry from `transcriber.lua` (`test_transcriber.lua` retry cases).
**Spec:** `03` §1, §3.

**Interfaces:** protocols in `Controller.swift`, implemented by the app in later tasks:
`Recording { start() throws; stop() -> [Float]; cancel() }`, `Transcribing { transcribe(_ samples: [Float], prompt: String) async throws -> Transcript }` (the app adapts `ModelHost`), `Pasting { paste(_ text: String, into app: AppRef?) async -> PasteOutcome /* .pasted | .copied */ }`, `ControllerEffects { setState, sound(_:), notify(_:), overlay(_ event:), frontApp() -> AppRef?, historyAppend(_:), keepFailed(_:) -> URL?, stats(_ event: DictationEvent) }`, plus an injected clock/timer.
`DictationEvent` carries exactly the `05` §1 per-dictation fields (outcome, audio s, wait s, words, characters, engine, model, language requested/detected, app, replacement count, fired terms, preview count).

- [ ] **Step 1:** Port the 26 controller tests with fakes. Add: `retriesOnceThenKeepsFailedAudio`, `historyWrittenBeforePaste` (effect order), `noAccessibilityCopiesAndSaysSo`, `modelLoadingWaitsUpTo60s`, `statsEventPerOutcome` (one event for each of pasted/copied/empty/cancelled/discarded/failed, no text field exists on the type). → FAIL.
- [ ] **Step 2:** Implement → PASS. Reviewer subagent on this task.
- [ ] **Step 3:** Commit `Shepit: dictation controller state machine`.

### Task 5: Audio recorder and spectrum

**Files:** Create `ShepitCore/Spectrum.swift`, `Shepit/AudioRecorder.swift`, tests `SpectrumTests.swift`.
**Port:** `spectrum.lua` (8 tests), microphone choice from `recorder.lua`/`platform.lua`.
**Spec:** `03` §2, §4 (meter).

- [ ] **Step 1:** Port spectrum tests (same band edges and levels for the same synthetic sine input); implement with vDSP. → PASS.
- [ ] **Step 2:** `AudioRecorder: Recording` with `AVAudioEngine`: input tap → `AVAudioConverter` → 16 kHz mono Float32 appended to an in-memory buffer; `devices() -> [String]`; `select(name:)` falls back to the default and reports `usedFallback`; route-change / device-lost → continue on default if possible, else stop and keep what was recorded. Live level callback for the meter. No temp WAV.
- [ ] **Step 3:** Manual check (no unit test for hardware): record 5 s from the built-in mic via a temporary `Shepit record-test` subcommand that prints duration and RMS; remove the subcommand before committing, or keep it only if Task 9 needs it.
- [ ] **Step 4:** Commit `Shepit: in-memory recording and spectrum meter`.

### Task 6: Hotkeys and paste (review)

**Files:** Create `ShepitCore/KeyNames.swift`, `Shepit/HotkeyCenter.swift`, `Shepit/Paster.swift`, tests `KeyNamesTests.swift`, `HotkeyCenterTests.swift`.
**Port:** key names as Hammerspoon used them (`config.lua` hotkey validation), `paster.lua`, `selection.lua`.
**Spec:** `03` §1, §3, §5; `01` §6.

- [ ] **Step 1:** `KeyNames` tests: every key name the settings validator accepts maps to a Carbon key code and back; `{"mods":["alt"],"key":"space"}` → `kVK_Space` + `optionKey`.
- [ ] **Step 2:** `HotkeyCenter` behind a `HotkeyRegistrar` protocol (real one wraps `RegisterEventHotKey`/`UnregisterEventHotKey`, press and release via `kEventHotKeyPressed`/`Released`). Tests with a fake: `takenHotkeyReportsTaken` (registrar returns `eventHotKeyExistsErr` → state `.taken`, menu text "Hotkey taken"), `cancelKeyOnlyWhileRecording`, `reRegistersOnSettingsChange`. **Verify** that `RegisterEventHotKey` really returns `eventHotKeyExistsErr` while Hammerspoon holds ⌥Space; if it doesn't, detect the clash another way and record the finding in the ledger.
- [ ] **Step 3:** `Paster: Pasting` — refocus original app (`refocusOriginalApp`), save all pasteboard items, set text, post ⌘V with keycode 9 via `CGEvent`, restore after `RESTORE_DELAY` (`restoreClipboard`). Without Accessibility (`AXIsProcessTrusted() == false`) → set clipboard only and return `.copied`. Selection read for add-word: temporary ⌘C, read, restore.
- [ ] **Step 4:** Reviewer subagent. Commit `Shepit: global hotkeys and paste`.

### Task 7: Overlay panel and live draft

**Files:** Create `ShepitCore/OverlayLayout.swift`, `Shepit/OverlayPanel.swift`, `Shepit/LivePreview.swift`, tests `OverlayLayoutTests.swift`, `LivePreviewTests.swift`.
**Port:** `overlay.lua` (11 tests: layout functions), `preview.lua` (8 tests).
**Spec:** `03` §4; `../2026-10-04-dictation-tool-design.md` §11.

- [ ] **Step 1:** Port layout and preview tests (preview against a fake transcriber + test clock: one request in flight, late results dropped, nothing below 0.5 s, stops on stop). → FAIL → implement → PASS.
- [ ] **Step 2:** `OverlayPanel`: non-activating `NSPanel`, ignores mouse, `.canJoinAllSpaces` + `.fullScreenAuxiliary`, on the screen of the focused window, every `overlayStyle` key honoured. With `overlay` false → small transient notices instead. With `livePreview` false or the preview model missing → status + meter only.
- [ ] **Step 3:** Commit `Shepit: overlay panel and live draft`.

### Task 8: Menu, add-word, app wiring

**Files:** Create `Shepit/MenuController.swift`, `ShepitCore/AddWord.swift`, tests `AddWordTests.swift`, `MenuModelTests.swift`; modify `AppDelegate.swift` (wires settings/dictionary stores, ModelHost, Controller, recorder, hotkeys, paster, overlay, menu).
**Port:** `menubar.lua` (18 tests: title, statusLine, item list as data), `addword.lua` (7 tests), `init.lua` wiring.
**Spec:** `03` §5–7.

- [ ] **Step 1:** Port menu tests against a pure `MenuModel` (items as data: title, enabled, checked, submenu) — the `NSMenu` is built from it. Icon states 🎙/🔴/⏳/🎙⚠ (or distinct template SF Symbols). Items per the `03` §7 table: Engine ▸ (downloaded pairs for dictation), Mode ▸, Language ▸, Microphone ▸, Recent ▸, Open history, Clear history… (asks; also clears failed audio), Edit dictionary…, Settings… (⌘,), Statistics, Reload models, Quit.
- [ ] **Step 2:** Port add-word tests; dialog with today's Ukrainian texts.
- [ ] **Step 3:** Wire everything in `AppDelegate`; launch loads dictation + preview models (`ModelHost.preload`); settings/dictionary changes apply live (existing watcher + menu-open reload).
- [ ] **Step 4:** `make test` green; `scripts/build-app.sh`; quick self-check with the Lua tool **still running** → Shepit shows "Hotkey taken" and does not interfere.
- [ ] **Step 5:** Commit `Shepit: menu, add-word and dictation wiring`.

### Task 9: GATE — dictation parity with the user

- [ ] Update `docs/manual-test-checklist.md` for the native app (`03` §8 additions: permissions survive a rebuild; no Accessibility → copied + notice; switching engines while idle and while recording; hotkey taken while the Lua tool runs).
- [ ] With the user: they quit dictation in the 🎙 menu, start Shepit, and walk the checklist. Measure stop-to-paste on a 30 s dictation with whisper.cpp turbo in Shepit and in the Lua tool (same model): Shepit ≤ ~6 s and not slower.
- [ ] Fix what the user finds; record results in the ledger. **Do not switch over yet** — Lua stays the installed tool until Task 17.

### Task 10: Statistics store (review)

**Files:** Create `ShepitCore/Stats.swift`, `Shepit/StatsDatabase.swift`, tests `StatsTests.swift`, `StatsDatabaseTests.swift`.
**Spec:** `05` §1–2.

- [ ] **Step 1: Tests**: `timeSavedFormula` (words ÷ wpm − (audio + wait), floored at 0 per dictation, only pasted/copied), `bucketsByPeriod` (hour for Day, day for Week/Month, month for Year/All, in the stored local time zone), `medianWaitPerEngine`, `medianWaitPer10sAudio`, `topAppsWithOther` (top 8 + Other), `heatmapHourWeekday`, `qualityShares`, `previousPeriodDelta`, `collectStatsFalseRecordsNothing`, `clearDeletesDatabase`, `noTextInDatabase` (Review Focus 5). → FAIL.
- [ ] **Step 2:** `StatsDatabase` on system SQLite (`import SQLite3`): tables `dictations`, `model_events` (and `meetings` created empty for phase 3), `schema_version`. Queries return rows; aggregation stays in pure `Stats` functions (tested without SQLite). Controller `stats` effect → insert.
- [ ] **Step 3:** Reviewer subagent. Commit `Shepit: local usage statistics store`.

### Task 11: Settings window — shell and simple sections

**Files:** Create `Shepit/Settings/SettingsWindow.swift`, `GeneralSection.swift`, `HotkeysSection.swift`, `DictationSection.swift`, `HistoryPrivacySection.swift`; tests `SettingsBindingTests.swift`.
**Spec:** `04` §1, §3.

- [ ] **Step 1: Tests** for the binding layer (pure): a control change calls `SettingsStore.update(key, value)` with exactly that key; broken file → every binding read-only and the error list exposed; external file edit → bindings refresh; `serverPort` never shown; unknown keys survive an update (round-trip the user's real file into a temp copy).
- [ ] **Step 2:** SwiftUI sidebar window in an `NSWindow` (accessory app; opened by Settings… ⌘, or by launching the app again). General (launch at login via `SMAppService.mainApp`, sounds, language, Open settings file, Open data folder), Hotkeys (shortcut recorder, conflicts inline), Dictation (microphone list, style prompt, refocus, restore clipboard, max length), History & Privacy (save history, days, recent items, failed-audio hours, Open/Clear history, collect statistics, Clear statistics…). One-line hints = README wording. Steppers/sliders clamp to allowed ranges.
- [ ] **Step 3:** Commit `Shepit: Settings window with general, hotkeys, dictation and privacy`.

### Task 12: Settings — Overlay and Dictionary sections

**Files:** Create `OverlaySection.swift`, `DictionarySection.swift`; tests extend `SettingsBindingTests.swift`.
- [ ] Overlay: show panel, live draft, every `overlayStyle` key (position picker, sliders, color pickers, text fields) + **Preview** button that shows the panel with sample text.
- [ ] Dictionary: terms (ordered, drag to reorder, add/remove), replace rules (two-column table), drop phrases — writes via `DictionaryStore.update` only on valid input. Test: reorder writes the new order; an invalid rule is rejected and the file is unchanged.
- [ ] Commit `Shepit: Settings overlay and dictionary sections`.

### Task 13: Settings — Statistics screen

**Files:** Create `StatisticsSection.swift`.
**Spec:** `05` §2.
- [ ] Period picker (Day, Week, Month, Year, All) driving tiles (Dictations, Words, Time saved with the formula note and a link to typing speed, Meetings "—") and Swift Charts (words per bucket, speed by engine, pasted into, heatmap, quality signals). Empty state text exactly "No dictations in this period yet." All numbers come from Task 10's pure functions; this task adds no new aggregation logic.
- [ ] Commit `Shepit: statistics screen`.

### Task 14: Settings — Engines & Models (without downloads)

**Files:** Create `EnginesSection.swift`; tests extend `SettingsBindingTests.swift`.
**Spec:** `04` §3 (Engines & Models), `02` §3–5.
- [ ] Three task pickers (engine + model) writing `engines` (and dropping `model`/`previewModel`, as `SettingsStore.update` already does); a note when the language can't be forced (`EngineCapabilities.check`); `idleUnloadMinutes`. Changing a choice calls `ModelHost.setChoices` (loads in background, unloads unused). Model list shows each catalog model's state (downloaded / missing / loading) and size on disk.
- [ ] Commit `Shepit: engine choice per task in Settings`.

### Task 15: In-app model downloads (review)

**Files:** Create `ShepitCore/ModelDownloader.swift`, tests `ModelDownloaderTests.swift`; modify `EnginesSection.swift`, `scripts/build-app.sh` (copy `scripts/models/*.sha256` into `Contents/Resources/models/`).
**Spec:** `02` §5; anti-goal "network only when the user asks".
- [ ] **Step 1: Tests** (URLProtocol stub, no network): same behaviour as `fetch_dir` — malformed or duplicate manifest row fails before any download; checksum mismatch deletes `.part`; success renames `.part` → folder and writes `.complete`; existing `.complete` re-verifies; cancel leaves no folder. Single-file ggml models use the pinned SHA from `download-models.sh` (move those three hashes into a manifest file both use).
- [ ] **Step 2:** Download / Delete buttons with progress. Apple: "Download" calls `AssetInventory.assetInstallationRequest` (same as `Shepit apple-assets --install`). Nothing downloads without a click.
- [ ] **Step 3:** Reviewer subagent. Commit `Shepit: download and delete models from Settings`.

### Task 16: Install and uninstall scripts

**Files:** Rewrite `scripts/install.sh` (behind `--native` until Task 17), create `scripts/uninstall.sh`, update `tests/install_test.sh`.
**Spec:** `01` §5.
- [ ] `install.sh --native`: checks Xcode/CLT and cmake, `build-app.sh`, downloads **`large-v3-turbo` by default** (`02-engines.md` §6 decision) plus VAD, creates `settings.json`/`dictionary.json` from `examples/` only if absent, opens the app. Safe to re-run. `uninstall.sh`: quits the app, removes it and its login item; `--purge` also deletes `~/.config/dictation` and `~/.local/share/dictation`. `tests/install_test.sh` covers both with stubs and stays green; the Lua install path is unchanged.
- [ ] Commit `Shepit: native install and uninstall scripts`.

### Task 17: GATE — switchover (with the user)

- [ ] Only when the user says parity is reached and they want to switch.
- [ ] `install.sh` becomes the native installer by default and removes the Hammerspoon loader block (Hammerspoon stays installed). README rewritten for the native app. Remove `scripts/build-whisper.sh` and `patches/whisper-server-auth.patch` (`01` §4).
- [ ] The Lua code (`src/`, `tests/*.lua`, Lua `Makefile` targets) is **not** deleted here — that is a separate commit after the user has used Shepit for a while and says so (`01` §6).
- [ ] Phase-end review of the whole phase diff, fix, ledger "Phase 2: complete", then plan phase 3 (meetings).

---

## Open questions to raise when the task starts (not blockers)

- Task 6: whether Carbon reports the clash with Hammerspoon's hotkey (verify step).
- Task 11: shortcut recorder — hand-written `NSView` key capture vs. a package; default is hand-written (no new dependency).
- Task 13: the approved mockup isn't in the repo; ask the user to share it or accept the builder's layout.
