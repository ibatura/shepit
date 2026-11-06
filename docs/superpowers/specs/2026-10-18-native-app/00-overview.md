# Native macOS app — Overview

Date: 2026-10-18
Status: Draft, awaiting review

This design is split into several files:

| file | what |
|---|---|
| `00-overview.md` | this file: intent, decisions, goals, phases |
| `01-app-build-signing.md` | the app shell, permissions, build, code signing, install, switchover from Hammerspoon |
| `02-engines.md` | speech engines (WhisperKit, whisper.cpp, Parakeet, Apple) and models |
| `03-dictation.md` | dictation feature parity with today's tool |
| `04-settings.md` | `settings.json` changes and the Settings window |
| `05-statistics.md` | usage statistics and charts |
| `../2026-10-17-meeting-transcription-design.md` | meeting transcription, revised for the native app (phase 3) |

The existing design `../2026-10-04-dictation-tool-design.md` (with its §11 overlay
addendum) and the README describe today's behaviour; "parity" below means that
behaviour unless a file here says otherwise.

## 1. Intent

Today the tool is Lua on Hammerspoon, with sox for recording and a patched
`whisper-server` over local HTTP. The planned meeting feature needs Swift anyway
(Core Audio process tap, FluidAudio speaker detection), which would make the tool a
mix of Lua, Swift helpers, an HTTP server and sox.

The user wants one native macOS app written in Swift instead: no Hammerspoon, no
sox, no server process. whisper.cpp may stay as a library. The rewrite also opens
the door to other local speech models, which the user called a big plus: they want
to choose between WhisperKit, whisper.cpp, Parakeet and Apple's speech engine,
separately for each task. They also want a proper Settings window and usage
statistics with charts.

## 2. Decided by the user

- Rewrite the whole tool as a native Swift macOS menu-bar app; remove Hammerspoon
  and sox. Order: **first dictation parity, then the meeting feature** as already
  specified (revised for the native app). No Lua meeting implementation first.
- Engines to choose from: **WhisperKit**, **whisper.cpp**, **Parakeet**, **Apple
  SpeechAnalyzer**. WhisperKit becomes the default if it is faster on the same
  Whisper models without being worse. **whisper.cpp stays as the fallback** for now;
  it can be removed later.
- The engine (and model) is chosen **separately for dictation (final text), the live
  draft, and meetings** — the same one for all, or different ones.
- Code signing: a **self-signed certificate in the Keychain** now, created by the
  build script, with instructions so anyone can build on their own Mac. **Developer
  ID** (paid) and notarization later, if everything works out.
- A **Settings window** with a good UI. Settings still live in a file
  (`settings.json`), not only in the UI.
- **Statistics with charts**, as in the mockup the user approved: dictations, words,
  meetings and hours, words per day, engine speed, **where text is pasted**, **time
  saved compared with typing**, hour × weekday heatmap, quality signals. More
  metrics will be discussed later.
- The design is written as several files.

## 2a. Name

The app is called **Shepit** (Ukrainian «шепіт», "whisper"), chosen by the user.
`Shepit.app`, shown as "Shepit" in the menu, Settings and README. The data folders
keep their current names (`~/.config/dictation`, `~/.local/share/dictation`) so
existing settings, dictionary and history work without moving anything. The repo
name is unchanged. *(My call: data folders and repo name kept.)*

## 3. Goals, non-goals, anti-goals

**Goals**
- One app, `Shepit.app`, that does everything today's tool does (`03-dictation.md`).
- Pluggable speech engines behind one interface, chosen per task in Settings.
- A measured choice of the default engine: a benchmark on the user's own clips
  (`tools/accuracy`) comparing speed and accuracy, shown to the user before the
  default changes.
- A Settings window covering every setting, plus the dictionary.
- Local statistics with charts.
- Anyone with an Apple Silicon Mac and Xcode can clone, run one script and get a
  working, signed app whose permissions survive rebuilds.
- Then: meeting transcription on top of the same app.

**Non-goals (v1)** — candidates for `docs/future-ideas.md`
- Developer ID signing, notarization, distributing a prebuilt `.app`, auto-update.
- Mac App Store / App Sandbox.
- Intel Macs; macOS older than 14.2 (whole app requires 14.2, see `01`).
- Streaming recognition (engines are called on finished audio, as today; the draft
  keeps today's "re-transcribe the last 20 s every 2 s" approach).
- Cloud engines of any kind.
- Statistics beyond those listed in `05-statistics.md`.
- Translation, voice commands, per-app profiles, LLM clean-up (already in future ideas).

**Anti-goals** — failure even if it "works"
- Any audio or dictated text leaving the Mac. The app touches the network only to
  download models, and only when the user asks (install script or a Download button).
- Dictation slower than today with the same model (stop-to-paste), or less reliable.
- Losing text: every result still goes to `history.log` before pasting.
- Permissions (Accessibility, Microphone) lost on every rebuild.
- The user's existing `settings.json`, `dictionary.json` and `history.log` not
  working unchanged in the new app.
- The statistics database containing dictated or transcribed text.

## 4. Phases

1. **Skeleton and engines.** Menu-bar app, build script, signing (with the
   permissions-survive-rebuild check done first), settings loading, the four engines
   behind one interface, and a `bench` command. Run the benchmark on the
   `tools/accuracy` clips and report to the user; the user picks the defaults.
2. **Dictation parity, Settings window, statistics.** Everything in `03`, `04`, `05`.
   Today's Lua tool keeps working until the switchover (`01` §6).
3. **Meetings**, per the revised meeting design.

Each phase is planned and reviewed on its own.

## 5. Machine and environment

Apple M1 Pro, 32 GB, macOS 26.4, Swift 6.3.3. The user dictates mostly Ukrainian
with English technical terms, and has calls in Teams and Google Meet. Existing
models on disk: `ggml-large-v3.bin`, `ggml-large-v3-turbo.bin`,
`ggml-silero-v6.2.0.bin` in `~/.local/share/dictation/models/`.
