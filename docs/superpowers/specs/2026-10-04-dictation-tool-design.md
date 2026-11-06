# Dictation Tool — Design Spec

Date: 2026-10-04
Status: Draft, awaiting review

## 1. Goal

A local, fast macOS dictation tool. Press a hotkey, speak (mostly Ukrainian with
English technical terms embedded), and the transcribed text is pasted into the
active application at the cursor.

### Requirements (from user)

- Uses whisper.cpp with a large model; default `ggml-large-v3`.
- Small tool written in Lua, fast, macOS only.
- Hotkey behaviour is configurable: **toggle** (press to start, press again to
  stop) or **hold-to-talk**. The actual hotkeys are set in settings.
- Ukrainian + English in the same utterance. Typical speech is Ukrainian with
  English terms embedded mid-sentence; English terms must appear in Latin script
  (`pull request`, not `пул реквест`).
- User-editable dictionary to improve recognition of custom terms/names.
- Transcribed text is pasted into the active app.
- Menu-bar (top panel) icon with a dropdown of settings.
- Dictionary and settings files are JSON.
- Everything runs locally on the laptop; no cloud services.

### Success criteria

- Stop-to-paste latency for a 30 s dictation ≤ ~6 s on the M1 Pro (32 GB) with
  `large-v3`.
- Embedded English terms from the dictionary come out in Latin script in the
  large majority of cases; remaining misses are fixable via `replace` rules.
- Pasting works in common apps (Terminal, browser, Slack, VS Code).
- A malformed config file or a crashed server never leaves the tool unusable.

### Out of scope (v1)

Live/streaming transcription, translation, hotkey-recorder GUI, per-app
profiles, auto-update, non-macOS platforms.

## 2. Architecture

Runtime is **Hammerspoon** (Lua). It provides global hotkeys (with key-down and
key-up events), menu bar, clipboard, keystroke synthesis, task spawning, and
HTTP. Audio is recorded by **sox** (`rec`). Transcription is done by
**whisper.cpp's `whisper-server`**, running locally as a background process
bound to `127.0.0.1`, keeping the model resident in memory (Metal GPU).

```
┌──────────────── Hammerspoon (Lua) ────────────────┐
│ init.lua ── wires modules, binds hotkeys          │
│  ├─ config.lua      load/validate/save JSON       │
│  ├─ menubar.lua     icon 🎙/🔴/⏳ + dropdown       │
│  ├─ recorder.lua    start/stop sox `rec`          │
│  ├─ server.lua      spawn/monitor whisper-server  │
│  ├─ transcriber.lua POST wav → text               │
│  ├─ dictionary.lua  prompt builder + replacements │
│  ├─ controller.lua  state machine (modes, cancel) │
│  └─ paster.lua      clipboard → ⌘V → restore      │
└───────────────────────────────────────────────────┘
        │ hs.task                 │ HTTP 127.0.0.1
        ▼                         ▼
   sox `rec` → /tmp/*.wav    whisper-server (Metal, model resident)
```

### File locations

| What | Where |
|---|---|
| Code | this repo (`src/`) |
| Hammerspoon hook | one `dofile`/`require` line in `~/.hammerspoon/init.lua` |
| Settings | `~/.config/dictation/settings.json` |
| Dictionary | `~/.config/dictation/dictionary.json` |
| Models | `~/.local/share/dictation/models/` |
| Transcript history | `~/.local/share/dictation/history.log` |
| Temp audio | `/tmp/dictation-<timestamp>.wav` |

### Dependencies

`brew install sox cmake`, `brew install --cask hammerspoon`. `whisper-server` is built from whisper.cpp source (tag v1.9.4) because the Homebrew formula does not include it.
Models: `ggml-large-v3.bin` (~3 GB, default), optional
`ggml-large-v3-turbo.bin` (~1.6 GB), Silero VAD model `ggml-silero-v6.2.0.bin` (~1 MB).

## 3. Components

Each module has one purpose and a small interface. Pure-logic modules
(`dictionary`, `config` validation, `controller`) have no direct Hammerspoon
dependency so they can be unit-tested with plain Lua.

### config.lua
- Loads `settings.json` and `dictionary.json` via `hs.json`, merges settings
  over built-in defaults, validates types/enums.
- On parse or validation error: keep the last good config, show an alert with
  the file and error message.
- `save(settings)` writes settings back (used by menu changes: mode, model,
  language). Settings file is the single source of truth.

