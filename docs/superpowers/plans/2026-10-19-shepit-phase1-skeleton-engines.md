# Shepit Phase 1 — Skeleton, Signing, Engines Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A signed menu-bar app `Shepit.app` whose permissions survive rebuilds, that loads the existing `settings.json`, runs four speech engines behind one interface, and benchmarks them on the user's clips.

**Architecture:** One SwiftPM package in `app/` with a pure-logic library (`ShepitCore`: settings, engine protocol, model catalog), an engines library (`ShepitEngines`: four adapters + audio loading), and one executable (`Shepit`) that is the menu-bar app or, with `bench` as first argument, a CLI. Shell scripts build whisper.cpp into an xcframework, assemble and sign the `.app`, and download pinned models.

**Tech Stack:** Swift 6.3 / Xcode 26.6, SwiftPM, AppKit, Swift Testing, WhisperKit v1.1.1, FluidAudio v0.17.7, whisper.cpp v1.9.4 (commit `927cfce34f31707e17f2bff35c349632fb9e2c3a`), Apple Speech (macOS 26), bash, Python 3.

**Spec:** `docs/superpowers/specs/2026-10-18-native-app/` (all files; this plan is phase 1 of `00-overview.md` §4). Executors read the spec files named in each task.

## Execution notes (from the user)

