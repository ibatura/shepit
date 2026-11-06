# Live Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A non-focusing floating panel shows recording state, elapsed time, a level meter and live draft text, then the final text, and disappears.

**Architecture:** Pure-Lua `wav.lua` reads the growing WAV (length from file size) to compute a level and cut 20 s snapshots. Pure-Lua `preview.lua` sends a snapshot every 2 s to a second `server.lua` instance running `large-v3-turbo`, reusing `transcriber.lua`. The controller emits state and text events to an injected `overlay` sink. `overlay.lua` renders them with `hs.canvas`.

**Tech Stack:** Lua 5.4 (Hammerspoon), hs.canvas, existing modules.

**Spec:** `docs/superpowers/specs/2026-10-04-dictation-tool-design.md` §11

## Global Constraints

- Overlay never takes focus: `canvasMouseEvents(false,false,false,false)`, no click callbacks, `clickActivating(false)`, level `"overlay"`, behaviour `{"canJoinAllSpaces","stationary","fullScreenAuxiliary"}`.
- WAV assumptions: 16 kHz, mono, 16-bit little-endian PCM, 44-byte header (`wav.HEADER = 44`, `wav.RATE = 16000`).
- Preview: interval `preview.INTERVAL = 2`, window `preview.WINDOW = 20` s, ≤ 1 request in flight, results after stop discarded.
- Preview server port = `serverPort + 2`; it uses the same idle-unload as the main server.
- New settings: `overlay` (bool, default true), `livePreview` (bool, default true), `previewModel` (enum of `config.MODELS`, default `"large-v3-turbo"`).
- Final text path unchanged; preview text is never pasted.
- Commit after every task, messages end with `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`.

## Review Focus

1. **Preview server missing or crashing** (turbo not downloaded, preview server dies) → dictation still works, the overlay shows status and level only, and no repeated error alerts. Owned by Task 4 (preview server errors are logged, not alerted) and Task 3 (preview errors are silent).
2. **Very short or brand-new recordings** (file < header, < 0.5 s of audio at a tick) → no crash, no request sent. Owned by Task 1 (unit tests) and Task 3 (unit test).
3. **Odd byte counts mid-write** (sox flushed half a sample) → snapshot length rounds down to whole samples. Owned by Task 1 (unit test).
4. **Hotkey pressed again while the "done" panel is still visible** → the new recording's panel replaces it immediately and the old hide timer doesn't hide it. Owned by Task 4 (overlay generation counter) and checked manually.
5. **Overlay disabled** → old behaviour (hs.alert notices) is fully preserved. Owned by Task 4 (the init wiring chooses the sink).

---

### Task 1: `wav.lua` — read a growing WAV

**Files:**
- Create: `src/dictation/wav.lua`
- Test: `tests/test_wav.lua`

**Interfaces:**
- Produces:
  - `wav.HEADER = 44`, `wav.RATE = 16000`
  - `wav.header(numSamples) -> string` (44-byte PCM header with correct sizes)
  - `wav.samplesInFile(size) -> integer` (`max(0, (size - 44) // 2)`)
  - `wav.rms(pcm) -> number` in 0..1 (pcm is a little-endian int16 string; returns 0 for empty input)
  - `wav.level(path, seconds) -> number` (RMS of the last `seconds` of audio; 0 if the file is missing or too short)
  - `wav.snapshot(src, dst, seconds) -> durationSeconds | nil, err` (writes the last `seconds` (or everything, if shorter) to `dst` as a valid WAV)

- [ ] **Step 1: Write the failing tests `tests/test_wav.lua`**

