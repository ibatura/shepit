# Native app — Speech engines

Part of the native app design; see `00-overview.md`.

## 1. One interface

All engines sit behind one Swift protocol. In outline (exact shape left to the builder):

- **Input:** 16 kHz mono Float32 samples; language (`uk`, `en`, `auto`); a prompt
  (style prompt + dictionary terms, built as today); whether time-stamped segments
  are wanted.
- **Output:** the text, segments with `start`/`end` in seconds (one segment for the
  whole input if the engine can't give times), and the detected language if known.
- **Capabilities:** supports a prompt or not; which languages it can be told to use;
  whether it can detect the language; whether it gives segment times.
- **Lifecycle:** load (async, reports progress), unload, and whether it's loaded.
- Errors are typed (model missing, load failed, language not supported, recognition
  failed) so the menu and notices can say what to do.

Post-processing stays engine-independent and unchanged: hallucination stripping,
`replace` rules, trimming (today's `dictionary.process`). For engines without prompt
support, `terms` still help through the `replace` rules only.

## 2. The engines

| id | engine | models | runs on | prompt | notes |
|---|---|---|---|---|---|
| `whisperkit` | WhisperKit (Argmax), Swift package | `large-v3`, `large-v3-turbo` (Core ML builds of the same Whisper models) | Neural Engine / GPU | yes (prompt tokens) | candidate default |
| `whispercpp` | whisper.cpp, linked in-process | `large-v3`, `large-v3-turbo` (the existing ggml files) | GPU (Metal) | yes | today's quality; fallback. Silero VAD as today |
| `parakeet` | Parakeet TDT v3 via FluidAudio | `parakeet-tdt-0.6b-v3` | Neural Engine | no | multilingual; whether Ukrainian and uk+en mixing work is checked in phase 1 |
| `apple` | Apple `SpeechAnalyzer` / `SpeechTranscriber` | system-managed | system | verify (contextual strings) | macOS 26+ only; hidden on older systems. Ukrainian support checked at runtime from its supported locales |

- whisper.cpp keeps today's request settings (temperature 0, VAD on). With the
  server gone, the auth patch and port are gone too.
- WhisperKit should get settings equivalent to today's whisper.cpp ones
  (temperature 0, forced language, prompt). Its exact model variant names on
  Hugging Face (`argmaxinc/whisperkit-coreml`) are pinned in the build.
- **Language mismatch:** each engine reports what it can do. If the chosen language
  isn't supported (e.g. Apple without Ukrainian), Settings shows it next to the
  choice, and dictation shows a ⚠ notice instead of silently changing language.
  Parakeet can't be forced to a language; it always detects, and Settings says so.
- Exact API names of WhisperKit, FluidAudio and SpeechAnalyzer are verified against
  the pinned versions.

## 3. Choosing per task

Three choices, each an engine plus a model (`04-settings.md`):

| task | what it does | today's equivalent |
|---|---|---|
| `dictation` | the text that gets pasted | `model` |
| `preview` | the live draft in the panel | `previewModel` |
| `meetings` | meeting transcripts (phase 3) | — |

The same engine+model may be chosen for several tasks.

## 4. Memory and loading

- One loaded instance per distinct engine+model; tasks that chose the same one share it.
- At launch the `dictation` and `preview` models are loaded (as today both servers
  start at launch). The `meetings` model loads when a meeting starts, if it isn't
  already loaded.
- `idleUnloadMinutes` (existing setting) applies to every loaded model; an unloaded
  model loads again on next use, and the menu shows "Loading …".
- **One recognition at a time per loaded model.** A dictation always goes first:
  live-draft and (in phase 3) meeting requests wait while a dictation's final pass
  is queued or running. Different loaded models may run in parallel.
- Changing a task's engine in Settings loads the new model in the background and
  unloads the old one if no task uses it.

## 5. Models on disk

| engine | where | how it gets there |
|---|---|---|
| whisper.cpp | `models/ggml-*.bin` (existing files, unchanged) | `scripts/download-models.sh`, as today |
| WhisperKit | `models/whisperkit/<variant>/` | install script, or Settings → Engines → Download |
| Parakeet | `models/parakeet/<variant>/` | same |
| Apple | system | Settings → Engines → Download asks macOS to install the language assets |

- Every download is pinned to a fixed revision and verified (SHA-256 like today, or
  an equivalent pinned check).
- Settings → Engines lists every model with its state (downloaded and size / not
  downloaded / downloading with progress / not available on this macOS) and offers
  Download and Delete. Downloads happen only on a click there or in the install
  script — never on their own. *(My call: today only the install script touches the
  network; adding a Download button is what makes engine choice usable from the UI.)*
- `install.sh` flags: by default whisper.cpp `large-v3` (as today) plus WhisperKit
  `large-v3` and `large-v3-turbo` once WhisperKit is the default; `--with-turbo` as
  today; `--with-parakeet` optional. Final default set decided after the phase 1 benchmark.
- A task whose model isn't downloaded can't be selected in Settings (it shows
  Download instead). If a model goes missing, the menu shows ⚠ with the fix.

## 6. Benchmark and the default

- `Shepit bench --engine <id> --model <name> [--language uk] [--prompt …] <wav>…`
  prints JSON per file: text, load time, recognition time, audio length.
- `tools/accuracy/evaluate.py` gets an option to run through `Shepit bench`
  instead of whisper-server, and reports the existing metrics (WER, Latin-term hit
  rate, seconds per clip) per engine+model, with and without the style prompt.
- Phase 1 ends with a report to the user: a table like
  `2026-10-04-dictation-tool-design.md` §10 for all engines and models on the
  existing six clips, plus model load time and memory. **The user decides the
  defaults.** Until then the defaults are today's: whisper.cpp `large-v3` for
  dictation and meetings, whisper.cpp `large-v3-turbo` for the draft.

**Decision (2026-10-23, after §7):** whisper.cpp `large-v3-turbo` for dictation,
draft and meetings — the most accurate row in §7 with the style prompt, 1.5×
faster and half the memory of `large-v3`. The user can switch any task in
settings later. Consequence for phase 2: Shepit's installer must download
`ggml-large-v3-turbo.bin` by default (today it needs `--with-turbo`; the Lua
tool's install is left as is).

## 7. Benchmark results (2026-10-23)

Six clips of the user reading Ukrainian with English terms (`tools/accuracy/`),
`evaluate.py --engines …` through a release build of `Shepit bench`, one process
per row, temperature 0. Language `uk`, except Parakeet (`auto`: it can't be
forced). "style+terms" = the style prompt plus the 14 default terms; Parakeet
has no prompt; Apple gets the terms as contextual strings.

| engine | model | prompt | WER | Latin terms | avg s/clip | load s | resident MB |
|---|---|---|---|---|---|---|---|
| whispercpp | large-v3 | none | 29.8% | 6/17 | 1.29 | 23.7 | 3476 |
| whispercpp | large-v3 | style+terms | 21.3% | 13/17 | 1.30 | 1.2 | 3504 |
| whispercpp | large-v3-turbo | none | 28.0% | 10/17 | 0.83 | 0.7 | 1820 |
| whispercpp | large-v3-turbo | style+terms | **18.2%** | 13/17 | 0.83 | 0.6 | 1821 |
| whisperkit | large-v3 | none | 27.1% | 9/17 | 3.39 | 156.0 | 83 |
| whisperkit | large-v3 | style+terms | 22.7% | 12/17 | 9.21 | 1.2 | 95 |
| whisperkit | large-v3-turbo | none | 39.6% | 6/17 | 1.34 | 129.4 | 82 |
| whisperkit | large-v3-turbo | style+terms | 25.7% | 12/17 | 2.30 | 1.1 | 86 |
| parakeet | parakeet-tdt-0.6b-v3 | none | 42.8% | 0/17 | **0.10** | 25.8 | 80 |
| apple | — (DictationTranscriber uk-UA) | none | 43.3% | 0/17 | 0.23 | 0.0 | 16 |
| apple | — (DictationTranscriber uk-UA) | style+terms | 43.3% | 0/17 | 0.20 | 0.0 | 16 |

Notes:
- **Quality:** whisper.cpp is best and matches the 2026-10-05 numbers exactly
  (same model, same decoding). WhisperKit large-v3 is close; WhisperKit turbo is
  worse than whisper.cpp turbo («Намітнигу», «кмит»). Parakeet's Ukrainian is
  good but it writes every English term in Cyrillic («пул реквест в Гітхаб») and
  can't take a prompt. Apple drops words outright («відкрив і попросив»,
  «Pinterest» for NullPointerException); contextual strings changed nothing.
- **Latin terms:** only the Whisper engines with the prompt get them right (12–13/17).
- **Speed:** Parakeet 0.10 s/clip and Apple 0.2 s/clip are 8–13× faster than
  whisper.cpp turbo; WhisperKit is the slowest, and the prompt makes it slower
  (prefill) — 9.2 s/clip for large-v3.
- **Load time:** the first row of each engine includes a cold start — Core ML
  compiles WhisperKit models on first use (2–2.5 min, cached after), whisper.cpp
  reads 3 GB from disk (24 s cold, ~1 s warm).
- **Memory:** "resident MB" is the process's resident size. For whisper.cpp it is
  the real cost (weights in RAM/Metal). Core ML engines show ~80 MB because their
  weights live in Core ML/ANE memory that isn't counted there — not comparable.
- Apple has no Ukrainian in `SpeechTranscriber` (macOS 26.4); these rows are the
  older `DictationTranscriber` fallback.