- Implementer and reviewer subagents run on the session's subagent model, **gpt-6-luna** (already `CLAUDE_CODE_SUBAGENT_MODEL`; pass `model: "sonnet"`, which maps to it).
- Implementers follow the **Ponytail** style (`ponytail` skill, level full): smallest complete change, a test for every non-trivial branch, no speculative options.
- Each task's review uses the `ponytail-review` skill's checklist.
- At the end of the phase a **thermo-nuclear code quality review** runs over the whole phase diff (the reviewer gets `~/.claude/skills/thermo-nuclear-code-quality-review/SKILL.md` as instructions; the skill can't be model-invoked), then fixes.
- **Task 2 and Task 9 are user gates**: stop and talk to the user.

## Global Constraints

- App name `Shepit`, bundle `Shepit.app`, bundle identifier `dev.shepit.Shepit` (never changes once Task 2 passes).
- macOS deployment target **14.2**, Apple Silicon only; Apple engine behind `if #available(macOS 26, *)`.
- Data folders unchanged: `~/.config/dictation/`, `~/.local/share/dictation/` (models in `…/models/`).
- Every dependency pinned to an exact version or commit; `app/Package.resolved` committed.
- Model downloads only from `scripts/download-models.sh` (user-run), pinned revision, every file SHA-256-verified.
- No audio or text leaves the Mac; engines must never download on their own (WhisperKit `download: false`, FluidAudio local-directory loading).
- The Lua tool keeps working untouched during this phase; nothing in `src/`, `tests/*.lua` or the Hammerspoon flow changes.
- Defaults stay today's until the user decides after Task 9: dictation `whispercpp/large-v3`, preview `whispercpp/large-v3-turbo`, meetings `whispercpp/large-v3`.
- whisper.cpp settings as today: temperature 0, VAD on with `ggml-silero-v6.2.0.bin`, threads = performance-core count.

## Review Focus

1. **The user's existing `settings.json`** (has `model`, `previewModel`, `serverPort`, `overlayStyle`, unknown keys) must load with no errors and map to engine choices — pinned by `realUserFileLoads` in Task 3.
2. **A language the engine can't be forced to** (Apple without `uk`, Parakeet with `uk`) must give `EngineError.languageNotSupported` or a clear note, never a silent switch — pinned by `capabilityCheck*` tests in Task 4.
3. **A half-downloaded model folder** must read as "not downloaded", not crash at load — pinned by `partialDownloadIsMissing` in Task 4.
4. **WAV files that aren't 16 kHz mono** (44.1 kHz stereo from another recorder) must be converted with the right duration — pinned by `loadsStereo44k` in Task 4.
5. **Silence or a very short clip** must return empty or short text without throwing — pinned by each engine's `silenceDoesNotThrow` smoke test (Tasks 5–8).

---

## File Structure

```
app/Package.swift                       products, deps (pinned), targets
app/Package.resolved                    committed
app/Resources/Info.plist                bundle metadata, usage descriptions
app/Vendor/whisper.xcframework          built by scripts/build-whisper-lib.sh (gitignored)
app/Sources/ShepitCore/
  Paths.swift                           all filesystem locations (honours DICTATION_HOME)
  Settings.swift                        Settings struct + defaults
  SettingsValidation.swift              validate(raw:) -> Result, messages as in config.lua
  SettingsStore.swift                   load / last-good / update(key:value:) atomic write
  Engine.swift                          SpeechEngine protocol, request/transcript types, errors
  ModelCatalog.swift                    engines × models, folders, isDownloaded
app/Sources/ShepitEngines/
  AudioFile.swift                       WAV/any file -> 16 kHz mono [Float]
  EngineFactory.swift                   EngineChoice -> SpeechEngine
  WhisperCppEngine.swift
  WhisperKitEngine.swift
  ParakeetEngine.swift
  AppleSpeechEngine.swift
app/Sources/Shepit/
  main.swift                            "bench" -> Bench.run, else NSApplication
  AppDelegate.swift                     status item + menu
  Permissions.swift                     Accessibility / Microphone state + requests
  Bench.swift                           CLI
app/Tests/ShepitCoreTests/              SettingsTests, StoreTests, EngineTypesTests, CatalogTests
app/Tests/ShepitEnginesTests/           AudioFileTests, <Engine>SmokeTests, Fixtures/hello.wav
scripts/build-whisper-lib.sh            whisper.cpp -> app/Vendor/whisper.xcframework
scripts/signing.sh                      choose_identity / ensure_self_signed (sourced)
scripts/build-app.sh                    build, assemble, sign, install to ~/Applications
scripts/models/*.sha256                 pinned model manifests
scripts/pin-model.sh                    maintainer tool: writes a manifest for a HF repo@rev/dir
tests/signing_test.sh                   choose_identity with stubbed `security`
tools/accuracy/evaluate.py              + --engines via Shepit bench
```

---

### Task 1: App skeleton, build script, self-signed signing

**Files:**
- Create: `app/Package.swift`, `app/Resources/Info.plist`, `app/Sources/Shepit/{main,AppDelegate,Permissions}.swift`, `app/Sources/ShepitCore/Paths.swift`, `app/Tests/ShepitCoreTests/PathsTests.swift`, `scripts/signing.sh`, `scripts/build-app.sh`, `tests/signing_test.sh`
- Modify: `.gitignore` (add `app/.build/`, `app/Vendor/`, `build/`), `Makefile` (`test` also runs `swift test --package-path app` and `bash tests/signing_test.sh`), `README.md` (new section "Shepit native app (preview)": requirements, `scripts/build-app.sh`, the one-time password prompt, `codesign -dv ~/Applications/Shepit.app`, `DICTATION_SIGN_IDENTITY`, "if permissions were lost: remove Shepit from the Accessibility list and add it again")

Spec: `01-app-build-signing.md` §1–4.

**Interfaces:**
- Produces: `Paths` (enum, static): `home`, `configDir`, `settingsFile`, `dictionaryFile`, `dataDir`, `modelsDir`, `historyFile`, `failedDir` — all `URL`, `home` = `$DICTATION_HOME` or `$HOME`.
- Produces: `scripts/signing.sh` functions `choose_identity` (prints the identity to use) and `ensure_self_signed` (creates `Shepit Local Signing` if missing).
- Produces: `scripts/build-app.sh` → `~/Applications/Shepit.app`, signed. Later tasks only add targets/deps to `Package.swift`.

- [ ] **Step 1: Write failing tests**

`PathsTests.dictationHomeOverrides`: with `DICTATION_HOME=/tmp/x` (inject via an `environment: [String:String]` parameter on a `Paths.resolve(environment:)` helper), `settingsFile.path == "/tmp/x/.config/dictation/settings.json"` and `modelsDir.path == "/tmp/x/.local/share/dictation/models"`.

`tests/signing_test.sh` (puts a fake `security` script first on `PATH` that prints canned `find-identity -v -p codesigning` output):
- `DICTATION_SIGN_IDENTITY="Foo"` → `choose_identity` prints `Foo`.
- canned output containing `"Apple Development: a@b.c (TEAM123)"` → prints `Apple Development: a@b.c (TEAM123)`.
- canned output with only `"Shepit Local Signing"` → prints `Shepit Local Signing`.
- canned output with no identities → exit status 3 (caller then runs `ensure_self_signed`).

- [ ] **Step 2: Run and see them fail** — `swift test --package-path app` (FAIL: no package) and `bash tests/signing_test.sh` (FAIL: no signing.sh).

- [ ] **Step 3: Implement**

`Package.swift`: platforms `.macOS("14.2")`; targets `ShepitCore` (library), `Shepit` (executable, depends on ShepitCore), `ShepitCoreTests`. Swift 6 language mode.

`Info.plist`: `CFBundleIdentifier dev.shepit.Shepit`, `CFBundleName/CFBundleExecutable Shepit`, `CFBundlePackageType APPL`, `LSUIElement true`, `LSMinimumSystemVersion 14.2`, `NSMicrophoneUsageDescription "Shepit records your voice to turn it into text on this Mac."`, `NSSpeechRecognitionUsageDescription "Shepit can use Apple's on-device speech recognition."`, `CFBundleShortVersionString 0.1.0`.

App (`main.swift`, `AppDelegate.swift`): status item with SF Symbol `waveform`; menu:
`Shepit 0.1.0 (preview)` (disabled) · `Accessibility: granted|not granted` (click → `AXIsProcessTrustedWithOptions` prompt + open the pane) · `Microphone: granted|not granted|denied` (click → `AVCaptureDevice.requestAccess(for: .audio)`, or open the pane if denied) · separator · `Quit`. The menu re-reads both states each time it opens (`menuNeedsUpdate`).

`signing.sh`:
- `choose_identity`: `$DICTATION_SIGN_IDENTITY` if set; else first `"Apple Development: …"` from `security find-identity -v -p codesigning`; else `Shepit Local Signing` if listed; else return 3.
- `ensure_self_signed`: print a notice that macOS will ask for the login password once; with `/usr/bin/openssl` (LibreSSL — its PKCS#12 output imports into the Keychain; OpenSSL 3 needs `-legacy`) create a key + self-signed cert, CN `Shepit Local Signing`, 3650 days, `extendedKeyUsage=critical,codeSigning`, `keyUsage=critical,digitalSignature`, `basicConstraints=critical,CA:false`; `security import` the p12 into the login keychain with `-T /usr/bin/codesign`; `security add-trusted-cert -p codeSign -k ~/Library/Keychains/login.keychain-db cert.pem`; delete the temp files.

`build-app.sh`: `swift build -c release --package-path app`; assemble `build/Shepit.app/Contents/{MacOS/Shepit,Info.plist}`; identity = `choose_identity` or (`ensure_self_signed` then `choose_identity`); `codesign --force --sign "$id" --identifier dev.shepit.Shepit build/Shepit.app`; `codesign --verify --strict build/Shepit.app`; print the identity; install to `~/Applications/Shepit.app` by copying to `Shepit.app.new` and renaming over (quit a running Shepit first with `osascript -e 'quit app id "dev.shepit.Shepit"'`, ignoring errors). No stamp skip yet — rebuild is cheap until whisper.cpp arrives (Task 5 adds its own stamp).

- [ ] **Step 4: Run tests** — both pass. Then `scripts/build-app.sh` succeeds and prints the identity; `codesign -dv ~/Applications/Shepit.app 2>&1 | grep Identifier=dev.shepit.Shepit`; `open ~/Applications/Shepit.app` shows the menu-bar icon.

- [ ] **Step 5: Check whether Command Line Tools suffice** — `DEVELOPER_DIR=/Library/Developer/CommandLineTools swift build --package-path app` (if that dir exists). Record the result in the README section ("Xcode required" or "Command Line Tools are enough").

- [ ] **Step 6: Commit** — `git commit -m "Add Shepit app skeleton, build script and self-signed code signing"`

---

### Task 2: GATE — permissions survive rebuilds (with the user)

Spec: `01-app-build-signing.md` §3 "Phase 1 gate". **Not a subagent task** — the controller does it with the user.

- [ ] **Step 1:** User opens `~/Applications/Shepit.app`, clicks both permission items, grants Accessibility and Microphone. Menu shows both "granted".
- [ ] **Step 2:** Change a visible string (e.g. version `0.1.1` in Info.plist), run `scripts/build-app.sh`, reopen. Both still "granted"?
- [ ] **Step 3:** Repeat once more (`0.1.2`). Both still "granted"?
- [ ] **Step 4:** Revert the version to `0.1.0`, commit nothing else.
- [ ] **Step 5: Decide.** Both survived twice → continue to Task 3. Otherwise **stop**: report to the user what was lost, `codesign -d -r- ~/Applications/Shepit.app` output, and options (Apple Development identity via Xcode; keeping one bundle path). Do not continue without the user.

---

### Task 3: Settings — load, validate, last-good, update

**Files:**
- Create: `app/Sources/ShepitCore/{Settings,SettingsValidation,SettingsStore}.swift`, `app/Tests/ShepitCoreTests/{SettingsTests,StoreTests}.swift`
- Modify: `app/Sources/Shepit/AppDelegate.swift` (load settings at launch, watch the file, show `⚠ <first error>` menu line with the full list as tooltip), `examples/settings.json` (add `engines`, `launchAtLogin`, `typingSpeedWpm`, `collectStats` with defaults — the Lua tool ignores unknown keys)

Spec: `04-settings.md` §1–2. Port behaviour from `src/dictation/config.lua` and its tests `tests/test_config.lua` (every `test(...)` there except the dictionary-store and `jsonFileIo` cases, which map to Store tests below; drop `serverPort leaves room…`).

**Interfaces:**
- Consumes: `Paths.settingsFile`.
- Produces:
  - `enum EngineID: String, CaseIterable, Sendable { case whisperkit, whispercpp, parakeet, apple }`
  - `struct EngineChoice: Equatable, Hashable, Sendable { var engine: EngineID; var model: String }` (`model == ""` for apple)
  - `enum EngineTask: String, CaseIterable, Sendable { case dictation, preview, meetings }` (not `Task`, which clashes with Swift concurrency).
  - `struct Settings: Equatable, Sendable` — one stored property per key in `config.lua` `DEFAULT_SETTINGS` (same names; `hotkey`/`addWordHotkey` as `Hotkey { mods: [String]; key: String }`, `overlayStyle` as `OverlayStyle` with all 15 fields) plus `engines: [EngineTask: EngineChoice]`, `launchAtLogin = true`, `typingSpeedWpm = 40`, `collectStats = true`. `static let defaults`.
  - `func validateSettings(_ raw: [String: Any], catalog: ModelCatalog.Type = ModelCatalog.self) -> (Settings?, [String])` — errors sorted, messages formatted exactly like `config.lua` (`settings.json: "mode" must be one of: toggle, hold`).
  - `final class SettingsStore { init(file: URL); private(set) var settings: Settings; private(set) var errors: [String]; func load() -> Bool; func update(_ key: String, _ value: Any) throws }` — `update` refuses while the file is broken, writes only the raw keys + changed key via temp file + rename.
- Note: Task 3 needs `ModelCatalog.models(for:)` for validating `engines`; create `ModelCatalog.swift` here with just `static func models(for: EngineID) -> [String]` — whisperkit/whispercpp: `["large-v3", "large-v3-turbo"]`, parakeet: `["parakeet-tdt-0.6b-v3"]`, apple: `[""]`. Task 4 extends it.

- [ ] **Step 1: Write failing tests** — the ported `test_config.lua` cases (same inputs and expected messages), plus:
  - `enginesDefaultFromLegacyKeys`: raw `{"model":"large-v3-turbo","previewModel":"large-v3"}` → `engines[.dictation] == EngineChoice(.whispercpp,"large-v3-turbo")`, `engines[.preview] == (.whispercpp,"large-v3")`, `engines[.meetings] == (.whispercpp,"large-v3")`.
  - `enginesKeyWinsOverLegacy`: raw with both `model` and `engines.dictation = {whisperkit, large-v3}` → dictation is whisperkit.
  - `enginesValidation`: `{"engines":{"dictation":{"engine":"foo"}}}` → error `settings.json: "engines.dictation.engine" must be one of: whisperkit, whispercpp, parakeet, apple`; `{"engine":"parakeet","model":"large-v3"}` → `settings.json: "engines.dictation.model" must be one of: parakeet-tdt-0.6b-v3`; `{"engine":"apple"}` (no model) is valid; unknown task name `"foo"` → `settings.json: "engines" has unknown task "foo"; allowed: dictation, preview, meetings`.
  - `newKeysValidated`: `typingSpeedWpm` 9 and 201 rejected (`must be a whole number from 10 to 200`), `launchAtLogin`/`collectStats` must be boolean.
  - `serverPortIgnored`: `{"serverPort": 99999}` → no error (accepted and ignored).
  - `realUserFileLoads`: the exact content of `examples/settings.json` (read from the repo via `#filePath`) plus `"foo": 1` → no errors, `settings.overlayStyle.bars == 10`.
  - Store: `updateRemovesLegacyWhenWritingEngines` — `update("engines", …)` on a file with `model` writes `engines` and removes `model`/`previewModel` from the file.

- [ ] **Step 2: Run** — `swift test --package-path app --filter Settings` → FAIL.
- [ ] **Step 3: Implement** with `JSONSerialization` into `[String: Any]` (keeps unknown keys for writes) and per-key validators as in `config.lua`. JSON booleans vs numbers: check `CFGetTypeID(v as CFTypeRef) == CFBooleanGetTypeID()` so `1` is not a boolean. File watching in the app: `DispatchSource.makeFileSystemObjectSource` on the config dir, reload on change.
- [ ] **Step 4: Run** — all Settings/Store tests pass; `scripts/build-app.sh`, open the app, break `settings.json` by hand → `⚠` line appears; fix it → line disappears.
- [ ] **Step 5: Commit** — `git commit -m "Shepit: load and validate settings.json, engine choices per task"`

---

### Task 4: Engine interface, model catalog, audio loading, bench CLI

**Files:**
- Create: `app/Sources/ShepitCore/Engine.swift`, `app/Sources/ShepitEngines/{AudioFile,EngineFactory}.swift`, `app/Sources/Shepit/Bench.swift`, `app/Tests/ShepitCoreTests/{EngineTypesTests,CatalogTests}.swift`, `app/Tests/ShepitEnginesTests/AudioFileTests.swift`, `app/Tests/ShepitEnginesTests/Fixtures/hello.wav`
- Modify: `app/Sources/ShepitCore/ModelCatalog.swift`, `app/Package.swift` (add `ShepitEngines` library + `ShepitEnginesTests` with `resources: [.copy("Fixtures")]`), `app/Sources/Shepit/main.swift`

Spec: `02-engines.md` §1, §2 (capabilities column), §5, §6.

**Interfaces:**
- Produces (ShepitCore):
  ```swift
  enum Language: String, Sendable { case uk, en, auto }
  struct TranscriptionRequest: Sendable { var samples: [Float]; var language: Language; var prompt: String; var wantSegments: Bool }
  struct Segment: Equatable, Sendable { var text: String; var start: Double; var end: Double }
  struct Transcript: Equatable, Sendable { var text: String; var segments: [Segment]; var detectedLanguage: String? }
  struct EngineCapabilities: Sendable { var supportsPrompt: Bool; var forcibleLanguages: Set<Language>; var detectsLanguage: Bool; var givesSegmentTimes: Bool
      func check(_ language: Language) -> EngineError? }   // nil = ok
  enum EngineError: Error, Equatable { case modelMissing(String), loadFailed(String), languageNotSupported(Language), recognitionFailed(String), unavailableOnThisMac(String) }
  protocol SpeechEngine: Actor { var choice: EngineChoice { get }; var capabilities: EngineCapabilities { get async }
      func load() async throws; func unload() async; var isLoaded: Bool { get }
      func transcribe(_ request: TranscriptionRequest) async throws -> Transcript }
  ```
  `check`: `.auto` is ok iff `detectsLanguage`; `.uk`/`.en` ok iff in `forcibleLanguages`.
- Produces (ModelCatalog, extending Task 3): `static func folder(for: EngineChoice) -> URL` — whispercpp: `models/ggml-<model>.bin` (a file); whisperkit: `models/whisperkit/<model>/`; parakeet: `models/parakeet/<model>/`; apple: none. `static func isDownloaded(_: EngineChoice) -> Bool` — whispercpp: file exists; whisperkit/parakeet: folder contains `.complete` (written by the download script after all files verify); apple: `true` (the engine itself reports missing assets). `static let vadModel: URL` = `models/ggml-silero-v6.2.0.bin`.
- Produces (ShepitEngines): `enum AudioFile { static func load(_ url: URL) throws -> [Float] }` (16 kHz mono Float32 via `AVAudioFile` + `AVAudioConverter`); `enum EngineFactory { static func make(_ choice: EngineChoice) throws -> any SpeechEngine }` — throws `unavailableOnThisMac` for apple before macOS 26; engine types are added by Tasks 5–8 (until then `make` throws `modelMissing("not implemented")` for them).
- Produces (CLI): `Shepit bench --engine <id> [--model <name>] [--language uk|en|auto] [--prompt <text>] <file>...` — prints one JSON line `{"event":"load","engine":…,"model":…,"seconds":…,"residentMB":…}` then per file `{"event":"result","file":…,"audioSeconds":…,"seconds":…,"text":…,"language":…}`; on error `{"event":"error","message":…}` and exit 1. A capability `check` failure is an error before loading. `residentMB` from `task_info(MACH_TASK_BASIC_INFO).resident_size`.

- [ ] **Step 1: Create the fixture** — `say -v Samantha -o app/Tests/ShepitEnginesTests/Fixtures/hello.wav --data-format=LEI16@16000 "Hello, this is a short test of the speech engine."` (English; committed; ~100 KB).

- [ ] **Step 2: Write failing tests**
  - `capabilityCheckAuto`: caps with `detectsLanguage: false` → `check(.auto) == .languageNotSupported(.auto)`.
  - `capabilityCheckForced`: caps with `forcibleLanguages: [.en]` → `check(.uk) == .languageNotSupported(.uk)`, `check(.en) == nil`.
  - `catalogPaths`: with `DICTATION_HOME=/tmp/h`, `folder(for: (.whisperkit,"large-v3")).path == "/tmp/h/.local/share/dictation/models/whisperkit/large-v3"`.
  - `partialDownloadIsMissing`: a whisperkit folder with files but no `.complete` → `isDownloaded == false`; add `.complete` → `true`.
  - `loadsFixture`: `AudioFile.load(hello.wav).count` within ±1% of `16000 × afinfo duration`.
  - `loadsStereo44k`: write a 1.0 s 44.1 kHz stereo 440 Hz sine with `AVAudioFile` to a temp file → loaded count in 15 840…16 160.
  - `benchRejectsUnsupportedLanguage`: `Bench.run(arguments: ["--engine","apple","--language","uk","x.wav"], engineFactory: { _ in FakeEngine(caps: forcible [.en]) }, output:)` → output contains `"event":"error"` and returns exit code 1. (Bench takes an injectable factory and output sink for this.)

- [ ] **Step 3: Run** → FAIL. **Step 4: Implement.** **Step 5: Run** → PASS.
- [ ] **Step 6: Commit** — `git commit -m "Shepit: engine interface, model catalog, audio loading, bench CLI"`

---

### Task 5: whisper.cpp engine

**Files:**
- Create: `scripts/build-whisper-lib.sh`, `app/Sources/ShepitEngines/WhisperCppEngine.swift`, `app/Tests/ShepitEnginesTests/WhisperCppSmokeTests.swift`
- Modify: `app/Package.swift` (`.binaryTarget(name: "whisper", path: "Vendor/whisper.xcframework")`, ShepitEngines depends on it; link `Accelerate`, `Metal`, `Foundation`), `scripts/build-app.sh` (runs `build-whisper-lib.sh` first), `EngineFactory.swift`

Spec: `02-engines.md` §2 (whispercpp row and bullets).

**Interfaces:**
- Consumes: `SpeechEngine`, `ModelCatalog.folder(for:)`, `ModelCatalog.vadModel`.
- Produces: `actor WhisperCppEngine: SpeechEngine { init(model: String) }`; capabilities: prompt yes, forcible `[.uk, .en]`, detects yes, segment times yes.

- [ ] **Step 1: `build-whisper-lib.sh`** — clone `https://github.com/ggml-org/whisper.cpp` tag `v1.9.4` into `~/.local/share/dictation/src/whisper.cpp-lib`, refuse unless HEAD is `927cfce34f31707e17f2bff35c349632fb9e2c3a` (same check as `build-whisper.sh`); `cmake -B build -DBUILD_SHARED_LIBS=OFF -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DGGML_NATIVE=OFF -DWHISPER_BUILD_EXAMPLES=OFF -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_SERVER=OFF -DCMAKE_OSX_DEPLOYMENT_TARGET=14.2 -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_BUILD_TYPE=Release`; build; merge all produced `.a` files with `libtool -static -o libwhisper-all.a`; headers dir with `whisper.h`, `ggml*.h` and a `module.modulemap` (`module whisper { header "whisper.h" link "c++" export * }`); `xcodebuild -create-xcframework -library libwhisper-all.a -headers <dir> -output app/Vendor/whisper.xcframework`. Skip if `app/Vendor/.whisper-stamp` equals `"v1.9.4 927cfce… $(shasum of this script)"`. No auth patch (no server).

- [ ] **Step 2: Write failing smoke tests** (each `.enabled(if: ModelCatalog.isDownloaded(...))`):
  - `transcribesFixture`: `large-v3-turbo`, language `.en`, no prompt → lowercased text contains `"test"` and `"speech"`; `segments.count >= 1`; `segments[0].start >= 0`.
  - `silenceDoesNotThrow`: 1 s of zeros → no throw, `text.count < 40`.
  - `promptAccepted`: same fixture with prompt `"Kubernetes, GitHub"` → no throw.

- [ ] **Step 3: Run** → FAIL. **Step 4: Implement** with the C API: `whisper_init_from_file_with_params` (`use_gpu = true`); per request `whisper_full_default_params(WHISPER_SAMPLING_GREEDY)`, `language` (`"auto"` for auto), `initial_prompt`, `temperature = 0`, `no_timestamps = !wantSegments`, `n_threads` = `sysctlbyname("hw.perflevel0.physicalcpu")`, `vad = true`, `vad_model_path` = `ModelCatalog.vadModel.path`, `print_progress/print_realtime/print_timestamps = false`; segments from `whisper_full_n_segments` / `whisper_full_get_segment_text` / `_t0`/`_t1` (×0.01 s); `detectedLanguage = whisper_lang_str(whisper_full_lang_id(ctx))`; text = segments joined and trimmed. One `whisper_context` per engine, freed in `unload`. Missing model file → `modelMissing(path)`.
- [ ] **Step 5: Run** → PASS (models exist on this Mac). `scripts/build-app.sh` still succeeds; second run skips the lib build.
- [ ] **Step 6: Bench sanity** — `~/Applications/Shepit.app/Contents/MacOS/Shepit bench --engine whispercpp --model large-v3 --language uk tools/accuracy/recordings/01.wav` → text close to `tools/accuracy/recordings/01.txt`.
- [ ] **Step 7: Commit** — `git commit -m "Shepit: whisper.cpp engine linked in-process"`

---

### Task 6: WhisperKit engine + pinned model downloads

**Files:**
- Create: `scripts/pin-model.sh`, `scripts/models/whisperkit-large-v3.sha256`, `scripts/models/whisperkit-large-v3-turbo.sha256`, `app/Sources/ShepitEngines/WhisperKitEngine.swift`, `app/Tests/ShepitEnginesTests/WhisperKitSmokeTests.swift`
- Modify: `scripts/download-models.sh` (add `--with-whisperkit`), `app/Package.swift` (WhisperKit `exact: "1.1.1"`), `EngineFactory.swift`, `tests/install_test.sh` only if its stubbed run breaks

Spec: `02-engines.md` §2 (whisperkit row), §5.

**Interfaces:**
- Produces: `actor WhisperKitEngine: SpeechEngine { init(model: String) }`; capabilities: prompt yes, forcible `[.uk, .en]`, detects yes, segment times yes.
- Produces: `scripts/download-models.sh` function `fetch_dir <hf-repo> <revision> <remote-dir> <local-dir> <manifest>` reusable by Task 7: downloads each manifest path from `https://huggingface.co/<repo>/resolve/<rev>/<remote-dir>/<path>` into `<local-dir>.part/`, verifies every SHA-256 against the manifest, then renames `<local-dir>.part` → `<local-dir>` and writes `<local-dir>/.complete`. Skips if `.complete` exists. Any mismatch → delete `.part`, exit 1.

- [ ] **Step 1: `pin-model.sh <repo> <revision> <remote-dir> <out-manifest>`** — lists files via `https://huggingface.co/api/models/<repo>/tree/<rev>/<remote-dir>?recursive=1` (type `file` only), downloads each, writes `shasum -a 256` lines with paths relative to `<remote-dir>`. Maintainer-only; output committed.
- [ ] **Step 2: Pin** — repo `argmaxinc/whisperkit-coreml`, revision `0f63a7800b00dd0226abd051b906c246e1907482`; `large-v3` ← `openai_whisper-large-v3`, `large-v3-turbo` ← `openai_whisper-large-v3-v20240930` (that folder is OpenAI's large-v3-turbo; `openai_whisper-large-v3_turbo` is a different Argmax variant — confirm from the repo's README/config before pinning; if wrong, use the one whose config says 4 decoder layers). Commit the two manifests.
- [ ] **Step 3: Download** — `scripts/download-models.sh --with-whisperkit` → `models/whisperkit/{large-v3,large-v3-turbo}/.complete` exist. Run again → skipped. Corrupt one byte of a manifest line in a temp copy and confirm the run fails and leaves no folder (manual check, not committed).
- [ ] **Step 4: Write failing smoke tests** — same three as Task 5 (`transcribesFixture` on `large-v3-turbo`, `silenceDoesNotThrow`, `promptAccepted`) for WhisperKit.
- [ ] **Step 5: Run** → FAIL. **Step 6: Implement** — `WhisperKit(WhisperKitConfig(modelFolder: folder.path, download: false, …))`; `DecodingOptions(task: .transcribe, language: nil for auto else code, temperature: 0, temperatureFallbackCount: 0 (greedy, like whisper.cpp), usePrefillPrompt: true, detectLanguage: language == .auto, withoutTimestamps: !wantSegments, promptTokens: tokenizer-encoded prompt (prefixed with a space, special tokens filtered < tokenizer.specialTokens.specialTokenBegin))`; segments from the results' `segments` (`start`/`end`), detected language from `result.language`. Verify every API name against WhisperKit 1.1.1 sources in `app/.build/checkouts/WhisperKit`.
- [ ] **Step 7: Run** → PASS. Bench sanity on `01.wav` as in Task 5.
- [ ] **Step 8: Commit** — `git commit -m "Shepit: WhisperKit engine and pinned Core ML model downloads"`

---

### Task 7: Parakeet engine

**Files:**
- Create: `scripts/models/parakeet-tdt-0.6b-v3.sha256`, `app/Sources/ShepitEngines/ParakeetEngine.swift`, `app/Tests/ShepitEnginesTests/ParakeetSmokeTests.swift`
- Modify: `scripts/download-models.sh` (`--with-parakeet`, uses `fetch_dir`), `app/Package.swift` (FluidAudio `exact: "0.17.7"`), `EngineFactory.swift`

Spec: `02-engines.md` §2 (parakeet row: no prompt, can't be forced to a language).

**Interfaces:**
- Produces: `actor ParakeetEngine: SpeechEngine { init(model: String) }`; capabilities: prompt no, forcible `[]`, detects yes, segment times yes if FluidAudio's result gives token timings, otherwise no (one segment for the whole input).

- [ ] **Step 1: Pin** — `pin-model.sh FluidInference/parakeet-tdt-0.6b-v3-coreml 7dd20fe6b1797d35f5e3307e8b1732d9a178edfe . scripts/models/parakeet-tdt-0.6b-v3.sha256` (exclude README/.gitattributes if FluidAudio doesn't need them). Download with `--with-parakeet` → `models/parakeet/parakeet-tdt-0.6b-v3/.complete`.
- [ ] **Step 2: Write failing smoke tests** — `transcribesFixture` (`.auto`; contains `"test"`), `silenceDoesNotThrow`, and `forcedLanguageRejected`: `capabilities.check(.uk) == .languageNotSupported(.uk)`.
- [ ] **Step 3: Run** → FAIL. **Step 4: Implement** — load models from the local folder with FluidAudio's ASR model loading API that takes a directory (verify the name in `app/.build/checkouts/FluidAudio` for 0.17.7; it must not hit the network), `AsrManager` initialise + `transcribe(samples)`; text and timings from its result. `request.prompt` is ignored.
- [ ] **Step 5: Run** → PASS. Bench sanity on `01.wav` with `--language auto` (Ukrainian quality is what Task 9 measures; just check it returns text).
- [ ] **Step 6: Commit** — `git commit -m "Shepit: Parakeet engine via FluidAudio"`

---

### Task 8: Apple SpeechAnalyzer engine

**Files:**
- Create: `app/Sources/ShepitEngines/AppleSpeechEngine.swift`, `app/Tests/ShepitEnginesTests/AppleSpeechSmokeTests.swift`
- Modify: `EngineFactory.swift`, `app/Sources/Shepit/Bench.swift` (subcommand `Shepit apple-assets <uk|en>`: reports whether the locale is supported and installed; with `--install` asks the system to download it — user-run only)

Spec: `02-engines.md` §2 (apple row), §5 (apple: system-managed).

**Interfaces:**
- Produces: `@available(macOS 26, *) actor AppleSpeechEngine: SpeechEngine { init() }`; capabilities: prompt = whatever the API supports for contextual strings (verify; if supported, pass `terms` from the prompt split on `", "`), forcible = `{.en}` ∪ `{.uk}` if `SpeechTranscriber.supportedLocales` contains `uk_UA`; detects no; segment times yes (result ranges).
- `load()` throws `modelMissing("Apple speech assets for <locale> are not installed — run: Shepit apple-assets <lang> --install")` when assets aren't installed; never installs by itself.

- [ ] **Step 1: Write failing tests** (`.enabled(if: macOS 26)`): `transcribesFixtureEnglish` (assets for en installed — skip otherwise), `silenceDoesNotThrow`, `autoRejected`: `check(.auto) == .languageNotSupported(.auto)`, `ukSupportMatchesSystem`: `capabilities.forcibleLanguages.contains(.uk) == SpeechTranscriber.supportedLocales.contains { $0.identifier(.bcp47).hasPrefix("uk") }`.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement** with `SpeechAnalyzer` + `SpeechTranscriber` on the in-memory samples (feed an `AVAudioPCMBuffer` in the analyzer's preferred format via `AsyncStream<AnalyzerInput>`, finalize, collect results). Verify names against the macOS 26 SDK. Check whether it needs `SFSpeechRecognizer.requestAuthorization`; if yes, request it in `load()` (usage string already in Info.plist).
- [ ] **Step 4: Run** → PASS (or skipped where assets are missing). `Shepit apple-assets uk` prints supported/installed.
- [ ] **Step 5: Commit** — `git commit -m "Shepit: Apple SpeechAnalyzer engine (macOS 26)"`

---

### Task 9: GATE — benchmark and report (with the user)

**Files:**
- Modify: `tools/accuracy/evaluate.py`, `tools/accuracy/test_evaluate.py`, `docs/superpowers/specs/2026-10-18-native-app/02-engines.md` (append §7 "Benchmark results (date)")

Spec: `02-engines.md` §6.

**Interfaces:**
- Consumes: `Shepit bench` JSON lines (Task 4).
- Produces: `evaluate.py --engines whispercpp:large-v3 whisperkit:large-v3-turbo parakeet:parakeet-tdt-0.6b-v3 apple ... [--shepit PATH]` (default path `~/Applications/Shepit.app/Contents/MacOS/Shepit`); without `--engines` it behaves as today (whisper-server). Prompt variants as today ("no prompt", "style+terms"); engines without prompt support run only "no prompt"; Parakeet runs with `--language auto`, everything else `uk`. Table columns: engine, model, prompt, WER, Latin terms, avg s/clip, load s, resident MB.

- [ ] **Step 1: Write failing test** — `test_parse_bench_output`: feeding canned JSON lines (one load, two results) to `parse_bench(lines)` returns `{"load_s": 2.5, "resident_mb": 3100, "results": [("01.wav", "текст", 1.2), …]}`; `test_engine_spec`: `parse_engine("apple") == ("apple", "")`, `parse_engine("whisperkit:large-v3") == ("whisperkit", "large-v3")`.
- [ ] **Step 2: Run** `cd tools/accuracy && python3 -m unittest -q test_evaluate` → FAIL. **Step 3: Implement**, reusing `normalize`, `wer`, `latin_hit_rate`. **Step 4: Run** → PASS.
- [ ] **Step 5: Run the benchmark** on every downloaded engine+model over `tools/accuracy/recordings/*.wav` (6 clips). Download Apple `uk` assets only if the user agrees.
- [ ] **Step 6:** Append the table and short notes (Ukrainian quality, Latin terms, speed, memory) to `02-engines.md` §7. Commit: `git commit -m "Benchmark engines on the user's clips"`.
- [ ] **Step 7: Report to the user** and ask which engine+model to use for dictation, draft and meetings. Record the decision in `02-engines.md` §6 and change `Settings.defaults.engines` + `examples/settings.json` accordingly (with the Task 3 tests updated), commit. **Phase 1 done** → thermo-nuclear review of the phase diff (see Execution notes), fix, then plan phase 2.