### menubar.lua
- Icon reflects state: idle 🎙, recording 🔴, transcribing ⏳.
- Dropdown:
  ```
  Status: Ready — large-v3
  ──────────
  Mode           ▸ ✓ Toggle / Hold to talk
  Model          ▸ ✓ large-v3 / large-v3-turbo   (only models present on disk)
  Language       ▸ ✓ Ukrainian / English / Auto-detect
  ──────────
  Edit dictionary…     (opens dictionary.json in default editor)
  Edit settings…       (opens settings.json)
  Reload config
  Restart whisper server
  Open history
  Quit
  ```
- Status line shows errors (server down, missing mic permission, config error).

### recorder.lua
- `start(path)`: spawns `rec -q -c 1 -r 16000 -b 16 <path>` via `hs.task`.
- `stop()`: terminates the task (SIGTERM so the WAV header is finalized),
  returns path and duration.
- `cancel()`: stops and deletes the file.
- Reports spawn failures (sox missing, mic permission denied) to the caller.

### server.lua
- Spawns `whisper-server` with: model path, `--host 127.0.0.1`, `--port`,
  VAD enabled with the VAD model, threads tuned for the machine.
- Health check via HTTP before marking ready; menu shows "Loading model…"
  until then.
- Restarts on unexpected exit (with backoff) and when the model setting
  changes. Terminated when Hammerspoon quits/reloads.
- Optional idle unload: if `idleUnloadMinutes > 0`, stop the server after that
  idle period and start it lazily on next recording.

### transcriber.lua
- POSTs the WAV as multipart to the server's inference endpoint with:
  `language` (`uk` / `en` / `auto`), `prompt` (from dictionary.lua),
  `temperature=0`, `response_format=json`.
- Uses `curl` via `hs.task` (multipart upload is simpler and more reliable than
  `hs.http` for files). Async; callback with text or error.
- On connection failure: ask server.lua to restart, retry once.

### dictionary.lua (pure logic)
- `buildPrompt(stylePrompt, terms, maxTokens)`: style sentence + `", "`-joined
  terms. Trimmed to stay within whisper's prompt window (~224 tokens) using a
  conservative estimate (Cyrillic ≈ 3 tokens/word, Latin ≈ 1.5); terms are
  dropped from the end, so list order is priority.