```lua
local wav = require("dictation.wav")

local function pcm(samples)
  local parts = {}
  for i, s in ipairs(samples) do parts[i] = string.pack("<i2", s) end
  return table.concat(parts)
end

local function writeRaw(path, data)
  local f = assert(io.open(path, "wb"))
  f:write(data)
  f:close()
end

local function readAll(path)
  local f = assert(io.open(path, "rb"))
  local d = f:read("a")
  f:close()
  return d
end

-- sox writes a header with placeholder sizes while recording
local function soxLikeHeader()
  return wav.header(0):sub(1, 4) .. string.pack("<I4", 0x7FFFF024) .. wav.header(0):sub(9, 40)
    .. string.pack("<I4", 0x7FFFF000)
end

test("header has correct sizes and format", function()
  local h = wav.header(16000)
  eq(#h, 44)
  eq(h:sub(1, 4), "RIFF")
  eq(string.unpack("<I4", h, 5), 36 + 32000)
  eq(h:sub(9, 16), "WAVEfmt ")
  eq({ string.unpack("<I4I2I2I4I4I2I2", h, 17) }, { 16, 1, 1, 16000, 32000, 2, 16, 37 })
  eq(h:sub(37, 40), "data")
  eq(string.unpack("<I4", h, 41), 32000)
end)

test("samplesInFile rounds down and never goes negative", function()
  eq(wav.samplesInFile(44), 0)
  eq(wav.samplesInFile(10), 0)
  eq(wav.samplesInFile(44 + 7), 3)
  eq(wav.samplesInFile(44 + 32000), 16000)
end)

test("rms of silence, full scale and empty", function()
  eq(wav.rms(pcm({ 0, 0, 0 })), 0)
  eq(wav.rms(""), 0)
  truthy(math.abs(wav.rms(pcm({ 32767, -32767 })) - 1) < 0.001)
  truthy(math.abs(wav.rms(pcm({ 16384, -16384 })) - 0.5) < 0.001)
end)

test("level reads only the tail of a growing file", function()
  local path = os.tmpname()
  local loud, quiet = {}, {}
  for i = 1, 1600 do quiet[i] = 0; loud[i] = 16384 end
  writeRaw(path, soxLikeHeader() .. pcm(loud) .. pcm(quiet))
  eq(wav.level(path, 0.1), 0)
  writeRaw(path, soxLikeHeader() .. pcm(quiet) .. pcm(loud))
  truthy(math.abs(wav.level(path, 0.1) - 0.5) < 0.001)
  os.remove(path)
end)

test("level of a missing or header-only file is 0", function()
  eq(wav.level("/nonexistent/x.wav", 0.1), 0)
  local path = os.tmpname()
  writeRaw(path, soxLikeHeader())
  eq(wav.level(path, 0.1), 0)
  os.remove(path)
end)

test("snapshot cuts the last N seconds into a valid wav", function()
  local src, dst = os.tmpname(), os.tmpname()
  local samples = {}
  for i = 1, 16000 * 3 do samples[i] = i % 1000 end
  writeRaw(src, soxLikeHeader() .. pcm(samples))
  eq(wav.snapshot(src, dst, 2), 2)
  local out = readAll(dst)
  eq(#out, 44 + 2 * 32000)
  eq(string.unpack("<I4", out, 41), 64000)
  eq(out:sub(45, 46), pcm({ samples[16001] }))
  os.remove(src); os.remove(dst)
end)

test("snapshot of a shorter file copies everything", function()
  local src, dst = os.tmpname(), os.tmpname()
  writeRaw(src, soxLikeHeader() .. pcm({ 1, 2, 3, 4 }))
  eq(wav.snapshot(src, dst, 20), 4 / 16000)
  eq(readAll(dst), wav.header(4) .. pcm({ 1, 2, 3, 4 }))
  os.remove(src); os.remove(dst)
end)

test("snapshot drops a half-written trailing byte", function()
  local src, dst = os.tmpname(), os.tmpname()
  writeRaw(src, soxLikeHeader() .. pcm({ 5, 6 }) .. "\1")
  eq(wav.snapshot(src, dst, 20), 2 / 16000)
  eq(readAll(dst), wav.header(2) .. pcm({ 5, 6 }))
  os.remove(src); os.remove(dst)
end)

test("snapshot reports a missing source", function()
  local d, err = wav.snapshot("/nonexistent/x.wav", os.tmpname(), 2)
  eq(d, nil)
  truthy(err)
end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test`
Expected: `tests/test_wav.lua (load error) … module 'dictation.wav' not found`.

- [ ] **Step 3: Write `src/dictation/wav.lua`**

```lua
-- Reads a 16 kHz mono 16-bit WAV while sox is still writing it.
-- sox leaves placeholder sizes in the header until it exits, so length comes from the file size.
local M = {}

M.HEADER = 44
M.RATE = 16000

function M.header(numSamples)
  local dataBytes = numSamples * 2
  return "RIFF" .. string.pack("<I4", 36 + dataBytes) .. "WAVEfmt "
    .. string.pack("<I4I2I2I4I4I2I2", 16, 1, 1, M.RATE, M.RATE * 2, 2, 16)
    .. "data" .. string.pack("<I4", dataBytes)
end

function M.samplesInFile(size)
  return math.max(0, (size - M.HEADER) // 2)
end

function M.rms(pcm)
  local n = #pcm // 2
  if n == 0 then return 0 end
  local sum = 0
  for i = 1, n * 2, 2 do
    local s = string.unpack("<i2", pcm, i)
    sum = sum + s * s
  end
  return math.min(1, math.sqrt(sum / n) / 32767)
end

-- Returns the last `seconds` of PCM bytes (whole samples only) and the sample count.
local function tail(path, seconds)
  local f, err = io.open(path, "rb")
  if not f then return nil, err end
  local total = M.samplesInFile(f:seek("end"))
  local count = math.min(total, math.floor(seconds * M.RATE))
  f:seek("set", M.HEADER + (total - count) * 2)
  local data = count > 0 and f:read(count * 2) or ""
  f:close()
  return data, count
end

function M.level(path, seconds)
  local data = tail(path, seconds)
  if not data then return 0 end
  return M.rms(data)
end

function M.snapshot(src, dst, seconds)
  local data, count = tail(src, seconds)
  if not data then return nil, count end
  local f, err = io.open(dst, "wb")
  if not f then return nil, err end
  f:write(M.header(count), data)
  f:close()
  return count / M.RATE
end

return M
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test`
Expected: `122 passed, 0 failed`; Python `OK`; `install tests passed`.

