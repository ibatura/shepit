# Native app — Statistics

Part of the native app design; see `00-overview.md`.

The user wants statistics with charts, as in the approved mockup. More metrics may
be added later; the data stored should make that possible without migrations where
reasonable.

## 1. What is stored

A local SQLite database, `~/.local/share/dictation/stats.sqlite`. **No dictated or
transcribed text and no audio** — only numbers and names below. Nothing is ever
sent anywhere.

**One row per dictation attempt:**
| field | meaning |
|---|---|
| time | when recording started (local time zone stored too, for the heatmap) |
| outcome | `pasted`, `copied` (no Accessibility), `empty`, `cancelled`, `discarded` (too short), `failed` |
| audio seconds | recording length |
| wait seconds | stop → text ready (recognition + queueing) |
| words, characters | of the final text (0 if none) |
| engine, model | used for the final text |
| language | requested, and detected if the engine reported it |
| app | bundle ID and name of the app the text was pasted into |
| replacements | how many dictionary `replace` rules fired |
| replaced terms | which `replace` targets fired (the corrected words, e.g. `Kubernetes`) — these are dictionary entries the user wrote, not dictated text |
| preview requests | how many live-draft requests ran |

**One row per meeting** (phase 3): start, duration, words by stream (mine / call),
number of speakers detected, transcription engine, diarization seconds, failed chunks.

**Model events:** engine, model, load seconds, resident memory after load (best effort).

`collectStats` false → nothing new is recorded; existing data stays until
**Clear statistics…** (History & Privacy), which deletes the database.
`uninstall.sh --purge` deletes it too.

## 2. Statistics screen

A period picker: **Day, Week, Month, Year, All**. Every figure and chart follows it.

**Tiles** (with change vs the previous period of the same length):
- **Dictations** — count of `pasted` + `copied`.
- **Words dictated.**
- **Time saved** = words ÷ `typingSpeedWpm` − (audio seconds + wait seconds), summed
  over successful dictations (`pasted` and `copied`; other outcomes count 0); never shown below zero per dictation. A note under it
  says how it's computed and links to the typing-speed setting.
- **Meetings · hours** (phase 3; shows "—" before).

**Charts** (Swift Charts):
- **Words per day** — stacked bars, dictation and meetings. Bucket by hour for Day,
  by day for Week/Month, by month for Year/All.
- **Speed by engine** — median wait after stop per engine+model, and median wait per
  10 s of audio, so long and short dictations compare fairly.
- **Pasted into** — top apps by number of dictations (top 8, rest as "Other").
- **When you dictate** — hour × weekday heatmap of dictation counts.
- **Quality signals** — share cancelled, share failed, share empty; languages
  detected; dictionary fixes count and top corrected terms.

Empty states say "No dictations in this period yet."

## 3. Not in v1 (to discuss later)

The user said more metrics will be discussed later. Ideas already raised: average
dictation length, longest streak of days, engine usage share, model load time and
memory over time, meeting speakers and diarization time. The stored fields above
already cover most of them.
