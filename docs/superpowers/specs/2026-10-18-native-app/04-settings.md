# Native app — Settings file and Settings window

Part of the native app design; see `00-overview.md`.

## 1. The file stays the source of truth

- Settings stay in `~/.config/dictation/settings.json`, the dictionary in
  `dictionary.json`. The user's existing files work unchanged.
- Same rules as today: only the keys you set are stored, everything else uses the
  default; invalid JSON or values → the last good settings stay in use, and a notice
  plus a ⚠ menu line name the field and what's allowed; the files are watched and
  changes apply on save.
- The Settings window **reads and writes the same file**. A change in the window
  writes only that key into the raw file (keeping the user's other keys and unknown
  keys), validated first, via temp file + rename — as `Store:update` does today.
  Editing the file by hand updates an open window.
- If the file has errors, the window shows them at the top and controls are
  read-only until the file is fixed (today the menu refuses changes in that case too).

## 2. Changes to keys

**New: engine per task.**
```json
"engines": {
  "dictation": { "engine": "whispercpp", "model": "large-v3" },
  "preview":   { "engine": "whispercpp", "model": "large-v3-turbo" },
  "meetings":  { "engine": "whispercpp", "model": "large-v3" }
}
```
- `engine`: `whisperkit`, `whispercpp`, `parakeet`, `apple`. `model`: one of that
  engine's models (`02-engines.md` §2); `apple` has no model (`"model"` omitted or `""`).
- Each task may be set on its own; missing tasks use defaults.
- **Compatibility:** if `engines.dictation` is absent, today's `model` is used as
  `{whispercpp, model}`; likewise `previewModel` for `engines.preview`. When the
  window changes an engine, it writes `engines` and removes `model`/`previewModel`
  so there's one source. Defaults change only after the phase 1 benchmark
  (`02-engines.md` §6).

**New:**
| key | default | allowed | meaning |
|---|---|---|---|
| `launchAtLogin` | `true` | `true`, `false` | Start the app at login |
| `typingSpeedWpm` | `40` | 10–200 | Your typing speed, for "time saved" in Statistics |
| `collectStats` | `true` | `true`, `false` | Record usage statistics (`05-statistics.md`) |

**No longer used:** `serverPort` (no server). It is accepted and ignored, so old
files stay valid; the window doesn't show it.

All other keys keep their meaning, defaults and allowed values. Meeting keys come
from the meeting design (`meetingsFolder`, `meetingFileName`, …).

## 3. The Settings window

A standard macOS settings window with a sidebar, as in the approved mockup.
SwiftUI. Opened from the menu (Settings…, ⌘,) or by launching the app again.

| section | contents |
|---|---|
| **General** | Launch at login, sounds, language, Open settings file, Open data folder |
| **Hotkeys** | Mode (toggle / hold), dictation hotkey, cancel key, add-word hotkey — each with a shortcut recorder (click, press the keys); conflicts shown inline |
| **Engines & Models** | The three task choices (engine + model pickers, with a note when the language isn't supported). A model list with state, size, Download / Delete and progress. `idleUnloadMinutes` |
| **Dictation** | Microphone (device list), style prompt (multi-line), refocus original app, restore clipboard, max recording length |
| **Overlay** | Show panel, live draft, and every `overlayStyle` key with fitting controls (position picker, sliders, color pickers, text fields), plus a **Preview** button that shows the panel with sample text |
| **Meetings** | Phase 3: the meeting keys, with a live example of the file name from `meetingFileName` |
| **Dictionary** | Terms (ordered list, drag to reorder, add/remove), replace rules (two-column table, add/remove/edit), drop phrases. Writes `dictionary.json` the same way (only on valid input) |
| **History & Privacy** | Save history, keep N days, Recent menu items, failed-audio hours, Open history, Clear history…, collect statistics, Clear statistics… |
| **Statistics** | `05-statistics.md` |

- Every control maps to one key; changing it saves at once (no Save button), as in
  macOS System Settings.
- Each control has a one-line hint, the same wording as the README table.
- Values outside the allowed range can't be entered (steppers/sliders clamp).

*Left to the builder:* exact layout, icons, control types where not listed.
