# Native app — Dictation (parity)

Part of the native app design; see `00-overview.md`.

Everything in today's README and `../2026-10-04-dictation-tool-design.md` (incl. the
§11 overlay addendum) works the same in the native app. This file lists how each
part is done natively and the few intended changes.

## 1. Hotkeys and modes

- Dictation hotkey (default ⌥Space), toggle and hold-to-talk modes, the 0.3 s
  short-hold discard, the 0.5 s short-recording discard, cancel key (default Esc)
  registered only while recording, presses ignored while transcribing,
  `maxRecordingSeconds` auto-stop — all as today.
- Add-word hotkey (default ⌃⌥D), as today.
- Carbon `RegisterEventHotKey` (gives press and release). The key-name format in
  `settings.json` stays the same (`{"mods": ["alt"], "key": "space"}`; key names as
  Hammerspoon used them), so existing files keep working.
- If a hotkey can't be registered, a notice and a ⚠ menu line say so (as today).

## 2. Recording

- `AVAudioEngine` input → converted to 16 kHz mono Float32, kept **in memory**. No
  temp WAV for a normal dictation (today's `$TMPDIR/dictation` files go away).
- The `microphone` setting picks the input device by name; if it isn't connected,
  the system default is used and the panel says so (as today). Device list in
  Settings and in the menu.
- If the device disappears mid-recording (Bluetooth off), recording continues on
  the default device if possible; otherwise it stops and transcribes what it has.
- Start / done / error sounds as today (`sounds`), using the same system sounds.
- The frontmost app is remembered at start for refocus and for statistics.

## 3. Recognition and paste

- On stop, the audio goes to the `dictation` engine (`02-engines.md`) with
  `language` and the prompt built as today (style prompt + `terms`, trimmed to the
  token budget). The result goes through today's post-processing.
- Empty result → "Nothing recognized", no paste (as today).
- The text is appended to `history.log` (same format, `saveHistory`, `historyDays`
  as today) **before** pasting.
- Paste: refocus the original app (`refocusOriginalApp`), save the clipboard, set the
  text, post ⌘V with `CGEvent`, restore the clipboard after ~0.5 s
  (`restoreClipboard`) — as today.
- On recognition failure, retry once; then the audio is written as WAV to
  `failed/` and kept for `failedAudioHours` (as today), and the notice says so.
- Model still loading when a recording stops: wait up to 60 s, as today.

## 4. Overlay panel and live draft

- A non-activating `NSPanel` that ignores the mouse, visible on all Spaces and over
  full-screen apps, on the screen with the focused window. States, texts and every
  `overlayStyle` key as today.
- Frequency meter computed with Accelerate (vDSP) from the in-memory audio.
- Live draft as today: every 2 s the last 20 s go to the `preview` engine, at most
  one request in flight, late results dropped, draft never pasted. With
  `livePreview` false or the preview model missing, the panel shows status and meter only.
- With `overlay` false, short notices appear instead (system notification or a small
  transient panel — builder's choice).

## 5. Dictionary and add-word

- `dictionary.json` format and rules unchanged; edits apply on save (file watched).
- Add-word: read the selection with a temporary ⌘C (clipboard restored), show a
  small input dialog with today's Ukrainian texts and parsing rules (`wrong = right`,
  up to 6 words selected, existing rule shown).
- The Dictionary can also be edited in Settings (`04-settings.md` §3).
- Ukrainian/Cyrillic case-insensitive whole-word matching uses Swift's Unicode-aware
  lowercasing; behaviour must match today's tests.

## 6. History

- `history.log` stays plain text in today's format, so old entries show up.
- Recent submenu (`historyMenuItems`), Open history, Clear history… (also clears
  failed audio; asks first) — as today.

## 7. Menu

Same icon states (🎙 ready · 🔴 recording · ⏳ transcribing · 🎙⚠ problem; a
template SF Symbol is fine if the states stay distinct) and the same items, with
these changes:

| today | native |
|---|---|
| Model ▸ | **Engine ▸** — lists downloaded engine+model pairs for dictation; full choice in Settings |
| Edit settings… | **Settings…** (⌘,) opens the Settings window. "Open settings file" moves to Settings → General |
| Edit dictionary… | stays (opens the file); the Dictionary tab is in Settings |
| Restart whisper server | **Reload models** |
| Quit dictation | **Quit** |
| — | **Statistics** opens Settings → Statistics |

Mode, Language and Microphone submenus stay.

## 8. Tests

- Pure logic ported from today's Lua tests to Swift tests (Swift Testing or XCTest),
  keeping the same cases: dictionary (replacements, prompt budget, hallucinations),
  settings validation and last-good behaviour, controller state machine, history
  parsing, add-word prompt and parsing, overlay layout logic, spectrum.
- The controller and paste/recording code are written against small protocols so
  the state machine is tested without audio or UI.
- Engine smoke test: a short committed fixture clip through each downloaded engine
  (skipped when the model is missing).
- `docs/manual-test-checklist.md` updated for the native app (adds: permissions
  survive a rebuild; Accessibility missing → text copied, notice shown; switching
  engines in Settings while idle and while recording).
- Success criteria from the original design still hold: stop-to-paste for a 30 s
  dictation ≤ ~6 s with `large-v3`, and not slower than today with the same model.