- `applyReplacements(text, replace)`: case-insensitive, whole-word matching
  that works for Cyrillic (custom UTF-8 lowercase mapping for Ukrainian/Russian
  letters, since Lua's `string.lower` is ASCII-only). Longest keys applied
  first. Replacement value is inserted verbatim.
- `stripHallucinations(text, phrases)`: removes known whisper artifacts
  ("Дякую за перегляд!", "Субтитри зроблено…", "Thanks for watching!", etc.)
  only when they are the entire output or the final sentence.

### controller.lua (state machine)
States: `idle → recording → transcribing → idle`.

- **toggle mode**: hotkey down in `idle` → start; hotkey down in `recording` →
  stop and transcribe.
- **hold mode**: hotkey down → start; hotkey up → stop and transcribe.
  Holds shorter than 0.3 s are discarded.
- **cancel**: the cancel key (default Esc) is bound only while recording;
  discards audio, returns to idle.
- Hotkey presses in `transcribing` are ignored.
- Recordings shorter than 0.5 s are discarded.
- Auto-stop at `maxRecordingSeconds` (default 300) and transcribe.
- Remembers the frontmost app at recording start, for refocus before paste.

### paster.lua
- Optionally refocus the original app (`refocusOriginalApp`, default true).
- Save clipboard contents, set transcript, send ⌘V, restore clipboard after
  ~0.5 s (`restoreClipboard`, default true).
- Append every transcript to `history.log` (timestamp + text) so text is never
  lost if the paste misses.

## 4. Data flow

1. Hotkey → controller: `idle → recording`; start sound; icon 🔴; recorder
   starts writing WAV; frontmost app remembered.
2. Stop (toggle press / hold release / auto-stop) → recorder stops; icon ⏳.
3. transcriber POSTs WAV + language + prompt to local whisper-server
   (VAD strips silence server-side).
4. Text → `stripHallucinations` → `applyReplacements` → trimmed.
5. Empty result → alert "Nothing recognized", no paste. Otherwise paster pastes
   and logs to history.
6. Icon 🎙; end sound; WAV deleted (kept 24 h on failure for debugging).

## 5. Language handling

Speech is Ukrainian-based with English terms embedded mid-sentence. Whisper
picks one language per 30 s window and, when forced to `uk`, tends to write
English terms in Cyrillic. Three layered measures:

1. **Forced base language**: default `language=uk` (menu: Ukrainian / English /
   Auto-detect). Auto-detect is not the default because it may pick English and
   translate the Ukrainian.
2. **Bilingual style prompt**: whisper imitates the prompt's style. Default
   `stylePrompt` is Ukrainian text with Latin-script English terms, e.g.
   "Сьогодні я відкрив pull request у GitHub, задеплоїв сервіс у Kubernetes і
   оновив README." followed by dictionary `terms`. User-editable in settings.
3. **Post-processing replacements** from `dictionary.json` fix residual
   transliterations.

Plus `temperature=0` for deterministic output and VAD to reduce
hallucinations on silence.

This approach is validated early with real recordings (see §8) before the
rest of the tool is built on it.

## 6. Configuration files

### settings.json (defaults shown)
```json
{
  "mode": "toggle",
  "hotkey": { "mods": ["alt"], "key": "space" },
  "cancelKey": "escape",
  "model": "large-v3",
  "language": "uk",
  "stylePrompt": "Сьогодні я відкрив pull request у GitHub, задеплоїв сервіс у Kubernetes і оновив README.",
  "refocusOriginalApp": true,
  "restoreClipboard": true,
  "sounds": true,
  "maxRecordingSeconds": 300,
  "serverPort": 8178,
  "idleUnloadMinutes": 0
}
```
- `mode`: `"toggle"` | `"hold"`.
- `hotkey.mods`: any of `cmd`, `alt`, `ctrl`, `shift`; `hotkey.key`: a
  Hammerspoon key name.
- `model`: `"large-v3"` | `"large-v3-turbo"` (maps to
  `ggml-<model>.bin` in the models dir).
- `language`: `"uk"` | `"en"` | `"auto"`.

### dictionary.json
```json
{
  "terms": ["Kubernetes", "Terraform", "pull request", "PitchBook", "Hammerspoon"],
  "replace": {
    "пул реквест": "pull request",
    "кубернетіс": "Kubernetes",
    "гіт хаб": "GitHub"
  },
  "dropPhrases": ["Дякую за перегляд!", "Субтитри зроблено"]
}
```
- `terms`: fed into the prompt, in priority order.
- `replace`: case-insensitive whole-word rules, longest first.
- `dropPhrases`: extra hallucination phrases, added to built-in list.

JSON has no comments; every field is documented in the README. Invalid files
never break dictation — last good config is kept and an alert explains the
error.

## 7. Error handling

| Situation | Behaviour |
|---|---|
| whisper-server not running / unreachable | Alert, restart server, retry once; then alert failure, keep WAV, log text unavailable |
| Model still loading | Menu shows "Loading model…"; recording allowed, transcription waits until ready (timeout 60 s) |
| sox missing / mic permission denied | Alert with fix instructions; menu status shows problem |
| Accessibility permission missing | Alert with instructions (needed for hotkeys and ⌘V) |
| Empty transcript | Alert "Nothing recognized"; no paste |
| Config JSON invalid | Keep last good config; alert with file + error |
| Model file missing | Menu lists only installed models; alert if configured model is absent |
| Original app quit before paste | Paste into current frontmost app; text also in history |

## 8. Installation & testing

### install.sh
1. `brew install whisper-cpp sox`, `brew install --cask hammerspoon`
   (skip if present).
2. Download `ggml-large-v3.bin` + VAD model into the models dir with checksum
   verification; `--with-turbo` also fetches `ggml-large-v3-turbo.bin`.
3. Create `settings.json` / `dictionary.json` from `examples/` if absent
   (never overwrite).
4. Add the loader line to `~/.hammerspoon/init.lua` idempotently.
5. Print one-time permission steps: Accessibility + Microphone for Hammerspoon.

`uninstall.sh` reverses this; keeps models and user config unless `--purge`.

### Tests
- **Unit (plain Lua, `busted`)**, with a minimal `hs` stub where needed:
  - Cyrillic case-insensitive whole-word replacement; longest-first ordering.
  - Prompt building and token-budget trimming.
  - Hallucination stripping.
  - Config loading, defaults merge, validation, last-good fallback.
  - Controller state machine: toggle, hold, cancel, too-short discard,
    ignore-while-transcribing, auto-stop.
- **Accuracy harness (run first)**: a script sends a set of WAVs of the user
  speaking Ukrainian with embedded English terms to `whisper-server`, compares
  output with reference text, and reports word error rate plus Latin-term hit
  rate. Matrix: `large-v3` vs `large-v3-turbo` × with/without style prompt.
  Needs ~5 user recordings of 10–20 s (script with suggested sentences
  provided).
- **Manual checklist**: both modes, cancel, paste into Terminal / browser /
  Slack / VS Code, switching apps mid-recording, server crash recovery,
  malformed JSON, missing mic permission.

## 9. Open items to verify during implementation

- Exact whisper-server request field names and VAD flags for the installed
  whisper.cpp version (Homebrew `whisper-cpp` 1.9.4).
- Model download URLs and checksums (Hugging Face `ggerganov/whisper.cpp` and
  the whisper.cpp VAD model repo).
- Whether Hammerspoon's hotkey key-up events are reliable for hold mode with
  the chosen default combo; if ⌥Space conflicts, pick another default.

## 10. Accuracy results (2026-10-05)

Six clips of the user reading Ukrainian sentences with embedded English terms
(`tools/accuracy/`), `language=uk`, temperature 0:

| model | prompt | WER | Latin terms | avg s/clip |
|---|---|---|---|---|
| large-v3 | none | 29.8% | 6/17 | 1.48 |
| large-v3 | style + 5 terms | 25.9% | 10/17 | 1.43 |
| large-v3-turbo | none | 28.0% | 10/17 | 0.91 |
| large-v3-turbo | style + 5 terms | 24.7% | 9/17 | 0.91 |
| large-v3 | style + 14 terms | 21.3% | 13/17 | — |
| large-v3-turbo | style + 14 terms | 18.2% | 12/17 | — |

With the 14-term prompt plus the example `replace` rules, every embedded
English term came out in Latin script on all six clips for both models (only
"Kibana" casing needed an extra rule). WER is inflated by the reference using
«у» where the speaker said «в».

Decision: keep `large-v3` as default (user preference; quality is on par), keep
the style prompt, ship the expanded example dictionary. Turbo is ~40% faster
and a reasonable menu choice.

## 11. Addendum (2026-10-05): live overlay with preview text

User feedback after first use: it is not obvious when the tool is listening or
working. Requested: a small window showing that it listens, an icon, and the
text appearing live while speaking; the window closes when done and the text is
inserted where the cursor was. This supersedes "Live/streaming transcription"
in §1 Out of scope.

### Behaviour
- A floating panel (`hs.canvas`) at the bottom centre of the screen with the
  focused window, ~560×96 pt, rounded, dark translucent background.
- It never takes focus and ignores the mouse, so the user's app keeps keyboard
  focus throughout. No refocus is needed for the overlay itself.
- Visible on all Spaces and above full-screen apps.
- States:
  | state | content |
  |---|---|
  | recording | `🔴 Слухаю · m:ss`, a level meter, and the latest preview text (tail, ≤ 2 lines) |
  | transcribing | `⏳ Розпізнаю…` and the last preview text |
  | done | `✓` and the final text; hides after 1 s |
  | message | short notice (cancelled, nothing recognized, errors); hides after 2.5 s |
- When the overlay is enabled, controller notifications go to the overlay
  instead of `hs.alert`. Config and server errors still use `hs.alert`.

### Live preview
- While recording, every 2 s the last 20 s of audio are cut from the growing WAV
  and sent to a second whisper-server running `previewModel` (default
  `large-v3-turbo`) on `serverPort + 2`. Same language, prompt and dictionary
  post-processing as the final pass.
- At most one preview request in flight; ticks that find one running are
  skipped. Results that arrive after recording stopped are discarded.
- The final text is unchanged: the full recording goes to the main model and is
  pasted as before. Preview text is never pasted.
- If the preview model is not installed, or `livePreview` is false, the preview
  server is not started and the overlay shows status and level only.
- The preview server costs ~2 GB RAM; it follows the same idle-unload setting.

### Reading a WAV while sox writes it
sox leaves the RIFF/data sizes as placeholders until it exits. The audio length
is therefore derived from the file size: `(size − 44) / 2` samples (16 kHz, mono,
16-bit, 44-byte header; verified with `xxd` on a live recording). Snapshots are
written as a fresh WAV with a correct header. The level meter reads the last
0.1 s directly from the file and computes RMS.

### New settings
| key | default | meaning |
|---|---|---|
| `overlay` | `true` | show the floating panel |
| `livePreview` | `true` | show draft text while speaking |
| `previewModel` | `"large-v3-turbo"` | model used for draft text |