- [ ] **Step 5: Commit**

```bash
git add src/dictation/wav.lua tests/test_wav.lua
git commit -m "Add WAV reader for growing recordings

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Config fields and controller overlay events

**Files:**
- Modify: `src/dictation/config.lua` (`DEFAULT_SETTINGS`, `SETTING_CHECKS`)
- Modify: `examples/settings.json`
- Modify: `src/dictation/controller.lua`
- Test: `tests/test_config.lua`, `tests/test_controller.lua`

**Interfaces:**
- Produces:
  - Settings `overlay` (boolean, default `true`), `livePreview` (boolean, default `true`), `previewModel` (enum `config.MODELS`, default `"large-v3-turbo"`).
  - Controller dependency `deps.overlay` (optional; if it's nil, nothing is emitted) with the methods:
    - `overlay.recording(startedAt)` — called when recording starts
    - `overlay.transcribing()`
    - `overlay.done(text)` — final processed text that was pasted
    - `overlay.message(text)` — every controller notice (cancelled, too short, errors), **in addition to** `deps.notify`. The init wiring decides which one to show.
    - `overlay.hide()` — a silent short-hold discard
  - Controller emits `deps.onRecordingStart(path)` and `deps.onRecordingStop()` (both optional), used by preview in Task 3. `onRecordingStop` fires whenever the recording state ends (stop, cancel, discard, recorder failure).

- [ ] **Step 1: Write the failing config tests** — append to `tests/test_config.lua`:

```lua
test("overlay settings have defaults and are validated", function()
  local s = config.validateSettings({})
  eq(s.overlay, true)
  eq(s.livePreview, true)
  eq(s.previewModel, "large-v3-turbo")
  local bad, errs = config.validateSettings({ overlay = "yes", livePreview = 1, previewModel = "tiny" })
  eq(bad, nil)
  eq(#errs, 3)
end)
```

- [ ] **Step 2: Write the failing controller tests** — append to `tests/test_controller.lua`:

```lua
local function withOverlay()
  local events = {}
  local h = harness({
    overlay = {
      recording = function(t) events[#events + 1] = "recording " .. t end,
      transcribing = function() events[#events + 1] = "transcribing" end,
      done = function(text) events[#events + 1] = "done " .. text end,
      message = function(text) events[#events + 1] = "message " .. text end,
      hide = function() events[#events + 1] = "hide" end,
    },
    onRecordingStart = function(path) events[#events + 1] = "start " .. path end,
    onRecordingStop = function() events[#events + 1] = "stop" end,
  })
  return h, events
end

test("overlay: full dictation emits recording, transcribing, done", function()
  local h, events = withOverlay()
  h.now = 5
  h.ctl:hotkeyDown(); h.advance(1); h.ctl:hotkeyDown()
  h.transcribeCb(" Привіт ")
  eq(events, { "recording 5", "start /tmp/a.wav", "stop", "transcribing", "done Привіт" })
end)

test("overlay: cancel emits message and stop", function()
  local h, events = withOverlay()
  h.ctl:hotkeyDown(); h.advance(1); h.ctl:cancel()
  eq(events, { "recording 0", "start /tmp/a.wav", "stop", "message Cancelled" })
end)

test("overlay: silent short hold hides", function()
  local h, events = withOverlay()
  h.settings.mode = "hold"
  h.ctl:hotkeyDown(); h.advance(0.1); h.ctl:hotkeyUp()
  eq(events, { "recording 0", "start /tmp/a.wav", "stop", "hide" })
end)

test("overlay: empty result and errors become messages", function()
  local h, events = withOverlay()
  h.ctl:hotkeyDown(); h.advance(1); h.ctl:hotkeyDown()
  h.transcribeCb("  ")
  eq(events[#events], "message Nothing recognized")
  h.ctl:hotkeyDown(); h.advance(1); h.ctl:hotkeyDown()
  h.transcribeCb(nil, "boom")
  eq(events[#events], "message Transcription failed: boom")
end)

test("overlay: recorder failure emits stop and message", function()
  local h, events = withOverlay()
  h.ctl:hotkeyDown()
  h.ctl:recorderExited(1, "no mic")
  eq(events, { "recording 0", "start /tmp/a.wav", "stop", "message Recording failed: no mic" })
end)

test("overlay: start failure emits only a message", function()
  local h, events = withOverlay()
  h.recFails = "sox missing"
  h.ctl:hotkeyDown()
  eq(events, { "message Recording failed: sox missing" })
end)
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `make test`
Expected: the 7 new tests FAIL (`expected true, got nil` for the overlay setting; event lists that don't match). All other tests pass.

- [ ] **Step 4: Add the settings to `src/dictation/config.lua`**

In `M.DEFAULT_SETTINGS`, after `idleUnloadMinutes = 0,`, add:
```lua
  overlay = true,
  livePreview = true,
  previewModel = "large-v3-turbo",
```
In `SETTING_CHECKS`, after `idleUnloadMinutes = integer(0, 1440),`, add:
```lua
  overlay = kind("boolean"),
  livePreview = kind("boolean"),
  previewModel = enum(M.MODELS),
```

- [ ] **Step 5: Add the settings to `examples/settings.json`**

Replace the last line `  "idleUnloadMinutes": 0` with:
```json
  "idleUnloadMinutes": 0,
  "overlay": true,
  "livePreview": true,
  "previewModel": "large-v3-turbo"
```

- [ ] **Step 6: Emit events from `src/dictation/controller.lua`**

Add a helper after `Ctl:stopTimer`:
```lua
function Ctl:emit(name, ...)
  local sink = self.deps.overlay
  if sink and sink[name] then sink[name](...) end
end

function Ctl:notify(message)
  self.deps.notify(message)
  self:emit("message", message)
end

function Ctl:recordingEnded()
  if self.deps.onRecordingStop then self.deps.onRecordingStop() end
end
```
Then make these edits:
- Replace every `d.notify(` and `self.deps.notify(` call with `self:notify(`. There are 7 sites: start failure, discard message, timeout, transcription failed, nothing recognized, and the two that already go through `discard`. `discard` receives the message and calls `self:notify(message)`.
- In `Ctl:start`, after `self:setState("recording")`, add:
  ```lua
  self:emit("recording", self.rec.startedAt)
  if d.onRecordingStart then d.onRecordingStart(path) end
  ```
- In `Ctl:discard`, after `d.recorder.cancel()`, add `self:recordingEnded()`. Replace `if message then d.notify(message) end` with:
  ```lua
  if message then self:notify(message) else self:emit("hide") end
  ```
- In `Ctl:stop`, after `d.bindCancel(false)` (the transcribing path), add `self:recordingEnded()`. After `self:setState("transcribing")`, add `self:emit("transcribing")`.
- In `Ctl:finish`, after `d.paste(result, rec.app)`, add `self:emit("done", result)`.

- [ ] **Step 7: Run tests to verify they pass**

Run: `make test`
Expected: `129 passed, 0 failed` (122 + 1 config + 6 controller); the examples consistency test still passes; Python `OK`; `install tests passed`.

- [ ] **Step 8: Commit**

```bash
git add src/dictation/config.lua examples/settings.json src/dictation/controller.lua tests/test_config.lua tests/test_controller.lua
git commit -m "Add overlay settings and controller overlay events

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: `preview.lua` — periodic draft transcription

**Files:**
- Create: `src/dictation/preview.lua`
- Test: `tests/test_preview.lua`

**Interfaces:**
- Consumes: `wav.snapshot` (Task 1); a transcriber with the same `:transcribe(path, cb)` signature as Task 8 of the main plan.
- Produces:
  - `preview.INTERVAL = 2`, `preview.WINDOW = 20`, `preview.MIN_SECONDS = 0.5`
  - `preview.new(deps) -> p` with `p:start(wavPath)` and `p:stop()`.
  - `deps`:
    - `enabled() -> bool`
    - `every(sec, fn) -> timer` (`timer:stop()`)
    - `snapshot(src, dst, seconds) -> duration | nil`
    - `snapshotPath() -> path`
    - `transcribe(path, cb(text, err))`
    - `process(text) -> text`
    - `onText(text)`
    - `removeFile(path)`
- Behaviour:
  - `start` does nothing if `enabled()` is false.
  - Every `INTERVAL` s: skip if a request is in flight, or if the snapshot is shorter than `MIN_SECONDS`.
  - Results are processed; an empty result is ignored, otherwise it goes to `onText`. Errors are ignored silently.
  - Once `stop` has been called, results are discarded (a session counter) and the snapshot file is removed.

- [ ] **Step 1: Write the failing tests `tests/test_preview.lua`**

```lua
local preview = require("dictation.preview")

local function harness(opts)
  local h = { timers = {}, texts = {}, calls = {}, removed = {}, duration = 3, enabled = true }
  h.p = preview.new {
    enabled = function() return h.enabled end,
    every = function(sec, fn)
      local t = { sec = sec, fn = fn }
      function t:stop() self.stopped = true end
      h.timers[#h.timers + 1] = t
      return t
    end,
    snapshot = function(src, dst, seconds)
      h.lastSnap = { src, dst, seconds }
      return h.duration
    end,
    snapshotPath = function() return "/tmp/snap.wav" end,
    transcribe = function(path, cb) h.calls[#h.calls + 1] = cb end,
    process = function(t) return (t:gsub("^%s+", ""):gsub("%s+$", "")) end,
    onText = function(t) h.texts[#h.texts + 1] = t end,
    removeFile = function(p) h.removed[#h.removed + 1] = p end,
  }
  function h.tick() h.timers[#h.timers].fn() end
  return h
end

test("start schedules ticks every INTERVAL", function()
  local h = harness()
  h.p:start("/tmp/a.wav")
  eq(#h.timers, 1)
  eq(h.timers[1].sec, preview.INTERVAL)
end)

test("tick snapshots the last WINDOW seconds and shows processed text", function()
  local h = harness()
  h.p:start("/tmp/a.wav")
  h.tick()
  eq(h.lastSnap, { "/tmp/a.wav", "/tmp/snap.wav", preview.WINDOW })
  h.calls[1]("  Привіт  ")
  eq(h.texts, { "Привіт" })
end)

test("tick is skipped while a request is in flight", function()
  local h = harness()
  h.p:start("/tmp/a.wav")
  h.tick(); h.tick()
  eq(#h.calls, 1)
  h.calls[1]("a")
  h.tick()
  eq(#h.calls, 2)
end)

test("too-short snapshot sends nothing", function()
  local h = harness()
  h.duration = 0.3
  h.p:start("/tmp/a.wav")
  h.tick()
  eq(#h.calls, 0)
  h.duration = nil
  h.tick()
  eq(#h.calls, 0)
end)

test("empty results and errors are ignored", function()
  local h = harness()
  h.p:start("/tmp/a.wav")
  h.tick(); h.calls[1]("   ")
  h.tick(); h.calls[2](nil, "server down")
  eq(h.texts, {})
  h.tick()
  eq(#h.calls, 3)
end)

test("results after stop are discarded; stop cleans up", function()
  local h = harness()
  h.p:start("/tmp/a.wav")
  h.tick()
  h.p:stop()
  eq(h.timers[1].stopped, true)
  eq(h.removed, { "/tmp/snap.wav" })
  h.calls[1]("late")
  eq(h.texts, {})
end)

test("result from a previous recording does not leak into the next", function()
  local h = harness()
  h.p:start("/tmp/a.wav")
  h.tick()
  local old = h.calls[1]
  h.p:stop()
  h.p:start("/tmp/b.wav")
  old("old text")
  eq(h.texts, {})
  h.tick()
  eq(#h.calls, 2) -- not blocked by the stale in-flight request
end)

test("disabled preview does nothing", function()
  local h = harness()
  h.enabled = false
  h.p:start("/tmp/a.wav")
  eq(#h.timers, 0)
  h.p:stop()
end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test`
Expected: `tests/test_preview.lua (load error) … module 'dictation.preview' not found`.

- [ ] **Step 3: Write `src/dictation/preview.lua`**

```lua
-- Draft text while recording: every few seconds, transcribe the tail of the growing WAV.
local M = {}

M.INTERVAL = 2
M.WINDOW = 20
M.MIN_SECONDS = 0.5

local P = {}
P.__index = P

function M.new(deps)
  return setmetatable({ deps = deps, session = 0 }, P)
end

function P:start(wavPath)
  self:stop()
  if not self.deps.enabled() then return end
  self.session = self.session + 1
  self.busy = false
  local session = self.session
  self.timer = self.deps.every(M.INTERVAL, function() self:tick(session, wavPath) end)
end

function P:tick(session, wavPath)
  local d = self.deps
  if session ~= self.session or self.busy then return end
  local snap = d.snapshotPath()
  local duration = d.snapshot(wavPath, snap, M.WINDOW)
  if not duration or duration < M.MIN_SECONDS then return end
  self.busy = true
  d.transcribe(snap, function(text)
    if session ~= self.session then return end
    self.busy = false
    if not text then return end
    local result = d.process(text)
    if result ~= "" then d.onText(result) end
  end)
end

function P:stop()
  if not self.timer then return end
  self.timer:stop()
  self.timer = nil
  self.session = self.session + 1
  self.busy = false
  self.deps.removeFile(self.deps.snapshotPath())
end

return M
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test`
Expected: `137 passed, 0 failed`; Python `OK`; `install tests passed`.

- [ ] **Step 5: Commit**

```bash
git add src/dictation/preview.lua tests/test_preview.lua
git commit -m "Add live preview scheduler

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Overlay panel and wiring

**Files:**
- Create: `src/dictation/overlay.lua`
- Modify: `src/dictation/paths.lua` (add `previewWav`)
- Modify: `src/dictation/platform.lua` (add `every`)
- Modify: `src/dictation/init.lua`
- Test: `tests/test_overlay.lua` (pure formatting helpers), `tests/test_paths.lua`

**Interfaces:**
- Consumes: controller overlay events (Task 2), `preview.new` (Task 3), `wav.level` (Task 1), `server.new` and `transcriber.new` (main plan).
- Produces:
  - `overlay.formatElapsed(seconds) -> "m:ss"`
  - `overlay.tailText(text, maxChars) -> string` (keeps the end of the text, starting at a word boundary, with a leading `…` when cut)
  - `overlay.meterWidth(level, maxWidth) -> number` (perceptual scale `min(1, sqrt(level) * 2.5)`)
  - `overlay.new{ every, after, level } -> o` with the controller sink methods `recording(startedAt)`, `transcribing()`, `done(text)`, `message(text)`, `hide()`, plus `o.preview(text)`, `o.setWav(path)` and `o.delete()`. Requires `hs`.
  - `paths.previewWav = "/tmp/dictation-preview.wav"`
  - `platform.every(sec, fn) -> {stop=fn}`

- [ ] **Step 1: Write the failing tests `tests/test_overlay.lua`**

```lua
local overlay = require("dictation.overlay")

test("formatElapsed", function()
  eq(overlay.formatElapsed(0), "0:00")
  eq(overlay.formatElapsed(7.9), "0:07")
  eq(overlay.formatElapsed(65), "1:05")
  eq(overlay.formatElapsed(-1), "0:00")
end)

test("tailText keeps short text and cuts long text at a word boundary", function()
  eq(overlay.tailText("Привіт світ", 50), "Привіт світ")
  eq(overlay.tailText("один два три чотири", 12), "…три чотири")
  eq(overlay.tailText("", 10), "")
end)

test("tailText counts characters, not bytes", function()
  local s = string.rep("ї", 30)
  eq(overlay.tailText(s, 40), s)
end)

test("tailText with no spaces cuts by characters", function()
  eq(overlay.tailText("абвгдежзик", 5), "…жзик")
end)

test("meterWidth is clamped and perceptual", function()
  eq(overlay.meterWidth(0, 100), 0)
  eq(overlay.meterWidth(1, 100), 100)
  truthy(overlay.meterWidth(0.04, 100) >= 49 and overlay.meterWidth(0.04, 100) <= 51)
end)
```

Append to `tests/test_paths.lua`:
```lua
test("previewWav path", function()
  eq(paths.previewWav, "/tmp/dictation-preview.wav")
end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test`
Expected: `tests/test_overlay.lua (load error) … module 'dictation.overlay' not found`; the `previewWav path` test FAILS with `expected "/tmp/dictation-preview.wav", got nil`.

- [ ] **Step 3: Add `M.previewWav` to `src/dictation/paths.lua`**

After `M.failedDir = …`, add:
```lua
M.previewWav = "/tmp/dictation-preview.wav"
```

- [ ] **Step 4: Write `src/dictation/overlay.lua`**

```lua
-- Floating status panel. Never takes focus. Formatting helpers are pure; new() requires hs.
local M = {}

M.WIDTH, M.HEIGHT = 560, 96
M.BOTTOM_MARGIN = 80
M.DONE_SECONDS = 1.0
M.MESSAGE_SECONDS = 2.5
M.TAIL_CHARS = 120

function M.formatElapsed(seconds)
  local s = math.max(0, math.floor(seconds))
  return string.format("%d:%02d", s // 60, s % 60)
end

function M.tailText(text, maxChars)
  local len = utf8.len(text) or #text
  if len <= maxChars then return text end
  local keep = maxChars - 1
  local cut = text:sub(utf8.offset(text, len - keep + 1))
  local word = cut:match("^%S*%s+(.+)$")
  return "…" .. (word or cut)
end

function M.meterWidth(level, maxWidth)
  return math.floor(math.min(1, math.sqrt(level) * 2.5) * maxWidth + 0.5)
end

local WHITE = { white = 1, alpha = 1 }
local DIM = { white = 1, alpha = 0.65 }

function M.new(deps)
  local o = {}
  local canvas, ticker, hideTimer, wavPath, startedAt
  local gen, state, previewText = 0, "hidden", ""

  local function frame()
    local screen = hs.screen.mainScreen():frame()
    return {
      x = screen.x + (screen.w - M.WIDTH) / 2,
      y = screen.y + screen.h - M.HEIGHT - M.BOTTOM_MARGIN,
      w = M.WIDTH, h = M.HEIGHT,
    }
  end

  local function ensureCanvas()
    if canvas then return end
    canvas = hs.canvas.new(frame())
    canvas:level("overlay")
    canvas:behavior({ "canJoinAllSpaces", "stationary", "fullScreenAuxiliary" })
    canvas:clickActivating(false)
    canvas:canvasMouseEvents(false, false, false, false)
  end

  local function render(title, body, level)
    ensureCanvas()
    canvas:frame(frame())
    local elements = {
      { type = "rectangle", action = "fill", fillColor = { white = 0.08, alpha = 0.88 },
        roundedRectRadii = { xRadius = 14, yRadius = 14 } },
      { type = "text", text = title, textColor = WHITE, textSize = 15,
        frame = { x = 18, y = 12, w = M.WIDTH - 200, h = 22 } },
      { type = "text", text = body or "", textColor = DIM, textSize = 14,
        frame = { x = 18, y = 40, w = M.WIDTH - 36, h = 48 } },
    }
    if level then
      local maxW = 150
      elements[#elements + 1] = { type = "rectangle", action = "fill",
        fillColor = { white = 1, alpha = 0.15 },
        roundedRectRadii = { xRadius = 3, yRadius = 3 },
        frame = { x = M.WIDTH - maxW - 18, y = 19, w = maxW, h = 8 } }
      elements[#elements + 1] = { type = "rectangle", action = "fill",
        fillColor = { red = 1, green = 0.27, blue = 0.27, alpha = 0.95 },
        roundedRectRadii = { xRadius = 3, yRadius = 3 },
        frame = { x = M.WIDTH - maxW - 18, y = 19, w = math.max(2, M.meterWidth(level, maxW)), h = 8 } }
    end
    canvas:replaceElements(elements)
    canvas:show()
  end

  local function stopTimers()
    if ticker then ticker.stop(); ticker = nil end
    if hideTimer then hideTimer.stop(); hideTimer = nil end
  end

  local function drawRecording()
    local level = wavPath and deps.level(wavPath, 0.1) or 0
    local elapsed = M.formatElapsed(hs.timer.secondsSinceEpoch() - startedAt)
    render("🔴  Слухаю · " .. elapsed, M.tailText(previewText, M.TAIL_CHARS), level)
  end

  local function hideAfter(seconds)
    local myGen = gen
    hideTimer = deps.after(seconds, function()
      if myGen == gen then o.hide() end
    end)
  end

  function o.setWav(path) wavPath = path end

  function o.recording(t)
    gen = gen + 1
    stopTimers()
    state, startedAt, previewText = "recording", t, ""
    drawRecording()
    ticker = deps.every(0.1, drawRecording)
  end

  function o.preview(text)
    previewText = text
    if state == "recording" then drawRecording()
    elseif state == "transcribing" then o.transcribing() end
  end

  function o.transcribing()
    stopTimers()
    state = "transcribing"
    render("⏳  Розпізнаю…", M.tailText(previewText, M.TAIL_CHARS))
  end

  function o.done(text)
    gen = gen + 1
    stopTimers()
    state = "done"
    render("✓  Готово", M.tailText(text, M.TAIL_CHARS))
    hideAfter(M.DONE_SECONDS)
  end

  function o.message(text)
    gen = gen + 1
    stopTimers()
    state = "message"
    render(text, "")
    hideAfter(M.MESSAGE_SECONDS)
  end

  function o.hide()
    stopTimers()
    state, wavPath = "hidden", nil
    if canvas then canvas:hide() end
  end

  function o.delete()
    o.hide()
    if canvas then canvas:delete(); canvas = nil end
  end

  return o
end

return M
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `make test`
Expected: `143 passed, 0 failed` (137 + 5 overlay + 1 paths); Python `OK`; `install tests passed`.

- [ ] **Step 6: Add `every` to `src/dictation/platform.lua`**

After the `M.after` function, add:
```lua
function M.every(sec, fn)
  local timer = hs.timer.doEvery(sec, fn)
  live[timer] = true
  return {
    stop = function()
      live[timer] = nil
      timer:stop()
    end,
  }
end
```

- [ ] **Step 7: Wire it up in `src/dictation/init.lua`**

1. Add the requires next to the others:
   ```lua
   local overlay = require("dictation.overlay")
   local preview = require("dictation.preview")
   local wav = require("dictation.wav")
   ```
2. Add `panel, previewServer, livePreview` to the `local menu, hotkey, …` line.
3. In `M.start()`, after the `trans = transcriber.new{…}` block, add:
   ```lua
   -- second, faster server for draft text while speaking
   local function previewSettings()
     local s = M.store.settings
     return setmetatable({ model = s.previewModel, serverPort = s.serverPort + 2 }, { __index = s })
   end
   local function previewWanted()
     local s = M.store.settings
     return s.overlay and s.livePreview and platform.fileExists(paths.model(s.previewModel))
   end
   previewServer = server.new {
     settings = previewSettings, paths = paths, threads = platform.perfCores(),
     fileExists = platform.fileExists, killStale = platform.killStale,
     spawn = platform.spawn, httpGet = platform.httpGet, after = platform.after,
     onStatus = function(status, detail)
       if status == "error" then print("dictation: preview server: " .. tostring(detail)) end
     end,
   }
   local previewTrans = transcriber.new {
     server = previewServer, runCurl = platform.runCurl, settings = settings, decode = hs.json.decode,
     prompt = function()
       return dictionary.buildPrompt(M.store.settings.stylePrompt, M.store.dictionary.terms, PROMPT_TOKENS)
     end,
   }
   panel = overlay.new { every = platform.every, after = platform.after, level = wav.level }
   livePreview = preview.new {
     enabled = function() return previewWanted() and previewServer.status == "ready" end,
     every = platform.every,
     snapshot = wav.snapshot,
     snapshotPath = function() return paths.previewWav end,
     transcribe = function(path, cb) previewTrans:transcribe(path, cb) end,
     process = function(text) return dictionary.process(text, M.store.dictionary) end,
     onText = function(text) panel.preview(text) end,
     removeFile = function(path) os.remove(path) end,
   }
   ```
4. In the `controller.new{…}` dependencies:
   - Replace `notify = function(msg) alert(msg) end,` with:
     ```lua
     notify = function(msg) if not M.store.settings.overlay then alert(msg) end end,
     overlay = setmetatable({}, { __index = function(_, name)
       return function(...) if M.store.settings.overlay then panel[name](...) end end
     end }),
     onRecordingStart = function(path)
       if M.store.settings.overlay then panel.setWav(path) end
       if previewWanted() then previewServer:ensure(function() end) end
       livePreview:start(path)
     end,
     onRecordingStop = function() livePreview:stop() end,
     ```
5. After `M.srv:start()` at the end of `M.start()`, add:
   ```lua
   if previewWanted() then previewServer:start() end
   ```
6. In `reloadConfig`, after the main-server restart check, add:
   ```lua
   if before.previewModel ~= after.previewModel or before.serverPort ~= after.serverPort
       or before.livePreview ~= after.livePreview or before.overlay ~= after.overlay then
     previewServer:stop()
     if previewWanted() then previewServer:start() end
   end
   ```
7. In `M.stop()`, before `M.srv:stop()`, add:
   ```lua
   if livePreview then livePreview:stop() end
   if panel then panel.delete() end
   if previewServer then previewServer:stop() end
   panel, livePreview, previewServer = nil, nil, nil
   ```

- [ ] **Step 8: Compile-check and test**

Run: `for f in src/dictation/*.lua; do /opt/homebrew/opt/lua@5.4/bin/luac -p "$f" || exit 1; done && echo OK && make test`
Expected: `OK`, then `143 passed, 0 failed`; Python `OK`; `install tests passed`.

- [ ] **Step 9: Live check in Hammerspoon**

Reload with `hs -c 'hs.reload()'` (or 🔨 → Reload Config). Then:
- `pgrep -fl whisper-server` shows two processes, on ports 8178 and 8180.
- The human partner presses ⌥Space in TextEdit and speaks for about 8 s.
  - The panel appears at the bottom centre with `🔴 Слухаю · 0:0x` and a moving level bar.
  - Draft text appears after about 2–4 s.
  - TextEdit keeps focus: the text cursor still blinks there.
- Stop: the panel shows `⏳ Розпізнаю…`, then `✓ Готово` with the final text, and disappears after 1 s. The text is pasted in TextEdit.
- Press Esc while recording: the panel shows `Cancelled` for about 2.5 s.
- Set `"overlay": false` in settings.json and save. The next dictation shows no panel and uses `hs.alert` notices as before. Then set it back to `true`.

- [ ] **Step 10: Update README** — add rows to the settings table:

```markdown
| `overlay` | `true` | Show a floating panel while recording: state, timer, level and draft text. It never takes focus |
| `livePreview` | `true` | Show draft text while you speak (needs `previewModel` downloaded; uses ~2 GB extra memory) |
| `previewModel` | `"large-v3-turbo"` | Faster model used only for the draft text; the pasted text always uses `model` |
```

- [ ] **Step 11: Commit**

```bash
git add src/dictation/overlay.lua src/dictation/paths.lua src/dictation/platform.lua src/dictation/init.lua tests/test_overlay.lua tests/test_paths.lua README.md
git commit -m "Add live overlay panel with draft text preview

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```
