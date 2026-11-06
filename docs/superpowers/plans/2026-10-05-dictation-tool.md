# Dictation Tool Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A local macOS dictation tool: a hotkey records speech (Ukrainian with embedded English terms), a local whisper.cpp server transcribes it, and the text is pasted into the active app.

**Architecture:** Hammerspoon (Lua) owns hotkeys, menu bar, clipboard and process management. sox (`rec`) records 16 kHz mono WAV. A locally built `whisper-server` (whisper.cpp v1.9.4, Metal) keeps `ggml-large-v3` resident and serves `/inference` on 127.0.0.1. Pure-logic Lua modules (text processing, config, state machine) are unit-tested with plain Lua 5.4; Hammerspoon glue modules are verified manually in the Hammerspoon console.

**Tech Stack:** Lua 5.4 (Hammerspoon 1.1.x runtime), whisper.cpp v1.9.4 built with cmake, sox, curl, Python 3 (accuracy harness only, stdlib), Bash (install scripts).

**Spec:** `docs/superpowers/specs/2026-10-04-dictation-tool-design.md`

## Global Constraints

- macOS on Apple Silicon (dev machine: M1 Pro, 32 GB). Everything runs locally; the only network use is install-time downloads.
- Default model `large-v3`; optional `large-v3-turbo`. Model files: `ggml-<model>.bin` in `~/.local/share/dictation/models/`.
- VAD model: `ggml-silero-v6.2.0.bin` in the same models dir.
- `whisper-server` is built from source, tag `v1.9.4`, into `~/.local/share/dictation/bin/whisper-server`. (Deviation from spec §2 "brew install whisper-cpp": the Homebrew formula is built with `-DWHISPER_BUILD_SERVER=OFF` and ships no server binary.)
- Server binds `127.0.0.1` only; default port `8178`; harness uses `8179`.
- Server flags: `-m <model> --host 127.0.0.1 --port <port> --vad --vad-model <vad> -nt -sns`.
- Inference request fields: `file`, `language` (`uk`|`en`|`auto`), `prompt`, `temperature=0.0`, `response_format=json`; response JSON key `text`, errors in key `error`.
- User files: `~/.config/dictation/settings.json`, `~/.config/dictation/dictionary.json` (JSON only). History: `~/.local/share/dictation/history.log`. Temp audio: `/tmp/dictation-*.wav`.
- Lua modules live under `src/dictation/` and are required as `dictation.<name>`. Pure modules must not reference the global `hs` at load time.
- Unit tests run with Homebrew `lua@5.4` via a bundled minimal runner (`tests/run.lua`) — no busted/luarocks dependency. (Deviation from spec §8 "busted": avoids luarocks/Lua-version friction; same coverage.)
- Hotkey modes: `"toggle"` and `"hold"`. Hold shorter than 0.3 s is discarded silently; recordings shorter than 0.5 s are discarded with "Recording too short".
- Prompt token budget: 200 (whisper keeps ~224); estimate 3 tokens per word containing non-ASCII, 1.5 per ASCII word; terms dropped from the end.
- Clipboard restore delay is 1.0 s (spec said ~0.5 s) because Electron apps read the pasteboard late; transcription watchdog is 120 s and model-ready timeout is 120 s (spec said 60 s) to cover a cold 3 GB model load.
- Menu item is "Quit dictation" (stops the tool, not Hammerspoon).
- Commit after every task. Commit messages end with `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`.

## Review Focus

1. **Slow apps read the clipboard after it's restored** (Electron apps like Slack/VS Code) → the user expects the dictated text, not their old clipboard, to be pasted. Owned by Task 10 (`paster.RESTORE_DELAY = 1.0`, skip restore if the clipboard changed) and checked in Task 13 scenarios 5 and 7.
2. **Unusual characters in whisper output** (invalid UTF-8 fragments, «guillemets», apostrophes `'`/`ʼ`/`’` inside Ukrainian words like «з'їв», emoji) → processing must never crash and must not replace inside words. Owned by Tasks 3 and 4 (unit tests).
3. **Menu change while settings.json is malformed** → the user's broken file must not be silently overwritten with last-good values; the change is refused with an explanation. Owned by Task 5 (unit test).
4. **Server hangs or callback never fires** → the icon must not stay ⏳ forever; a watchdog returns to idle with "Transcription timed out" and late results are ignored. Owned by Task 6 (unit test).
5. **Key repeat and rapid presses** (holding the key in hold mode, pressing during ⏳, toggling mode mid-recording) → no duplicate recordings, no stuck states. Owned by Task 6 (unit tests).

## File Structure

```
.gitignore
Makefile                         make test → Lua unit tests + Python harness tests
README.md                        install, permissions, usage, every config field
examples/settings.json           default settings (copied by installer)
examples/dictionary.json         sample dictionary (copied by installer)
scripts/build-whisper.sh         clone v1.9.4, build static Metal whisper-server
scripts/download-models.sh       download + SHA-256 verify models
scripts/install.sh               brew deps, build, models, config, Hammerspoon loader
scripts/uninstall.sh             reverse install (keeps user data unless --purge)
src/dictation/init.lua           Hammerspoon entry: wiring, hotkeys, lifecycle   (hs)
src/dictation/paths.lua          all filesystem locations                        (pure)
src/dictation/utf8util.lua       Cyrillic-aware lower(), word-char tests         (pure)
src/dictation/dictionary.lua     prompt builder, replacements, hallucination strip (pure)
src/dictation/config.lua         defaults, validation, store with last-good      (pure, io injected)
src/dictation/controller.lua     state machine for toggle/hold/cancel            (pure, deps injected)
src/dictation/history.lua        append transcripts to history.log               (pure Lua io)
src/dictation/menubar.lua        buildMenu (pure) + hs.menubar glue              (mixed)
src/dictation/server.lua         spawn/monitor whisper-server                    (hs)
src/dictation/transcriber.lua    curl multipart POST to /inference               (hs)
src/dictation/recorder.lua       sox rec start/stop/cancel                       (hs)
src/dictation/paster.lua         refocus, clipboard, ⌘V, restore                 (hs)
src/dictation/platform.lua       hs.* wrappers injected into pure modules        (hs)
tests/run.lua                    minimal test runner (test/eq globals)
tests/test_*.lua                 unit tests for pure modules
tests/install_test.sh            install/uninstall against a temp HOME
docs/manual-test-checklist.md    manual acceptance scenarios + results
tools/accuracy/sentences.txt     sentences for the user to read
tools/accuracy/record.sh         records reference clips into recordings/
tools/accuracy/evaluate.py       WER + Latin-term hit rate per model/prompt variant
tools/accuracy/test_evaluate.py  unit tests for evaluate.py pure functions
```

---

### Task 1: Build whisper-server and download models

**Files:**
- Create: `.gitignore`
- Create: `scripts/build-whisper.sh`
- Create: `scripts/download-models.sh`
- Modify: `docs/superpowers/specs/2026-10-04-dictation-tool-design.md` (Dependencies paragraph in §2)

**Interfaces:**
- Produces: executable `~/.local/share/dictation/bin/whisper-server`; files `~/.local/share/dictation/models/ggml-large-v3.bin`, `ggml-silero-v6.2.0.bin`, optionally `ggml-large-v3-turbo.bin`. Both scripts are idempotent and are called by `scripts/install.sh` (Task 11).

- [ ] **Step 1: Create `.gitignore`**

```gitignore
.DS_Store
tools/accuracy/recordings/
tools/accuracy/__pycache__/
```

- [ ] **Step 2: Install build dependency**

Run: `brew list cmake >/dev/null 2>&1 || brew install cmake`
Expected: cmake available (`cmake --version` prints 4.x).

- [ ] **Step 3: Write `scripts/build-whisper.sh`**

```bash
#!/usr/bin/env bash
# Build whisper-server from source. The Homebrew whisper-cpp formula is built
# with WHISPER_BUILD_SERVER=OFF, so it does not ship the server binary.
set -euo pipefail

VERSION="v1.9.4"
DATA="$HOME/.local/share/dictation"
SRC="$DATA/src/whisper.cpp"
BIN="$DATA/bin"

if [[ -x "$BIN/whisper-server" && -f "$BIN/.version" && "$(cat "$BIN/.version")" == "$VERSION" ]]; then
  echo "whisper-server $VERSION already built"
  exit 0
fi

command -v cmake >/dev/null || { echo "cmake is missing: brew install cmake" >&2; exit 1; }

rm -rf "$SRC"
mkdir -p "$(dirname "$SRC")" "$BIN"
git clone --depth 1 --branch "$VERSION" https://github.com/ggml-org/whisper.cpp "$SRC"

cmake -S "$SRC" -B "$SRC/build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DWHISPER_BUILD_EXAMPLES=ON \
  -DWHISPER_BUILD_SERVER=ON \
  -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_SDL2=OFF \
  -DGGML_METAL=ON \
  -DGGML_METAL_EMBED_LIBRARY=ON
cmake --build "$SRC/build" --config Release -j --target whisper-server

cp "$SRC/build/bin/whisper-server" "$BIN/whisper-server"
echo "$VERSION" > "$BIN/.version"
echo "built $BIN/whisper-server"
```

- [ ] **Step 4: Run the build**

Run: `chmod +x scripts/build-whisper.sh && scripts/build-whisper.sh && otool -L ~/.local/share/dictation/bin/whisper-server`
Expected: ends with `built .../whisper-server`; `otool -L` lists only system libraries/frameworks (Metal, Accelerate, libc++, libSystem) — no `libwhisper`/`libggml` dylibs, proving the static build.
Run again: `scripts/build-whisper.sh` → prints `whisper-server v1.9.4 already built`.

- [ ] **Step 5: Write `scripts/download-models.sh`**

```bash
#!/usr/bin/env bash
# Download whisper models with SHA-256 verification.
# Usage: download-models.sh [--with-turbo]
set -euo pipefail

DIR="$HOME/.local/share/dictation/models"
HF="https://huggingface.co"
mkdir -p "$DIR"

fetch() { # file-name url sha256
  local name="$1" url="$2" sha="$3" dest="$DIR/$1"
  if [[ -f "$dest" ]] && echo "$sha  $dest" | shasum -a 256 -c --status; then
    echo "ok   $name"
    return
  fi
  echo "get  $name"
  curl -fL --retry 3 -C - -o "$dest.part" "$url"
  if ! echo "$sha  $dest.part" | shasum -a 256 -c --status; then
    rm -f "$dest.part"
    echo "checksum mismatch for $name — run again to re-download" >&2
    exit 1
  fi
  mv "$dest.part" "$dest"
}

fetch ggml-large-v3.bin \
  "$HF/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin" \
  64d182b440b98d5203c4f9bd541544d84c605196c4f7b845dfa11fb23594d1e2
fetch ggml-silero-v6.2.0.bin \
  "$HF/ggml-org/whisper-vad/resolve/main/ggml-silero-v6.2.0.bin" \
  2aa269b785eeb53a82983a20501ddf7c1d9c48e33ab63a41391ac6c9f7fb6987

if [[ "${1:-}" == "--with-turbo" ]]; then
  fetch ggml-large-v3-turbo.bin \
    "$HF/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin" \
    1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69
fi
```

- [ ] **Step 6: Download models (turbo too, for the accuracy comparison in Task 2)**

Run: `chmod +x scripts/download-models.sh && scripts/download-models.sh --with-turbo`
Expected: three `get` lines followed by curl progress; no checksum error. Run again → three `ok` lines.

- [ ] **Step 7: Smoke-test the server with the bundled JFK sample**

Run:
```bash
D=~/.local/share/dictation
$D/bin/whisper-server -m $D/models/ggml-large-v3.bin --host 127.0.0.1 --port 8179 \
  --vad --vad-model $D/models/ggml-silero-v6.2.0.bin -nt -sns >/tmp/ws.log 2>&1 &
WS=$!
until curl -sf http://127.0.0.1:8179/health; do sleep 1; done; echo
curl -sS -F file=@$D/src/whisper.cpp/samples/jfk.wav --form-string response_format=json \
  --form-string language=en --form-string temperature=0.0 http://127.0.0.1:8179/inference
kill $WS
```
Expected: health prints `{"status":"ok"}`; inference prints JSON whose `text` contains `ask not what your country can do for you`. If `--vad` flags are rejected, check `/tmp/ws.log` and fix the flag names in the Global Constraints before continuing.

- [ ] **Step 8: Update the spec's dependency note**

In `docs/superpowers/specs/2026-10-04-dictation-tool-design.md` §2 "Dependencies", replace the line
`` `brew install whisper-cpp sox`, `brew install --cask hammerspoon`. ``
with
`` `brew install sox cmake`, `brew install --cask hammerspoon`. `whisper-server` is built from whisper.cpp source (tag v1.9.4) because the Homebrew formula does not include it. ``
and replace `Silero VAD model for whisper.cpp (~2 MB)` with `` Silero VAD model `ggml-silero-v6.2.0.bin` (~1 MB) ``.

- [ ] **Step 9: Commit**

```bash
git add .gitignore scripts/build-whisper.sh scripts/download-models.sh docs/superpowers/specs/2026-10-04-dictation-tool-design.md
git commit -m "Add whisper-server build and model download scripts

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Accuracy harness (validates the language approach before building the tool)

**Files:**
- Create: `tools/accuracy/sentences.txt`
- Create: `tools/accuracy/record.sh`
- Create: `tools/accuracy/evaluate.py`
- Test: `tools/accuracy/test_evaluate.py`

**Interfaces:**
- Consumes: server binary and models from Task 1.
- Produces: `evaluate.py` CLI printing a results table; constants `STYLE_PROMPT` and `DEFAULT_TERMS` whose values must equal the defaults later put in `examples/settings.json` / `examples/dictionary.json` (Task 5). Recordings in `tools/accuracy/recordings/NN.wav` + `NN.txt` (git-ignored).

- [ ] **Step 1: Write `tools/accuracy/sentences.txt`** (one sentence per line; the user reads these aloud)

```text
Сьогодні я відкрив pull request у GitHub і попросив колегу зробити code review.
Треба задеплоїти цей сервіс у Kubernetes, а потім перевірити логи в Kibana.
Я оновив README і додав нову змінну в Terraform конфіг.
Давай створимо feature branch, зробимо commit і запушимо зміни.
Тест падає через NullPointerException, треба подивитися stack trace.
На мітингу обговорили roadmap і дедлайн для нового release.
```

- [ ] **Step 2: Write the failing tests `tools/accuracy/test_evaluate.py`**

```python
import unittest

from evaluate import latin_hit_rate, normalize, wer


class NormalizeTest(unittest.TestCase):
    def test_lowercases_and_strips_punctuation(self):
        self.assertEqual(normalize("Привіт, GitHub!"), ["привіт", "github"])

    def test_keeps_apostrophe_inside_ukrainian_words(self):
        self.assertEqual(normalize("Я з’їв м'ясо"), ["я", "з'їв", "м'ясо"])

    def test_empty(self):
        self.assertEqual(normalize("  ...  "), [])


class WerTest(unittest.TestCase):
    def test_identical(self):
        self.assertEqual(wer(["a", "b"], ["a", "b"]), 0.0)

    def test_one_substitution_of_four(self):
        self.assertEqual(wer(["a", "b", "c", "d"], ["a", "x", "c", "d"]), 0.25)

    def test_insertion_and_deletion(self):
        self.assertAlmostEqual(wer(["a", "b", "c"], ["a", "c", "d", "e"]), 1.0)

    def test_empty_reference(self):
        self.assertEqual(wer([], ["a"]), 1.0)
        self.assertEqual(wer([], []), 0.0)


class LatinHitRateTest(unittest.TestCase):
    def test_counts_latin_words_found_in_hypothesis(self):
        ref = normalize("Відкрив pull request у GitHub")
        hyp = normalize("відкрив пул request у GitHub")
        self.assertEqual(latin_hit_rate(ref, hyp), (2, 3))

    def test_repeated_terms_count_separately(self):
        ref = normalize("commit і ще commit")
        hyp = normalize("commit і ще коміт")
        self.assertEqual(latin_hit_rate(ref, hyp), (1, 2))

    def test_no_latin_words(self):
        self.assertEqual(latin_hit_rate(["привіт"], ["привіт"]), (0, 0))


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd tools/accuracy && python3 -m unittest test_evaluate -v; cd -`
Expected: FAIL/ERROR with `ModuleNotFoundError: No module named 'evaluate'`.

- [ ] **Step 4: Write `tools/accuracy/evaluate.py`**

```python
#!/usr/bin/env python3
"""Compare whisper models and prompt variants on the user's own recordings.

Reports word error rate (WER) and how many Latin-script terms from the
reference text came out in Latin script.

Usage: evaluate.py [--models large-v3 large-v3-turbo] [--port 8179]
"""
import argparse
import json
import re
import subprocess
import sys
import time
import urllib.request
from collections import Counter
from pathlib import Path

DATA = Path.home() / ".local/share/dictation"
SERVER = DATA / "bin/whisper-server"
MODELS = DATA / "models"
VAD = MODELS / "ggml-silero-v6.2.0.bin"
RECORDINGS = Path(__file__).parent / "recordings"

# Must match examples/settings.json "stylePrompt" and examples/dictionary.json "terms".
STYLE_PROMPT = ("Сьогодні я відкрив pull request у GitHub, задеплоїв сервіс у "
                "Kubernetes і оновив README.")
DEFAULT_TERMS = ["Kubernetes", "Terraform", "pull request", "PitchBook", "Hammerspoon"]

APOSTROPHES = re.compile(r"[’ʼ`´]")
NON_WORD = re.compile(r"[^\w']+")
LATIN = re.compile(r"[a-z]")


def normalize(text):
    text = APOSTROPHES.sub("'", text.lower())
    words = NON_WORD.sub(" ", text).split()
    return [w.strip("'") for w in words if w.strip("'")]


def wer(ref, hyp):
    if not ref:
        return 0.0 if not hyp else 1.0
    prev = list(range(len(hyp) + 1))
    for i, r in enumerate(ref, 1):
        cur = [i]
        for j, h in enumerate(hyp, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (r != h)))
        prev = cur
    return prev[-1] / len(ref)


def latin_hit_rate(ref, hyp):
    wanted = [w for w in ref if LATIN.search(w)]
    have = Counter(hyp)
    hits = 0
    for w in wanted:
        if have[w] > 0:
            have[w] -= 1
            hits += 1
    return hits, len(wanted)


def start_server(model, port):
    proc = subprocess.Popen(
        [str(SERVER), "-m", str(MODELS / f"ggml-{model}.bin"), "--host", "127.0.0.1",
         "--port", str(port), "--vad", "--vad-model", str(VAD), "-nt", "-sns"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    deadline = time.time() + 120
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{port}/health") as r:
                if r.status == 200:
                    return proc
        except OSError:
            pass
        if proc.poll() is not None:
            sys.exit(f"whisper-server exited while loading {model}")
        time.sleep(0.5)
    proc.kill()
    sys.exit(f"timed out loading {model}")


def transcribe(port, wav, prompt):
    args = ["curl", "-sS", "--max-time", "120", "-F", f"file=@{wav}",
            "--form-string", "language=uk", "--form-string", "temperature=0.0",
            "--form-string", "response_format=json"]
    if prompt:
        args += ["--form-string", f"prompt={prompt}"]
    args.append(f"http://127.0.0.1:{port}/inference")
    started = time.time()
    out = subprocess.run(args, capture_output=True, text=True, check=True).stdout
    return json.loads(out).get("text", "").strip(), time.time() - started


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--models", nargs="+", default=["large-v3", "large-v3-turbo"])
    ap.add_argument("--port", type=int, default=8179)
    args = ap.parse_args()

    clips = sorted(RECORDINGS.glob("*.wav"))
    if not clips:
        sys.exit(f"no recordings in {RECORDINGS}; run record.sh first")

    variants = {"no prompt": "", "style+terms": STYLE_PROMPT + " " + ", ".join(DEFAULT_TERMS)}
    rows = []
    for model in args.models:
        if not (MODELS / f"ggml-{model}.bin").exists():
            print(f"skip {model}: model not downloaded")
            continue
        proc = start_server(model, args.port)
        try:
            for name, prompt in variants.items():
                errs, hits, total, secs = [], 0, 0, 0.0
                for wav in clips:
                    ref = normalize(wav.with_suffix(".txt").read_text())
                    text, took = transcribe(args.port, wav, prompt)
                    hyp = normalize(text)
                    errs.append(wer(ref, hyp))
                    h, t = latin_hit_rate(ref, hyp)
                    hits, total, secs = hits + h, total + t, secs + took
                    print(f"[{model} / {name}] {wav.name}: {text}")
                rows.append((model, name, sum(errs) / len(errs), hits, total, secs / len(clips)))
        finally:
            proc.terminate()
            proc.wait()

    print(f"\n{'model':<16}{'prompt':<14}{'WER':>7}{'Latin terms':>14}{'avg s':>8}")
    for model, name, w, h, t, s in rows:
        print(f"{model:<16}{name:<14}{w:>6.1%}{f'{h}/{t}':>14}{s:>8.2f}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd tools/accuracy && python3 -m unittest test_evaluate -v; cd -`
Expected: 10 tests, all `ok`.

- [ ] **Step 6: Write `tools/accuracy/record.sh`**

```bash
#!/usr/bin/env bash
# Record one clip per line of sentences.txt into recordings/NN.wav (+ NN.txt).
set -euo pipefail
cd "$(dirname "$0")"
command -v rec >/dev/null || { echo "sox is missing: brew install sox" >&2; exit 1; }
mkdir -p recordings

n=0
while IFS= read -r line <&3 || [[ -n "$line" ]]; do
  [[ -z "$line" ]] && continue
  n=$((n + 1))
  id=$(printf "%02d" "$n")
  echo
  echo "[$id] Read aloud (speak naturally):"
  echo "    $line"
  read -r -p "Press Enter to start recording..."
  rec -q -c 1 -r 16000 -b 16 "recordings/$id.wav" &
  pid=$!
  read -r -p "Recording... press Enter to stop."
  kill -INT "$pid"; wait "$pid" 2>/dev/null || true
  printf "%s\n" "$line" > "recordings/$id.txt"
  echo "saved recordings/$id.wav"
done 3< sentences.txt

echo
echo "Done. Add your own clips as recordings/NN.wav + NN.txt if you like, then run: ./evaluate.py"
```

Run: `brew list sox >/dev/null 2>&1 || brew install sox; chmod +x tools/accuracy/record.sh tools/accuracy/evaluate.py`

- [ ] **Step 7: Commit**

```bash
git add tools/accuracy
git commit -m "Add accuracy harness for model and prompt comparison

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 8: CHECKPOINT — the human partner records and we decide** (requires the user's voice; a subagent cannot do this step)

1. Ask the user to run `! tools/accuracy/record.sh` in this session (the terminal will need Microphone permission on first use).
2. Run `tools/accuracy/evaluate.py` and show the user the final table.
3. Decision rules:
   - If `large-v3 / style+terms` gets ≥ 70 % Latin terms: keep defaults (`large-v3`, style prompt) and continue.
   - If turbo is within 3 WER points of large-v3 with similar Latin-term rate, mention it to the user as an option (default stays `large-v3` per their preference).
   - If Latin-term rate is < 70 % for every variant: STOP and discuss with the user (options: stronger/longer style prompt, more `replace` rules, `language=auto`) before Task 3.
4. Record the table and decision in a short note appended to the spec under a new heading `## 10. Accuracy results (YYYY-MM-DD)`, and commit it.

---

### Task 3: Test runner, paths, UTF-8 helpers

**Files:**
- Create: `Makefile`
- Create: `tests/run.lua`
- Create: `src/dictation/paths.lua`
- Create: `src/dictation/utf8util.lua`
- Test: `tests/test_utf8util.lua`, `tests/test_paths.lua`

**Interfaces:**
- Produces:
  - Test globals: `test(name, fn)`, `eq(actual, expected, [msg])` (deep equality), `truthy(value, [msg])`.
  - `paths` table: `configDir, settings, dictionary, dataDir, modelsDir, server, vadModel, history, failedDir, rec, curl` (strings), `paths.model(name) -> string`, `paths.tempWav() -> string`.
  - `utf8util.lower(s) -> string` (ASCII + Ukrainian/Russian Cyrillic; keeps byte length, so byte offsets line up with the original), `utf8util.charAt(s, i) -> string` (the character starting at byte `i`, `""` past the end), `utf8util.charBefore(s, i) -> string` (the character ending at byte `i-1`, `""` at the start), `utf8util.isWordChar(ch) -> boolean` (letters, digits, `_`, apostrophes `'` `’` `ʼ`).
  - Invalid UTF-8 never raises; bytes that aren't valid are passed through unchanged.

- [ ] **Step 1: Install Lua 5.4 (same version Hammerspoon embeds)**

Run: `brew list lua@5.4 >/dev/null 2>&1 || brew install lua@5.4; /opt/homebrew/opt/lua@5.4/bin/lua -v`
Expected: `Lua 5.4.x`.

- [ ] **Step 2: Write `tests/run.lua`**

```lua
-- Minimal test runner. Usage (from repo root): lua tests/run.lua [tests/test_x.lua ...]
package.path = "./src/?.lua;./src/?/init.lua;" .. package.path

local function serialize(v)
  if type(v) == "string" then return string.format("%q", v) end
  if type(v) ~= "table" then return tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = "[" .. serialize(k) .. "]=" .. serialize(v[k]) end
  return "{" .. table.concat(parts, ", ") .. "}"
end

local function deepEqual(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do
    if not deepEqual(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

function eq(actual, expected, msg)
  if not deepEqual(actual, expected) then
    error((msg and msg .. ": " or "") .. "expected " .. serialize(expected)
      .. ", got " .. serialize(actual), 2)
  end
end

function truthy(value, msg)
  if not value then error(msg or "expected a truthy value", 2) end
end

local passed, failures, currentFile = 0, {}, ""

function test(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if ok then
    passed = passed + 1
  else
    failures[#failures + 1] = currentFile .. " :: " .. name .. "\n" .. tostring(err)
  end
end

local files = { ... }
if #files == 0 then
  local p = io.popen("ls tests/test_*.lua")
  for line in p:lines() do files[#files + 1] = line end
  p:close()
end

for _, file in ipairs(files) do
  currentFile = file
  local ok, err = pcall(dofile, file)
  if not ok then failures[#failures + 1] = file .. " (load error)\n" .. tostring(err) end
end

for _, f in ipairs(failures) do print("FAIL " .. f .. "\n") end
print(string.format("%d passed, %d failed", passed, #failures))
os.exit(#failures == 0 and 0 or 1)
```

- [ ] **Step 3: Write `Makefile`**

```makefile
LUA ?= /opt/homebrew/opt/lua@5.4/bin/lua

.PHONY: test
test:
	$(LUA) tests/run.lua
	cd tools/accuracy && python3 -m unittest -q test_evaluate
```

- [ ] **Step 4: Write the failing tests `tests/test_utf8util.lua`**

```lua
local u = require("dictation.utf8util")

test("lower handles ASCII", function()
  eq(u.lower("GitHub PR"), "github pr")
end)

test("lower handles Ukrainian uppercase incl. Є І Ї Ґ", function()
  eq(u.lower("ПРИВІТ ЄВГЕН ЇЖАК ҐАНОК"), "привіт євген їжак ґанок")
end)

test("lower handles Russian Ё and keeps lowercase untouched", function()
  eq(u.lower("ЁЖ ёж"), "ёж ёж")
end)

test("lower keeps byte length", function()
  local s = "Кубернетіс GitHub Їжак «Ура»"
  eq(#u.lower(s), #s)
end)

test("lower passes invalid UTF-8 and emoji through", function()
  eq(u.lower("A\x80Б\xFF🙂"), "a\x80б\xFF🙂")
end)

test("charAt returns whole multibyte characters", function()
  local s = "aБc"
  eq(u.charAt(s, 1), "a")
  eq(u.charAt(s, 2), "Б")
  eq(u.charAt(s, 4), "c")
  eq(u.charAt(s, 5), "")
end)

test("charBefore returns whole multibyte characters", function()
  local s = "aБc"
  eq(u.charBefore(s, 1), "")
  eq(u.charBefore(s, 2), "a")
  eq(u.charBefore(s, 4), "Б")
end)

test("isWordChar: letters, digits, apostrophes", function()
  for _, ch in ipairs({ "a", "Z", "7", "_", "б", "Ї", "ґ", "é", "'", "’", "ʼ" }) do
    eq(u.isWordChar(ch), true, ch)
  end
end)

test("isWordChar: spaces, punctuation, emoji, empty", function()
  for _, ch in ipairs({ " ", ",", ".", "-", "«", "»", "…", "🙂", "", "\x80" }) do
    eq(u.isWordChar(ch), false, ch)
  end
  eq(u.isWordChar(nil), false)
end)
```

- [ ] **Step 5: Write the failing tests `tests/test_paths.lua`**

```lua
local paths = require("dictation.paths")
local home = os.getenv("HOME")

test("paths are absolute and under the expected roots", function()
  eq(paths.settings, home .. "/.config/dictation/settings.json")
  eq(paths.dictionary, home .. "/.config/dictation/dictionary.json")
  eq(paths.server, home .. "/.local/share/dictation/bin/whisper-server")
  eq(paths.vadModel, home .. "/.local/share/dictation/models/ggml-silero-v6.2.0.bin")
  eq(paths.history, home .. "/.local/share/dictation/history.log")
end)

test("model path", function()
  eq(paths.model("large-v3"), home .. "/.local/share/dictation/models/ggml-large-v3.bin")
end)

test("tempWav is unique-ish and in /tmp", function()
  local p = paths.tempWav()
  truthy(p:match("^/tmp/dictation%-%d+%-%d+%-%d+%.wav$"), p)
end)
```

- [ ] **Step 6: Run tests to verify they fail**

Run: `make test`
Expected: FAIL — `module 'dictation.utf8util' not found` (runner reports errors per test file; non-zero exit).

- [ ] **Step 7: Write `src/dictation/paths.lua`**

```lua
-- All filesystem locations used by the tool.
local home = os.getenv("HOME")

local M = {}

M.configDir = home .. "/.config/dictation"
M.settings = M.configDir .. "/settings.json"
M.dictionary = M.configDir .. "/dictionary.json"

M.dataDir = home .. "/.local/share/dictation"
M.modelsDir = M.dataDir .. "/models"
M.server = M.dataDir .. "/bin/whisper-server"
M.vadModel = M.modelsDir .. "/ggml-silero-v6.2.0.bin"
M.history = M.dataDir .. "/history.log"
M.failedDir = M.dataDir .. "/failed"

M.rec = "/opt/homebrew/bin/rec"
M.curl = "/usr/bin/curl"

function M.model(name)
  return M.modelsDir .. "/ggml-" .. name .. ".bin"
end

local counter = 0
function M.tempWav()
  counter = counter + 1
  return string.format("/tmp/dictation-%s-%d.wav", os.date("%Y%m%d-%H%M%S"), counter)
end

return M
```

- [ ] **Step 8: Write `src/dictation/utf8util.lua`**

```lua
-- UTF-8 helpers. Lua's string.lower only handles ASCII; this adds Cyrillic.
local M = {}

local CHAR = "^" .. utf8.charpattern

local function codepoint(ch)
  local ok, cp = pcall(utf8.codepoint, ch)
  if ok and #utf8.char(cp) == #ch then return cp end
  return nil
end

local function lowerChar(ch)
  if #ch == 1 then return ch:lower() end
  local cp = codepoint(ch)
  -- charpattern glues stray continuation bytes onto the previous char ("A\x80")
  if not cp then return ch:sub(1, 1):lower() .. ch:sub(2) end
  if cp >= 0x410 and cp <= 0x42F then return utf8.char(cp + 0x20) end -- А..Я
  if cp >= 0x400 and cp <= 0x40F then return utf8.char(cp + 0x50) end -- Ѐ..Џ (Є І Ї Ё)
  if cp == 0x490 then return utf8.char(0x491) end                     -- Ґ
  return ch
end

-- Bytes that are not part of a valid sequence are left untouched by gsub.
function M.lower(s)
  return (s:gsub(utf8.charpattern, lowerChar))
end

function M.charAt(s, i)
  if i > #s then return "" end
  local _, e = s:find(CHAR, i)
  return s:sub(i, e or i)
end

function M.charBefore(s, i)
  if i <= 1 then return "" end
  local j = i - 1
  while j > 1 and j > i - 4 do
    local b = s:byte(j)
    if b < 0x80 or b > 0xBF then break end
    j = j - 1
  end
  return s:sub(j, i - 1)
end

function M.isWordChar(ch)
  if ch == nil or ch == "" then return false end
  if #ch == 1 then return ch:match("^[%w_']$") ~= nil and ch:byte() < 0x80 end
  local cp = codepoint(ch)
  if not cp then return false end
  return (cp >= 0xC0 and cp <= 0x24F and cp ~= 0xD7 and cp ~= 0xF7) -- Latin-1 / Extended letters
      or (cp >= 0x400 and cp <= 0x52F)                                -- Cyrillic
      or cp == 0x2BC or cp == 0x2019                                  -- ʼ ’
end

return M
```

- [ ] **Step 9: Run tests to verify they pass**

Run: `make test`
Expected: Lua runner prints `12 passed, 0 failed`; Python prints `OK`.

- [ ] **Step 10: Commit**

```bash
git add Makefile tests src/dictation/paths.lua src/dictation/utf8util.lua
git commit -m "Add test runner, paths and UTF-8 helpers

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Dictionary text processing

**Files:**
- Create: `src/dictation/dictionary.lua`
- Test: `tests/test_dictionary.lua`

**Interfaces:**
- Consumes: `utf8util.lower`, `utf8util.charAt`, `utf8util.charBefore`, `utf8util.isWordChar` (Task 3).
- Produces:
  - `dictionary.estimateTokens(text) -> number` — 3 per whitespace-separated word containing a non-ASCII byte, 1.5 per ASCII word.
  - `dictionary.buildPrompt(stylePrompt, terms, maxTokens) -> string` — style always included; terms appended in order, joined with `", "`, stopping at the first term that would exceed `maxTokens`; style and terms separated by one space.
  - `dictionary.applyReplacements(text, replace) -> string` — single left-to-right pass; at each position the longest matching key wins; case-insensitive (Cyrillic too); a key that starts/ends with a word character only matches at word boundaries; values inserted verbatim; output of one rule is never re-matched.
  - `dictionary.stripHallucinations(text, extraPhrases) -> string` — removes `[UPPER_CASE]` tags, then repeatedly removes the last sentence while it starts with a known phrase (built-in list + `extraPhrases`), comparing case-insensitively and ignoring surrounding punctuation.
  - `dictionary.process(text, dict) -> string` — `stripHallucinations(text, dict.dropPhrases)` → `applyReplacements(…, dict.replace)` → collapse runs of spaces → trim.
  - `dictionary.BUILTIN_DROP` — list of built-in hallucination phrases.

- [ ] **Step 1: Write the failing tests `tests/test_dictionary.lua`**

```lua
local d = require("dictation.dictionary")

-- estimateTokens / buildPrompt

test("estimateTokens counts ASCII and non-ASCII words differently", function()
  eq(d.estimateTokens("Hello world"), 3)
  eq(d.estimateTokens("Привіт world"), 4.5)
  eq(d.estimateTokens(""), 0)
end)

test("buildPrompt joins style and terms", function()
  eq(d.buildPrompt("Стиль.", { "Kubernetes", "pull request" }, 200), "Стиль. Kubernetes, pull request")
end)

test("buildPrompt with empty style or no terms", function()
  eq(d.buildPrompt("", { "A", "B" }, 200), "A, B")
  eq(d.buildPrompt("Стиль.", {}, 200), "Стиль.")
  eq(d.buildPrompt("", {}, 200), "")
end)

test("buildPrompt drops terms from the end when over budget", function()
  -- style 3 + one 1.5 + two 1.5 = 6 fits; three would make 7.5
  eq(d.buildPrompt("Слово", { "one", "two", "three" }, 6), "Слово one, two")
end)

test("buildPrompt stops at first term that does not fit (keeps priority order)", function()
  eq(d.buildPrompt("Слово", { "one", "довгий термін", "x" }, 6), "Слово one")
end)

-- applyReplacements

test("replaces case-insensitively, Cyrillic included, value verbatim", function()
  eq(d.applyReplacements("Відкрив Пул Реквест сьогодні", { ["пул реквест"] = "pull request" }),
    "Відкрив pull request сьогодні")
end)

test("matches whole words only", function()
  local r = { ["пул"] = "pool" }
  eq(d.applyReplacements("пул і пулемет", r), "pool і пулемет")
end)

test("apostrophe counts as part of a word (з'їв, з’їв, зʼїв)", function()
  local r = { ["їв"] = "X" }
  eq(d.applyReplacements("з'їв з’їв зʼїв їв", r), "з'їв з’їв зʼїв X")
end)

test("matches next to guillemets, punctuation and emoji", function()
  local r = { ["кубернетіс"] = "Kubernetes" }
  eq(d.applyReplacements("«Кубернетіс», кубернетіс🙂 (кубернетіс).", r),
    "«Kubernetes», Kubernetes🙂 (Kubernetes).")
end)

test("longest key wins at a position", function()
  local r = { ["пул"] = "pool", ["пул реквест"] = "pull request" }
  eq(d.applyReplacements("пул реквест і пул", r), "pull request і pool")
end)

test("output of one rule is not re-matched by another", function()
  local r = { ["пул реквест"] = "pull request", ["pull"] = "XX" }
  eq(d.applyReplacements("пул реквест", r), "pull request")
end)

test("empty keys are ignored and empty replace table is a no-op", function()
  eq(d.applyReplacements("текст", { [""] = "X" }), "текст")
  eq(d.applyReplacements("текст", {}), "текст")
end)

test("invalid UTF-8 does not crash", function()
  eq(d.applyReplacements("пул \x80\xFF пул", { ["пул"] = "pool" }), "pool \x80\xFF pool")
end)

-- stripHallucinations

test("drops output that is entirely a known phrase", function()
  eq(d.stripHallucinations("Дякую за перегляд!", {}), "")
  eq(d.stripHallucinations("  thanks for watching.  ", {}), "")
end)

test("drops a known phrase as the final sentence only", function()
  eq(d.stripHallucinations("Зробив деплой. Дякую за перегляд!", {}), "Зробив деплой.")
  eq(d.stripHallucinations("Дякую за перегляд! Зробив деплой.", {}), "Дякую за перегляд! Зробив деплой.")
end)

test("drops phrase prefixes like 'Субтитри зроблено спільнотою…'", function()
  eq(d.stripHallucinations("Готово. Субтитри зроблено спільнотою Amara.org", {}), "Готово.")
end)

test("drops repeated trailing hallucinations and ellipsis-separated ones", function()
  eq(d.stripHallucinations("Готово… Дякую за перегляд! Дякую за перегляд!", {}), "Готово…")
end)

test("uses extra phrases from the dictionary", function()
  eq(d.stripHallucinations("Текст. Бла бла.", { "бла бла" }), "Текст.")
end)

test("removes [BLANK_AUDIO]-style tags", function()
  eq(d.stripHallucinations("[BLANK_AUDIO]", {}), "")
  eq(d.stripHallucinations("Привіт [MUSIC] світ", {}), "Привіт  світ")
end)

-- process

test("process strips, replaces and tidies whitespace", function()
  local dict = { replace = { ["гіт хаб"] = "GitHub" }, dropPhrases = {} }
  eq(d.process("  Запушив у гіт хаб [BLANK_AUDIO]  зміни. Дякую за перегляд! ", dict),
    "Запушив у GitHub зміни.")
end)

test("process tolerates missing dict fields", function()
  eq(d.process(" текст ", {}), "текст")
end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test`
Expected: FAIL — `tests/test_dictionary.lua (load error) … module 'dictation.dictionary' not found`.

- [ ] **Step 3: Write `src/dictation/dictionary.lua`**

```lua
-- Prompt building and transcript post-processing. Pure Lua, no hs.
local u = require("dictation.utf8util")

local M = {}

M.BUILTIN_DROP = {
  "Дякую за перегляд",
  "Субтитри зроблено",
  "Субтитри створено",
  "Редактор субтитрів",
  "Продовження слідує",
  "Thanks for watching",
  "Thank you for watching",
  "Subtitles by",
}

function M.estimateTokens(text)
  local n = 0
  for word in text:gmatch("%S+") do
    n = n + (word:find("[\128-\255]") and 3 or 1.5)
  end
  return n
end

function M.buildPrompt(stylePrompt, terms, maxTokens)
  local style = stylePrompt or ""
  local used = M.estimateTokens(style)
  local picked = {}
  for _, term in ipairs(terms or {}) do
    local cost = M.estimateTokens(term)
    if used + cost > maxTokens then break end
    used = used + cost
    picked[#picked + 1] = term
  end
  local list = table.concat(picked, ", ")
  if style == "" then return list end
  if list == "" then return style end
  return style .. " " .. list
end

local function sortedRules(replace)
  local rules = {}
  for key, value in pairs(replace or {}) do
    if key ~= "" then
      rules[#rules + 1] = {
        key = u.lower(key),
        value = value,
        wordStart = u.isWordChar(u.charAt(key, 1)),
        wordEnd = u.isWordChar(u.charBefore(key, #key + 1)),
      }
    end
  end
  table.sort(rules, function(a, b)
    if #a.key ~= #b.key then return #a.key > #b.key end
    return a.key < b.key
  end)
  return rules
end

function M.applyReplacements(text, replace)
  local rules = sortedRules(replace)
  if #rules == 0 then return text end
  local lower = u.lower(text)
  local out, pos = {}, 1
  while pos <= #text do
    local matched = nil
    for _, r in ipairs(rules) do
      local stop = pos + #r.key - 1
      if lower:sub(pos, stop) == r.key
          and (not r.wordStart or not u.isWordChar(u.charBefore(text, pos)))
          and (not r.wordEnd or not u.isWordChar(u.charAt(text, stop + 1))) then
        matched = r
        break
      end
    end
    if matched then
      out[#out + 1] = matched.value
      pos = pos + #matched.key
    else
      local ch = u.charAt(text, pos)
      out[#out + 1] = ch
      pos = pos + #ch
    end
  end
  return table.concat(out)
end

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Lowercase, collapse spaces, drop non-word characters at both ends.
local function normalize(s)
  s = u.lower(s):gsub("%s+", " ")
  while s ~= "" and not u.isWordChar(u.charAt(s, 1)) do
    s = s:sub(#u.charAt(s, 1) + 1)
  end
  while s ~= "" and not u.isWordChar(u.charBefore(s, #s + 1)) do
    s = s:sub(1, #s - #u.charBefore(s, #s + 1))
  end
  return s
end

-- Byte offset where the last sentence of s begins.
local function lastSentenceStart(s)
  local probe = s:gsub("…", "...") -- same byte length, so offsets stay valid
  local start = 1
  for p in probe:gmatch("[%.!%?]%s+()") do start = p end
  return start
end

function M.stripHallucinations(text, extraPhrases)
  local phrases = {}
  for _, p in ipairs(M.BUILTIN_DROP) do phrases[#phrases + 1] = normalize(p) end
  for _, p in ipairs(extraPhrases or {}) do
    local n = normalize(p)
    if n ~= "" then phrases[#phrases + 1] = n end
  end

  local s = trim(text:gsub("%[[%u_]+%]", ""))
  while s ~= "" do
    local start = lastSentenceStart(s)
    local last = normalize(s:sub(start))
    local drop = false
    for _, p in ipairs(phrases) do
      if last:sub(1, #p) == p then drop = true break end
    end
    if not drop then break end
    s = trim(s:sub(1, start - 1))
  end
  return s
end

function M.process(text, dict)
  local s = M.stripHallucinations(text, dict.dropPhrases)
  s = M.applyReplacements(s, dict.replace)
  return trim(s:gsub(" +", " "))
end

return M
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test`
Expected: `33 passed, 0 failed` (12 from Task 3 + 21 here); Python `OK`.

- [ ] **Step 5: Commit**

```bash
git add src/dictation/dictionary.lua tests/test_dictionary.lua
git commit -m "Add prompt builder, replacements and hallucination filter

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Config loading, validation and saving

**Files:**
- Create: `src/dictation/config.lua`
- Create: `examples/settings.json`
- Create: `examples/dictionary.json`
- Test: `tests/test_config.lua`

**Interfaces:**
- Consumes: nothing from earlier tasks (pure Lua; JSON codec is injected).
- Produces:
  - `config.DEFAULT_SETTINGS` (table, values below), `config.MODELS = {"large-v3", "large-v3-turbo"}`, `config.LANGUAGES = {"uk", "en", "auto"}`, `config.MODES = {"toggle", "hold"}`.
  - `config.validateSettings(raw) -> settings|nil, errors` — merges `raw` over defaults; `errors` is a list of strings like `settings.json: "mode" must be one of: toggle, hold`. Unknown keys are ignored.
  - `config.validateDictionary(raw) -> dictionary|nil, errors` — result always has `terms` (list), `replace` (map), `dropPhrases` (list).
  - `config.jsonFileIo(decode, encode) -> readJson, writeJson` where `readJson(path) -> table` | `nil, nil` (file missing) | `nil, errString`; `writeJson(path, tbl) -> true | nil, errString` (writes `path .. ".tmp"` then renames).
  - `config.newStore{ readJson, writeJson, settingsPath, dictionaryPath } -> store` with fields `store.settings`, `store.dictionary` (always the last good values; defaults before the first good load) and methods:
    - `store:load() -> ok, errors` — loads both files; each file independently keeps its last good value on failure.
    - `store:update(key, value) -> true | false, errString` — refuses when the last settings load failed (never overwrites a broken file); otherwise writes the user's raw table with `key` changed (does not dump all defaults into the file) and updates `store.settings`.

- [ ] **Step 1: Write the failing tests `tests/test_config.lua`**

```lua
local config = require("dictation.config")

local function fakeFiles(contents)
  local files = { written = {} }
  local function read(path)
    local v = contents[path]
    if v == nil then return nil, nil end
    if type(v) == "string" then return nil, v end -- string = parse error message
    return v
  end
  local function write(path, tbl)
    if files.failWrite then return nil, "disk full" end
    files.written[path] = tbl
    contents[path] = tbl
    return true
  end
  return files, read, write
end

local function newStore(contents)
  local files, read, write = fakeFiles(contents)
  local store = config.newStore {
    readJson = read, writeJson = write,
    settingsPath = "S", dictionaryPath = "D",
  }
  return store, files
end

-- validateSettings

test("defaults when raw is empty", function()
  local s, errs = config.validateSettings({})
  eq(errs, {})
  eq(s.mode, "toggle")
  eq(s.hotkey, { mods = { "alt" }, key = "space" })
  eq(s.cancelKey, "escape")
  eq(s.model, "large-v3")
  eq(s.language, "uk")
  eq(s.serverPort, 8178)
  eq(s.maxRecordingSeconds, 300)
  eq(s.idleUnloadMinutes, 0)
  eq(s.refocusOriginalApp, true)
  eq(s.restoreClipboard, true)
  eq(s.sounds, true)
  truthy(s.stylePrompt:find("pull request", 1, true))
end)

test("user values override defaults; unknown keys ignored", function()
  local s, errs = config.validateSettings({ mode = "hold", language = "auto", extra = 1 })
  eq(errs, {})
  eq(s.mode, "hold")
  eq(s.language, "auto")
  eq(s.extra, nil)
end)

test("defaults are not mutated by validation", function()
  local s = config.validateSettings({ hotkey = { mods = { "cmd" }, key = "d" } })
  s.hotkey.mods[1] = "ctrl"
  eq(config.DEFAULT_SETTINGS.hotkey.mods, { "alt" })
end)

test("rejects bad enum, type and range values", function()
  local s, errs = config.validateSettings({
    mode = "push", model = 3, serverPort = 80, maxRecordingSeconds = 0,
    sounds = "yes", stylePrompt = false, idleUnloadMinutes = -1,
  })
  eq(s, nil)
  eq(#errs, 7)
  local all = table.concat(errs, "\n")
  truthy(all:find('settings.json: "mode" must be one of: toggle, hold', 1, true), all)
  truthy(all:find('"serverPort" must be a whole number from 1024 to 65535', 1, true), all)
end)

test("rejects bad hotkey definitions", function()
  local _, e1 = config.validateSettings({ hotkey = { mods = { "super" }, key = "space" } })
  truthy(e1[1]:find('"hotkey.mods"', 1, true), e1[1])
  local _, e2 = config.validateSettings({ hotkey = { mods = { "alt" } } })
  truthy(e2[1]:find('"hotkey.key"', 1, true), e2[1])
  local _, e3 = config.validateSettings({ hotkey = "alt+space" })
  truthy(e3[1]:find('"hotkey"', 1, true), e3[1])
end)

test("non-table settings root is rejected", function()
  local s, errs = config.validateSettings({ "a", "b" })
  eq(s, nil)
  truthy(errs[1]:find("must be a JSON object", 1, true), errs[1])
end)

-- validateDictionary

test("dictionary defaults to empty lists/maps", function()
  local d, errs = config.validateDictionary({})
  eq(errs, {})
  eq(d, { terms = {}, replace = {}, dropPhrases = {} })
end)

test("dictionary accepts valid content", function()
  local raw = { terms = { "Kubernetes" }, replace = { ["пул"] = "pool" }, dropPhrases = { "бла" } }
  local d, errs = config.validateDictionary(raw)
  eq(errs, {})
  eq(d, raw)
end)

test("dictionary rejects wrong shapes", function()
  local d, errs = config.validateDictionary({ terms = { 1 }, replace = { a = 2 }, dropPhrases = "x" })
  eq(d, nil)
  eq(#errs, 3)
end)

-- store

test("store load uses defaults when files are missing", function()
  local store = newStore({})
  local ok, errs = store:load()
  eq(ok, true)
  eq(errs, {})
  eq(store.settings.mode, "toggle")
  eq(store.dictionary.terms, {})
end)

test("store keeps last good settings when file becomes invalid", function()
  local contents = { S = { mode = "hold" } }
  local store = newStore(contents)
  store:load()
  contents.S = "Unexpected character at line 3, column 5"
  local ok, errs = store:load()
  eq(ok, false)
  truthy(errs[1]:find("settings.json", 1, true) and errs[1]:find("line 3", 1, true), errs[1])
  eq(store.settings.mode, "hold")
end)

test("store keeps last good dictionary independently", function()
  local contents = { D = { terms = { "A" } } }
  local store = newStore(contents)
  store:load()
  contents.D = { terms = "oops" }
  contents.S = { mode = "hold" }
  local ok = store:load()
  eq(ok, false)
  eq(store.dictionary.terms, { "A" })
  eq(store.settings.mode, "hold")
end)

test("update writes only the user's keys plus the changed key", function()
  local store, files = newStore({ S = { mode = "toggle", sounds = false } })
  store:load()
  eq(store:update("model", "large-v3-turbo"), true)
  eq(files.written.S, { mode = "toggle", sounds = false, model = "large-v3-turbo" })
  eq(store.settings.model, "large-v3-turbo")
end)

test("update creates the settings file when missing", function()
  local store, files = newStore({})
  store:load()
  eq(store:update("mode", "hold"), true)
  eq(files.written.S, { mode = "hold" })
end)

test("update refuses while settings.json is broken (no overwrite)", function()
  local contents = { S = { mode = "toggle" } }
  local store, files = newStore(contents)
  store:load()
  contents.S = "Unexpected end of file"
  store:load()
  local ok, err = store:update("mode", "hold")
  eq(ok, false)
  truthy(err:find("fix it first", 1, true), err)
  eq(files.written.S, nil)
end)

test("update rejects invalid values and leaves file untouched", function()
  local store, files = newStore({})
  store:load()
  local ok, err = store:update("mode", "push")
  eq(ok, false)
  truthy(err:find('"mode"', 1, true), err)
  eq(files.written.S, nil)
  eq(store.settings.mode, "toggle")
end)

test("update reports write failures and keeps old settings", function()
  local store, files = newStore({})
  store:load()
  files.failWrite = true
  local ok, err = store:update("mode", "hold")
  eq(ok, false)
  truthy(err:find("disk full", 1, true), err)
  eq(store.settings.mode, "toggle")
end)

-- jsonFileIo

test("jsonFileIo reads, reports missing and parse errors, writes atomically", function()
  local decode = function(s)
    if s == "bad" then error("parse error at line 1") end
    return { value = s }
  end
  local encode = function(t) return t.value end
  local read, write = config.jsonFileIo(decode, encode)
  local path = os.tmpname()

  eq(write(path, { value = "good" }), true)
  eq(read(path), { value = "good" })

  local f = io.open(path, "w"); f:write("bad"); f:close()
  local t, err = read(path)
  eq(t, nil)
  truthy(err:find("parse error at line 1", 1, true), err)

  os.remove(path)
  local t2, err2 = read(path)
  eq(t2, nil)
  eq(err2, nil)
end)

test("jsonFileIo treats a non-table result as an error", function()
  local read = config.jsonFileIo(function() return 42 end, tostring)
  local path = os.tmpname()
  local t, err = read(path)
  os.remove(path)
  eq(t, nil)
  truthy(err:find("JSON object", 1, true), err)
end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test`
Expected: FAIL — `tests/test_config.lua (load error) … module 'dictation.config' not found`.

- [ ] **Step 3: Write `src/dictation/config.lua`**

```lua
-- Settings and dictionary: defaults, validation, last-good store. Pure Lua; JSON codec injected.
local M = {}

M.MODES = { "toggle", "hold" }
M.MODELS = { "large-v3", "large-v3-turbo" }
M.LANGUAGES = { "uk", "en", "auto" }
local MODS = { "cmd", "alt", "ctrl", "shift" }

M.DEFAULT_SETTINGS = {
  mode = "toggle",
  hotkey = { mods = { "alt" }, key = "space" },
  cancelKey = "escape",
  model = "large-v3",
  language = "uk",
  stylePrompt = "Сьогодні я відкрив pull request у GitHub, задеплоїв сервіс у Kubernetes і оновив README.",
  refocusOriginalApp = true,
  restoreClipboard = true,
  sounds = true,
  maxRecordingSeconds = 300,
  serverPort = 8178,
  idleUnloadMinutes = 0,
}

local function copy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, x in pairs(v) do t[k] = copy(x) end
  return t
end

local function contains(list, value)
  for _, x in ipairs(list) do
    if x == value then return true end
  end
  return false
end

local function isList(v)
  if type(v) ~= "table" then return false end
  local n = 0
  for _ in pairs(v) do n = n + 1 end
  return n == #v
end

local function isObject(v)
  return type(v) == "table" and (next(v) == nil or not isList(v))
end

local function listOfStrings(v)
  if not isList(v) then return false end
  for _, x in ipairs(v) do
    if type(x) ~= "string" then return false end
  end
  return true
end

local function enum(list)
  return function(v)
    if contains(list, v) then return nil end
    return "must be one of: " .. table.concat(list, ", ")
  end
end

local function kind(t)
  return function(v)
    if type(v) == t then return nil end
    return "must be a " .. t
  end
end

local function integer(min, max)
  return function(v)
    if math.type(v) == "integer" or (type(v) == "number" and v == math.floor(v)) then
      if v >= min and v <= max then return nil end
    end
    return string.format("must be a whole number from %d to %d", min, max)
  end
end

local SETTING_CHECKS = {
  mode = enum(M.MODES),
  cancelKey = kind("string"),
  model = enum(M.MODELS),
  language = enum(M.LANGUAGES),
  stylePrompt = kind("string"),
  refocusOriginalApp = kind("boolean"),
  restoreClipboard = kind("boolean"),
  sounds = kind("boolean"),
  maxRecordingSeconds = integer(5, 3600),
  serverPort = integer(1024, 65535),
  idleUnloadMinutes = integer(0, 1440),
}

local function checkHotkey(v, errors)
  if type(v) ~= "table" then
    errors[#errors + 1] = 'settings.json: "hotkey" must be an object like {"mods": ["alt"], "key": "space"}'
    return
  end
  local mods = v.mods or {}
  local okMods = listOfStrings(mods)
  for _, m in ipairs(okMods and mods or {}) do
    if not contains(MODS, m) then okMods = false end
  end
  if not okMods then
    errors[#errors + 1] = 'settings.json: "hotkey.mods" must be a list of: ' .. table.concat(MODS, ", ")
  end
  if type(v.key) ~= "string" or v.key == "" then
    errors[#errors + 1] = 'settings.json: "hotkey.key" must be a key name like "space" or "d"'
  end
end

function M.validateSettings(raw)
  if not isObject(raw) then return nil, { "settings.json: must be a JSON object" } end
  local errors, settings = {}, copy(M.DEFAULT_SETTINGS)
  for key, check in pairs(SETTING_CHECKS) do
    if raw[key] ~= nil then
      local problem = check(raw[key])
      if problem then
        errors[#errors + 1] = string.format('settings.json: "%s" %s', key, problem)
      else
        settings[key] = raw[key]
      end
    end
  end
  if raw.hotkey ~= nil then
    local before = #errors
    checkHotkey(raw.hotkey, errors)
    if #errors == before then
      settings.hotkey = { mods = copy(raw.hotkey.mods or {}), key = raw.hotkey.key }
    end
  end
  table.sort(errors)
  if #errors > 0 then return nil, errors end
  return settings, errors
end

function M.validateDictionary(raw)
  if not isObject(raw) then return nil, { "dictionary.json: must be a JSON object" } end
  local errors = {}
  local dict = { terms = {}, replace = {}, dropPhrases = {} }
  for _, key in ipairs({ "terms", "dropPhrases" }) do
    if raw[key] ~= nil then
      if listOfStrings(raw[key]) then
        dict[key] = copy(raw[key])
      else
        errors[#errors + 1] = string.format('dictionary.json: "%s" must be a list of strings', key)
      end
    end
  end
  if raw.replace ~= nil then
    local ok = isObject(raw.replace)
    for k, v in pairs(ok and raw.replace or {}) do
      if type(k) ~= "string" or type(v) ~= "string" then ok = false end
    end
    if ok then
      dict.replace = copy(raw.replace)
    else
      errors[#errors + 1] = 'dictionary.json: "replace" must map strings to strings'
    end
  end
  if #errors > 0 then return nil, errors end
  return dict, errors
end

function M.jsonFileIo(decode, encode)
  local function readJson(path)
    local f = io.open(path, "r")
    if not f then return nil, nil end
    local text = f:read("a")
    f:close()
    local ok, result = pcall(decode, text)
    if not ok then return nil, tostring(result) end
    if type(result) ~= "table" then return nil, "file must contain a JSON object" end
    return result
  end

  local function writeJson(path, tbl)
    local tmp = path .. ".tmp"
    local f, err = io.open(tmp, "w")
    if not f then return nil, err end
    f:write(encode(tbl))
    f:close()
    local ok, renameErr = os.rename(tmp, path)
    if not ok then return nil, renameErr end
    return true
  end

  return readJson, writeJson
end

local Store = {}
Store.__index = Store

function M.newStore(opts)
  return setmetatable({
    readJson = opts.readJson,
    writeJson = opts.writeJson,
    settingsPath = opts.settingsPath,
    dictionaryPath = opts.dictionaryPath,
    settings = copy(M.DEFAULT_SETTINGS),
    dictionary = { terms = {}, replace = {}, dropPhrases = {} },
    rawSettings = {},
    settingsOk = true,
  }, Store)
end

local function loadFile(self, path, name, validate)
  local raw, err = self.readJson(path)
  if err then return nil, nil, { name .. ": " .. err } end
  raw = raw or {}
  local value, errors = validate(raw)
  return value, raw, errors
end

function Store:load()
  local all = {}

  local settings, raw, errs = loadFile(self, self.settingsPath, "settings.json", M.validateSettings)
  self.settingsOk = settings ~= nil
  if settings then
    self.settings, self.rawSettings = settings, raw
  end
  for _, e in ipairs(errs) do all[#all + 1] = e end

  local dict, _, dErrs = loadFile(self, self.dictionaryPath, "dictionary.json", M.validateDictionary)
  if dict then self.dictionary = dict end
  for _, e in ipairs(dErrs) do all[#all + 1] = e end

  return #all == 0, all
end

function Store:update(key, value)
  if not self.settingsOk then
    return false, "settings.json has errors; fix it first (Edit settings…)"
  end
  local raw = copy(self.rawSettings)
  raw[key] = value
  local settings, errors = M.validateSettings(raw)
  if not settings then return false, table.concat(errors, "\n") end
  local ok, err = self.writeJson(self.settingsPath, raw)
  if not ok then return false, "could not save settings.json: " .. tostring(err) end
  self.settings, self.rawSettings = settings, raw
  return true
end

return M
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test`
Expected: `52 passed, 0 failed`; Python `OK`.

- [ ] **Step 5: Write `examples/settings.json`** (values must equal `config.DEFAULT_SETTINGS`)

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

- [ ] **Step 6: Write `examples/dictionary.json`** (`terms` must equal `DEFAULT_TERMS` in `tools/accuracy/evaluate.py`)

```json
{
  "terms": ["Kubernetes", "Terraform", "pull request", "PitchBook", "Hammerspoon"],
  "replace": {
    "пул реквест": "pull request",
    "пул реквести": "pull requests",
    "кубернетіс": "Kubernetes",
    "кубернетес": "Kubernetes",
    "гіт хаб": "GitHub",
    "гітхаб": "GitHub",
    "терраформ": "Terraform",
    "рідмі": "README"
  },
  "dropPhrases": []
}
```

- [ ] **Step 7: Add an examples consistency test** — append to `tests/test_config.lua`:

```lua
-- examples/settings.json must match defaults (checked without a JSON library:
-- every default scalar must appear verbatim as "key": value)
test("examples/settings.json mirrors DEFAULT_SETTINGS", function()
  local f = assert(io.open("examples/settings.json"))
  local text = f:read("a")
  f:close()
  for key, value in pairs(config.DEFAULT_SETTINGS) do
    if type(value) ~= "table" then
      local literal = type(value) == "string" and ('"' .. value .. '"') or tostring(value)
      truthy(text:find('"' .. key .. '": ' .. literal, 1, true), key)
    end
  end
  truthy(text:find('"hotkey": { "mods": ["alt"], "key": "space" }', 1, true), "hotkey")
end)
```

Run: `make test`
Expected: `53 passed, 0 failed`.

- [ ] **Step 8: Commit**

```bash
git add src/dictation/config.lua tests/test_config.lua examples
git commit -m "Add config validation, last-good store and example files

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Controller state machine

**Files:**
- Create: `src/dictation/controller.lua`
- Test: `tests/test_controller.lua`

**Interfaces:**
- Consumes: nothing directly; all side effects are injected (real implementations are wired in Task 10).
- Produces: `controller.new(deps) -> ctl` with methods `ctl:hotkeyDown()`, `ctl:hotkeyUp()`, `ctl:cancel()`, `ctl:recorderExited(exitCode, stderr)`, and field `ctl.state` (`"idle"` | `"recording"` | `"transcribing"`). Constants `controller.HOLD_MIN = 0.3`, `controller.MIN_SECONDS = 0.5`, `controller.TRANSCRIBE_TIMEOUT = 120`.
- `deps` (all required):
  - `settings() -> table` — current settings (uses `mode`, `maxRecordingSeconds`)
  - `clock() -> number` — seconds
  - `after(seconds, fn) -> timer` — timer has `:stop()`
  - `tempWav() -> path`
  - `frontApp() -> app|nil`
  - `recorder.start(path) -> true | false, errString`
  - `recorder.stop(done)` — stops recording; calls `done()` once the WAV is finalized
  - `recorder.cancel()` — stops and deletes the file
  - `transcribe(path, callback)` — `callback(text)` or `callback(nil, errString)`
  - `process(text) -> text` — dictionary post-processing
  - `paste(text, app)`
  - `history(text)`
  - `removeFile(path)`, `keepFailed(path)`
  - `setState(state)` — menu bar icon
  - `notify(message)`
  - `sound(name)` — `"start"`, `"done"`, `"error"`
  - `bindCancel(enabled)` — enables/disables the cancel hotkey
- Behaviour (spec §3 controller, plus Review Focus 4 and 5):
  - Mode is read at `hotkeyDown` in `idle` and fixed for that recording; changing the setting mid-recording takes effect next time.
  - toggle: down in idle → start; down in recording → stop. `hotkeyUp` ignored.
  - hold: down in idle → start; repeated down while recording ignored; up → stop. Hold < `HOLD_MIN` → discarded silently.
  - Any recording < `MIN_SECONDS` (that wasn't a silent short hold) → discarded, `notify("Recording too short")`.
  - Presses in `transcribing` are ignored.
  - Auto-stop after `maxRecordingSeconds`, then transcribe normally.
  - Watchdog: if no transcription result within `TRANSCRIBE_TIMEOUT` seconds → `notify("Transcription timed out")`, keep the WAV, back to idle; a result arriving later is ignored.
  - Recorder exiting by itself while recording (e.g. mic denied) → `notify("Recording failed: " .. stderr)`, `sound("error")`, idle.
  - Result empty after `process` → `notify("Nothing recognized")`, no paste, WAV removed.

- [ ] **Step 1: Write the failing tests `tests/test_controller.lua`**

```lua
local controller = require("dictation.controller")

local function harness(overrides)
  local h = { now = 0, timers = {}, log = {}, states = {}, pasted = {}, notes = {} }
  h.settings = { mode = "toggle", maxRecordingSeconds = 300 }
  local function log(x) h.log[#h.log + 1] = x end

  local deps = {
    settings = function() return h.settings end,
    clock = function() return h.now end,
    after = function(sec, fn)
      local t = { at = h.now + sec, fn = fn }
      function t:stop() self.stopped = true end
      h.timers[#h.timers + 1] = t
      return t
    end,
    tempWav = function() return "/tmp/a.wav" end,
    frontApp = function() return "Slack" end,
    recorder = {
      start = function(path)
        log("rec.start " .. path)
        if h.recFails then return false, h.recFails end
        return true
      end,
      stop = function(done) log("rec.stop"); h.stopDone = done; if not h.asyncStop then done() end end,
      cancel = function() log("rec.cancel") end,
    },
    transcribe = function(path, cb) log("transcribe " .. path); h.transcribeCb = cb end,
    process = function(text) return (text:gsub("^%s+", ""):gsub("%s+$", "")) end,
    paste = function(text, app) h.pasted[#h.pasted + 1] = { text, app } end,
    history = function(text) log("history " .. text) end,
    removeFile = function(p) log("rm " .. p) end,
    keepFailed = function(p) log("keep " .. p) end,
    setState = function(s) h.states[#h.states + 1] = s end,
    notify = function(m) h.notes[#h.notes + 1] = m end,
    sound = function(n) log("sound " .. n) end,
    bindCancel = function(on) log("cancel " .. tostring(on)) end,
  }
  for k, v in pairs(overrides or {}) do deps[k] = v end

  function h.advance(sec)
    h.now = h.now + sec
    for _, t in ipairs(h.timers) do
      if not t.stopped and not t.fired and t.at <= h.now then
        t.fired = true
        t.fn()
      end
    end
  end

  function h.has(entry)
    for _, x in ipairs(h.log) do if x == entry then return true end end
    return false
  end

  h.ctl = controller.new(deps)
  return h
end

test("toggle: start, stop, transcribe, paste", function()
  local h = harness()
  h.ctl:hotkeyDown()
  eq(h.ctl.state, "recording")
  truthy(h.has("rec.start /tmp/a.wav") and h.has("sound start") and h.has("cancel true"))
  h.advance(2)
  h.ctl:hotkeyDown()
  eq(h.ctl.state, "transcribing")
  truthy(h.has("rec.stop") and h.has("transcribe /tmp/a.wav") and h.has("cancel false"))
  h.transcribeCb("  Привіт  ")
  eq(h.ctl.state, "idle")
  eq(h.pasted, { { "Привіт", "Slack" } })
  truthy(h.has("history Привіт") and h.has("rm /tmp/a.wav") and h.has("sound done"))
  eq(h.states, { "recording", "transcribing", "idle" })
end)

test("toggle: hotkeyUp is ignored", function()
  local h = harness()
  h.ctl:hotkeyDown()
  h.advance(2)
  h.ctl:hotkeyUp()
  eq(h.ctl.state, "recording")
end)

test("hold: start on down, stop on up", function()
  local h = harness()
  h.settings.mode = "hold"
  h.ctl:hotkeyDown()
  h.advance(1)
  h.ctl:hotkeyUp()
  eq(h.ctl.state, "transcribing")
end)

test("hold: key repeat while recording does not restart or stop", function()
  local h = harness()
  h.settings.mode = "hold"
  h.ctl:hotkeyDown()
  h.advance(0.5)
  h.ctl:hotkeyDown()
  h.ctl:hotkeyDown()
  eq(h.ctl.state, "recording")
  local starts = 0
  for _, x in ipairs(h.log) do if x:find("^rec.start") then starts = starts + 1 end end
  eq(starts, 1)
end)

test("hold: tap shorter than HOLD_MIN is discarded silently", function()
  local h = harness()
  h.settings.mode = "hold"
  h.ctl:hotkeyDown()
  h.advance(0.2)
  h.ctl:hotkeyUp()
  eq(h.ctl.state, "idle")
  truthy(h.has("rec.cancel"))
  eq(h.notes, {})
  eq(h.transcribeCb, nil)
end)

test("recording shorter than MIN_SECONDS is discarded with a notice", function()
  local h = harness()
  h.ctl:hotkeyDown()
  h.advance(0.4)
  h.ctl:hotkeyDown()
  eq(h.ctl.state, "idle")
  truthy(h.has("rec.cancel"))
  eq(h.notes, { "Recording too short" })
end)

test("mode change mid-recording applies to the next recording only", function()
  local h = harness()
  h.ctl:hotkeyDown()          -- toggle recording
  h.settings.mode = "hold"
  h.advance(1)
  h.ctl:hotkeyUp()            -- ignored: this recording is toggle
  eq(h.ctl.state, "recording")
  h.ctl:hotkeyDown()
  eq(h.ctl.state, "transcribing")
end)

test("presses while transcribing are ignored", function()
  local h = harness()
  h.ctl:hotkeyDown(); h.advance(1); h.ctl:hotkeyDown()
  h.ctl:hotkeyDown()
  h.ctl:hotkeyUp()
  h.ctl:cancel()
  eq(h.ctl.state, "transcribing")
end)

test("cancel discards the recording", function()
  local h = harness()
  h.ctl:hotkeyDown()
  h.advance(3)
  h.ctl:cancel()
  eq(h.ctl.state, "idle")
  truthy(h.has("rec.cancel") and h.has("cancel false"))
  eq(h.notes, { "Cancelled" })
  eq(h.transcribeCb, nil)
end)

test("cancel in idle does nothing", function()
  local h = harness()
  h.ctl:cancel()
  eq(h.ctl.state, "idle")
  eq(h.notes, {})
end)

test("auto-stop at maxRecordingSeconds transcribes", function()
  local h = harness()
  h.settings.maxRecordingSeconds = 10
  h.ctl:hotkeyDown()
  h.advance(10)
  eq(h.ctl.state, "transcribing")
  truthy(h.has("transcribe /tmp/a.wav"))
end)

test("auto-stop timer is cancelled when stopped manually", function()
  local h = harness()
  h.settings.maxRecordingSeconds = 10
  h.ctl:hotkeyDown(); h.advance(2); h.ctl:hotkeyDown()
  h.transcribeCb("ok")
  h.ctl:hotkeyDown()           -- second recording starts at t=2
  h.advance(9)                 -- first auto-stop would fire at t=10
  eq(h.ctl.state, "recording")
end)

test("empty result: notice, no paste", function()
  local h = harness()
  h.ctl:hotkeyDown(); h.advance(1); h.ctl:hotkeyDown()
  h.transcribeCb("   ")
  eq(h.ctl.state, "idle")
  eq(h.pasted, {})
  eq(h.notes, { "Nothing recognized" })
  truthy(h.has("rm /tmp/a.wav"))
end)

test("transcription error: notice, keep wav", function()
  local h = harness()
  h.ctl:hotkeyDown(); h.advance(1); h.ctl:hotkeyDown()
  h.transcribeCb(nil, "server unreachable")
  eq(h.ctl.state, "idle")
  eq(h.notes, { "Transcription failed: server unreachable" })
  truthy(h.has("keep /tmp/a.wav") and h.has("sound error"))
end)

test("watchdog: timeout returns to idle and late result is ignored", function()
  local h = harness()
  h.ctl:hotkeyDown(); h.advance(1); h.ctl:hotkeyDown()
  h.advance(controller.TRANSCRIBE_TIMEOUT)
  eq(h.ctl.state, "idle")
  eq(h.notes, { "Transcription timed out" })
  truthy(h.has("keep /tmp/a.wav"))
  h.transcribeCb("late text")
  eq(h.pasted, {})
  eq(h.ctl.state, "idle")
end)

test("late result from an old session does not affect a new recording", function()
  local h = harness()
  h.ctl:hotkeyDown(); h.advance(1); h.ctl:hotkeyDown()
  local oldCb = h.transcribeCb
  h.advance(controller.TRANSCRIBE_TIMEOUT)
  h.ctl:hotkeyDown()
  oldCb("late text")
  eq(h.ctl.state, "recording")
  eq(h.pasted, {})
end)

test("recorder start failure: notice and stay idle", function()
  local h = harness()
  h.recFails = "sox not found"
  h.ctl:hotkeyDown()
  eq(h.ctl.state, "idle")
  eq(h.notes, { "Recording failed: sox not found" })
  truthy(not h.has("cancel true"))
end)

test("recorder exiting on its own while recording: notice and idle", function()
  local h = harness()
  h.ctl:hotkeyDown()
  h.ctl:recorderExited(1, "can't open input device")
  eq(h.ctl.state, "idle")
  eq(h.notes, { "Recording failed: can't open input device" })
  truthy(h.has("cancel false") and h.has("sound error"))
end)

test("recorder exit after a normal stop is ignored", function()
  local h = harness()
  h.ctl:hotkeyDown(); h.advance(1); h.ctl:hotkeyDown()
  h.ctl:recorderExited(0, "")
  eq(h.ctl.state, "transcribing")
  eq(h.notes, {})
end)

test("transcribe waits for the recorder to finalize the file", function()
  local h = harness()
  h.asyncStop = true
  h.ctl:hotkeyDown(); h.advance(1); h.ctl:hotkeyDown()
  eq(h.ctl.state, "transcribing")
  eq(h.transcribeCb, nil)
  h.stopDone()
  truthy(h.has("transcribe /tmp/a.wav"))
end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test`
Expected: FAIL — `tests/test_controller.lua (load error) … module 'dictation.controller' not found`.

- [ ] **Step 3: Write `src/dictation/controller.lua`**

```lua
-- Dictation state machine: idle → recording → transcribing → idle. All side effects injected.
local M = {}

M.HOLD_MIN = 0.3
M.MIN_SECONDS = 0.5
M.TRANSCRIBE_TIMEOUT = 120

local Ctl = {}
Ctl.__index = Ctl

function M.new(deps)
  return setmetatable({ deps = deps, state = "idle", session = 0 }, Ctl)
end

function Ctl:setState(state)
  self.state = state
  self.deps.setState(state)
end

function Ctl:stopTimer(name)
  if self[name] then
    self[name]:stop()
    self[name] = nil
  end
end

function Ctl:start()
  local d = self.deps
  local path = d.tempWav()
  local ok, err = d.recorder.start(path)
  if not ok then
    d.notify("Recording failed: " .. tostring(err))
    d.sound("error")
    return
  end
  self.session = self.session + 1
  self.rec = {
    path = path,
    mode = d.settings().mode,
    startedAt = d.clock(),
    app = d.frontApp(),
  }
  local session = self.session
  self.autoStop = d.after(d.settings().maxRecordingSeconds, function()
    if self.session == session and self.state == "recording" then self:stop() end
  end)
  d.bindCancel(true)
  d.sound("start")
  self:setState("recording")
end

-- Leave the recording state without transcribing.
function Ctl:discard(message)
  local d = self.deps
  self:stopTimer("autoStop")
  d.bindCancel(false)
  d.recorder.cancel()
  self.rec = nil
  if message then d.notify(message) end
  self:setState("idle")
end

function Ctl:stop()
  local d = self.deps
  local rec = self.rec
  local held = d.clock() - rec.startedAt
  if rec.mode == "hold" and held < M.HOLD_MIN then return self:discard(nil) end
  if held < M.MIN_SECONDS then return self:discard("Recording too short") end

  self:stopTimer("autoStop")
  d.bindCancel(false)
  self:setState("transcribing")
  local session = self.session
  self.watchdog = d.after(M.TRANSCRIBE_TIMEOUT, function()
    if self.session ~= session or self.state ~= "transcribing" then return end
    self:finish(nil, "timeout")
  end)
  d.recorder.stop(function()
    if self.session ~= session or self.state ~= "transcribing" then return end
    d.transcribe(rec.path, function(text, err)
      if self.session ~= session or self.state ~= "transcribing" then return end
      self:finish(text, err)
    end)
  end)
end

function Ctl:finish(text, err)
  local d = self.deps
  local rec = self.rec
  self:stopTimer("watchdog")
  self.rec = nil
  if err == "timeout" then
    d.notify("Transcription timed out")
    d.keepFailed(rec.path)
    d.sound("error")
  elseif text == nil then
    d.notify("Transcription failed: " .. tostring(err))
    d.keepFailed(rec.path)
    d.sound("error")
  else
    local result = d.process(text)
    d.removeFile(rec.path)
    if result == "" then
      d.notify("Nothing recognized")
    else
      d.history(result)
      d.paste(result, rec.app)
      d.sound("done")
    end
  end
  self:setState("idle")
end

function Ctl:hotkeyDown()
  if self.state == "idle" then
    self:start()
  elseif self.state == "recording" and self.rec.mode == "toggle" then
    self:stop()
  end
end

function Ctl:hotkeyUp()
  if self.state == "recording" and self.rec.mode == "hold" then
    self:stop()
  end
end

function Ctl:cancel()
  if self.state == "recording" then
    self:discard("Cancelled")
  end
end

function Ctl:recorderExited(exitCode, stderr)
  if self.state ~= "recording" then return end
  local msg = (stderr and stderr ~= "") and stderr or ("rec exited with code " .. tostring(exitCode))
  self.deps.sound("error")
  self:discard("Recording failed: " .. msg:gsub("%s+$", ""))
end

return M
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test`
Expected: `73 passed, 0 failed`; Python `OK`.

- [ ] **Step 5: Commit**

```bash
git add src/dictation/controller.lua tests/test_controller.lua
git commit -m "Add dictation controller state machine

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: whisper-server lifecycle

**Files:**
- Create: `src/dictation/server.lua`
- Test: `tests/test_server.lua`

**Interfaces:**
- Consumes: settings shape from Task 5 (`model`, `serverPort`, `idleUnloadMinutes`); path names from Task 3 (`paths.server`, `paths.vadModel`, `paths.model(name)`).
- Produces:
  - `server.args{ model, vadModel, port, threads } -> list of strings` (port/threads formatted with `%d`, so JSON floats like `8178.0` become `"8178"`).
  - `server.new(deps) -> srv`, field `srv.status` (`"stopped"` | `"loading"` | `"ready"` | `"error"`), methods `srv:start()`, `srv:stop([detail])`, `srv:restart()`, `srv:ensure(cb(ok, err))`, `srv:touch()`, `srv:url() -> "http://127.0.0.1:<port>"`.
  - Constants `server.POLL_INTERVAL = 0.5`, `server.READY_TIMEOUT = 120`, `server.MAX_BACKOFF = 30`.
- `deps`:
  - `settings() -> table`, `paths` (table as above), `threads` (number)
  - `fileExists(path) -> boolean`
  - `killStale(serverPath, port)` — kills a leftover server from a previous Hammerspoon session
  - `spawn(path, args, onExit(exitCode, stderr)) -> handle | nil, err` — `handle.terminate()` sends SIGTERM
  - `httpGet(url, cb(statusCode))` — status `-1`/`0` on connection failure
  - `after(seconds, fn) -> timer` (`timer:stop()`)
  - `onStatus(status, detail)` — detail is the model name for loading/ready, a message for error/stopped
- Behaviour:
  - Missing server binary, model or VAD file → `error` with the path, no retry loop. Spawn failure → `error`, no retry.
  - Unexpected exit → `error` with the last stderr line, restart after 1 s, doubling to 30 s; backoff resets once ready.
  - `restart()` waits for the old process to exit before spawning (avoids port-in-use crashes).
  - Model not ready within `READY_TIMEOUT` → terminate, `error`, no retry.
  - `idleUnloadMinutes > 0` → stop after that much idle time; `ensure()` reloads on demand and resets the idle timer.
  - Results from stale health checks or old processes never change the current state.

- [ ] **Step 1: Write the failing tests `tests/test_server.lua`**

```lua
local server = require("dictation.server")

local function harness()
  local h = { now = 0, timers = {}, spawned = {}, gets = {}, statuses = {}, files = {}, killed = 0 }
  h.settings = { model = "large-v3", serverPort = 8178, idleUnloadMinutes = 0 }
  for _, f in ipairs({ "/bin/ws", "/m/vad.bin", "/m/ggml-large-v3.bin", "/m/ggml-large-v3-turbo.bin" }) do
    h.files[f] = true
  end
  local deps = {
    settings = function() return h.settings end,
    paths = {
      server = "/bin/ws",
      vadModel = "/m/vad.bin",
      model = function(n) return "/m/ggml-" .. n .. ".bin" end,
    },
    threads = 8,
    fileExists = function(p) return h.files[p] == true end,
    killStale = function() h.killed = h.killed + 1 end,
    spawn = function(path, args, onExit)
      if h.spawnFails then return nil, h.spawnFails end
      local p = { path = path, args = args, onExit = onExit }
      p.terminate = function() p.terminated = true end
      h.spawned[#h.spawned + 1] = p
      return p
    end,
    httpGet = function(url, cb) h.gets[#h.gets + 1] = { url = url, cb = cb } end,
    after = function(sec, fn)
      local t = { at = h.now + sec, fn = fn }
      function t:stop() self.stopped = true end
      h.timers[#h.timers + 1] = t
      return t
    end,
    onStatus = function(s, detail)
      h.statuses[#h.statuses + 1] = s
      h.detail = detail
    end,
  }

  -- answer the most recent health check
  function h.answer(code)
    local g = table.remove(h.gets)
    g.cb(code)
  end

  function h.advance(sec)
    h.now = h.now + sec
    local i = 1
    while i <= #h.timers do
      local t = h.timers[i]
      if not t.stopped and not t.fired and t.at <= h.now then
        t.fired = true
        t.fn()
      end
      i = i + 1
    end
  end

  h.srv = server.new(deps)
  return h
end

test("args", function()
  eq(server.args { model = "/m/a.bin", vadModel = "/m/v.bin", port = 8178, threads = 8 },
    { "-m", "/m/a.bin", "--host", "127.0.0.1", "--port", "8178", "-t", "8",
      "--vad", "--vad-model", "/m/v.bin", "-nt", "-sns" })
end)

test("args formats a float port from JSON as an integer", function()
  eq(server.args({ model = "a", vadModel = "v", port = 8178.0, threads = 4 })[6], "8178")
end)

test("start: loading, polls health until 200, then ready", function()
  local h = harness()
  h.srv:start()
  eq(#h.spawned, 1)
  eq(h.spawned[1].path, "/bin/ws")
  eq(h.spawned[1].args[2], "/m/ggml-large-v3.bin")
  eq(h.srv.status, "loading")
  eq(h.gets[1].url, "http://127.0.0.1:8178/health")
  h.answer(503)
  eq(#h.gets, 0)
  h.advance(server.POLL_INTERVAL)
  eq(#h.gets, 1)
  h.answer(200)
  eq(h.srv.status, "ready")
  eq(h.statuses, { "loading", "ready" })
  eq(h.detail, "large-v3")
  eq(h.killed, 1)
end)

test("start is a no-op while loading or ready", function()
  local h = harness()
  h.srv:start()
  h.srv:start()
  h.answer(200)
  h.srv:start()
  eq(#h.spawned, 1)
end)

test("ensure waits for ready, then answers immediately", function()
  local h = harness()
  local results = {}
  h.srv:ensure(function(ok) results[#results + 1] = ok end)
  eq(#h.spawned, 1)
  eq(results, {})
  h.answer(200)
  eq(results, { true })
  h.srv:ensure(function(ok) results[#results + 1] = ok end)
  eq(results, { true, true })
  eq(#h.spawned, 1)
end)

test("missing model: error, no spawn, no retry, waiter told why", function()
  local h = harness()
  h.files["/m/ggml-large-v3.bin"] = nil
  local got
  h.srv:ensure(function(ok, err) got = { ok, err } end)
  eq(#h.spawned, 0)
  eq(h.srv.status, "error")
  eq(got[1], false)
  truthy(got[2]:find("ggml-large-v3.bin", 1, true), got[2])
  h.advance(60)
  eq(#h.spawned, 0)
end)

test("spawn failure reports error", function()
  local h = harness()
  h.spawnFails = "permission denied"
  h.srv:start()
  eq(h.srv.status, "error")
  truthy(h.detail:find("permission denied", 1, true), h.detail)
end)

test("unexpected exit: error with last stderr line, restart with backoff", function()
  local h = harness()
  h.srv:start()
  h.answer(200)
  h.spawned[1].onExit(134, "loading model\nGGML_ASSERT failed\n")
  eq(h.srv.status, "error")
  truthy(h.detail:find("GGML_ASSERT failed", 1, true), h.detail)
  h.advance(1)
  eq(#h.spawned, 2)
  h.spawned[2].onExit(1, "bind failed")
  h.advance(1)
  eq(#h.spawned, 2) -- backoff is now 2 s
  h.advance(1)
  eq(#h.spawned, 3)
  h.answer(200)
  eq(h.srv.status, "ready")
  h.spawned[3].onExit(1, "x")
  h.advance(1)
  eq(#h.spawned, 4) -- backoff reset after ready
end)

test("waiters receive the crash error", function()
  local h = harness()
  local got
  h.srv:ensure(function(ok, err) got = { ok, err } end)
  h.spawned[1].onExit(1, "out of memory")
  eq(got[1], false)
  truthy(got[2]:find("out of memory", 1, true), got[2])
end)

test("stop terminates; the later exit does not restart", function()
  local h = harness()
  h.srv:start()
  h.answer(200)
  h.srv:stop()
  eq(h.spawned[1].terminated, true)
  eq(h.srv.status, "stopped")
  h.spawned[1].onExit(0, "")
  h.advance(60)
  eq(#h.spawned, 1)
  eq(h.srv.status, "stopped")
end)

test("restart waits for the old process to exit, then uses the new model", function()
  local h = harness()
  h.srv:start()
  h.answer(200)
  h.settings.model = "large-v3-turbo"
  h.srv:restart()
  eq(#h.spawned, 1)
  h.spawned[1].onExit(0, "")
  eq(#h.spawned, 2)
  eq(h.spawned[2].args[2], "/m/ggml-large-v3-turbo.bin")
end)

test("restart from stopped starts immediately", function()
  local h = harness()
  h.srv:restart()
  eq(#h.spawned, 1)
end)

test("health answer after stop is ignored", function()
  local h = harness()
  h.srv:start()
  h.srv:stop()
  h.answer(200)
  eq(h.srv.status, "stopped")
end)

test("load timeout: terminate, error, waiter told", function()
  local h = harness()
  local got
  h.srv:ensure(function(ok, err) got = { ok, err } end)
  for _ = 1, server.READY_TIMEOUT / server.POLL_INTERVAL do
    h.answer(-1)
    h.advance(server.POLL_INTERVAL)
  end
  eq(h.srv.status, "error")
  eq(h.spawned[1].terminated, true)
  eq(got[1], false)
  truthy(got[2]:find("did not become ready", 1, true), got[2])
end)

test("idle unload stops the server; ensure reloads it", function()
  local h = harness()
  h.settings.idleUnloadMinutes = 1
  h.srv:start()
  h.answer(200)
  h.advance(59)
  eq(h.srv.status, "ready")
  h.advance(1)
  eq(h.srv.status, "stopped")
  eq(h.spawned[1].terminated, true)
  h.srv:ensure(function() end)
  eq(#h.spawned, 1) -- old process still exiting
  h.spawned[1].onExit(0, "")
  eq(#h.spawned, 2)
end)

test("ensure resets the idle timer", function()
  local h = harness()
  h.settings.idleUnloadMinutes = 1
  h.srv:start()
  h.answer(200)
  h.advance(50)
  h.srv:ensure(function() end)
  h.advance(50)
  eq(h.srv.status, "ready")
  h.advance(10)
  eq(h.srv.status, "stopped")
end)

test("idleUnloadMinutes 0 never unloads", function()
  local h = harness()
  h.srv:start()
  h.answer(200)
  h.advance(100000)
  eq(h.srv.status, "ready")
end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test`
Expected: FAIL — `tests/test_server.lua (load error) … module 'dictation.server' not found`.

- [ ] **Step 3: Write `src/dictation/server.lua`**

```lua
-- whisper-server process lifecycle. Side effects are injected (real ones in platform.lua).
local M = {}

M.POLL_INTERVAL = 0.5
M.READY_TIMEOUT = 120
M.MAX_BACKOFF = 30

function M.args(o)
  return {
    "-m", o.model, "--host", "127.0.0.1", "--port", string.format("%d", o.port),
    "-t", string.format("%d", o.threads),
    "--vad", "--vad-model", o.vadModel, "-nt", "-sns",
  }
end

local Srv = {}
Srv.__index = Srv

function M.new(deps)
  return setmetatable({ deps = deps, status = "stopped", gen = 0, waiters = {}, backoff = 1 }, Srv)
end

local function stopTimer(self, name)
  if self[name] then
    self[name]:stop()
    self[name] = nil
  end
end

function Srv:setStatus(status, detail)
  self.status = status
  self.deps.onStatus(status, detail)
end

function Srv:flush(ok, err)
  local waiters = self.waiters
  self.waiters = {}
  for _, cb in ipairs(waiters) do cb(ok, err) end
end

function Srv:url()
  return "http://127.0.0.1:" .. string.format("%d", self.port or self.deps.settings().serverPort)
end

function Srv:fail(msg, retry)
  self:setStatus("error", msg)
  self:flush(false, msg)
  if retry then
    local delay = self.backoff
    self.backoff = math.min(self.backoff * 2, M.MAX_BACKOFF)
    self.restartTimer = self.deps.after(delay, function()
      self.restartTimer = nil
      self:start()
    end)
  end
end

-- Terminate the current process (if any); its exit callback will be ignored.
function Srv:kill()
  stopTimer(self, "pollTimer")
  stopTimer(self, "idleTimer")
  self.gen = self.gen + 1
  if self.handle then
    self.dying = true
    self.handle.terminate()
    self.handle = nil
  end
end

function Srv:start()
  if self.status == "loading" or self.status == "ready" then return end
  stopTimer(self, "restartTimer")
  if self.dying then
    self.startWhenOldExits = true
    return
  end
  local d = self.deps
  local s = d.settings()
  local model = d.paths.model(s.model)
  for _, f in ipairs({ d.paths.server, model, d.paths.vadModel }) do
    if not d.fileExists(f) then
      return self:fail("Missing file: " .. f .. " (run scripts/install.sh)", false)
    end
  end
  d.killStale(d.paths.server, s.serverPort)
  self.gen = self.gen + 1
  local gen = self.gen
  self.port, self.model = s.serverPort, s.model
  local handle, err = d.spawn(d.paths.server,
    M.args { model = model, vadModel = d.paths.vadModel, port = s.serverPort, threads = d.threads },
    function(code, stderr) self:exited(gen, code, stderr) end)
  if not handle then
    return self:fail("Could not start whisper-server: " .. tostring(err), false)
  end
  self.handle = handle
  self.polls = 0
  self:setStatus("loading", s.model)
  self:poll(gen)
end

function Srv:poll(gen)
  self.deps.httpGet(self:url() .. "/health", function(code)
    if gen ~= self.gen or self.status ~= "loading" then return end
    if code == 200 then
      self.backoff = 1
      self:setStatus("ready", self.model)
      self:touch()
      self:flush(true)
      return
    end
    self.polls = self.polls + 1
    if self.polls * M.POLL_INTERVAL >= M.READY_TIMEOUT then
      self:kill()
      return self:fail("whisper-server did not become ready in " .. M.READY_TIMEOUT .. " s", false)
    end
    self.pollTimer = self.deps.after(M.POLL_INTERVAL, function()
      self.pollTimer = nil
      self:poll(gen)
    end)
  end)
end

function Srv:exited(gen, code, stderr)
  if gen ~= self.gen then
    -- a process we terminated on purpose
    self.dying = false
    if self.startWhenOldExits then
      self.startWhenOldExits = false
      self:start()
    end
    return
  end
  self.handle = nil
  stopTimer(self, "pollTimer")
  stopTimer(self, "idleTimer")
  local last = (stderr or ""):match("([^\n]+)\n*$") or ""
  self:fail(string.format("whisper-server exited (code %s) %s", tostring(code), last), true)
end

function Srv:stop(detail)
  stopTimer(self, "restartTimer")
  self.startWhenOldExits = false
  self:kill()
  self:setStatus("stopped", detail)
  self:flush(false, "whisper-server stopped")
end

function Srv:restart()
  self:stop()
  self:start()
end

function Srv:ensure(cb)
  if self.status == "ready" then
    self:touch()
    return cb(true)
  end
  self.waiters[#self.waiters + 1] = cb
  if self.status ~= "loading" then self:start() end
end

function Srv:touch()
  stopTimer(self, "idleTimer")
  local minutes = self.deps.settings().idleUnloadMinutes
  if minutes > 0 and self.status == "ready" then
    self.idleTimer = self.deps.after(minutes * 60, function()
      self.idleTimer = nil
      self:stop("unloaded after idle")
    end)
  end
end

return M
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test`
Expected: `90 passed, 0 failed`; Python `OK`.

- [ ] **Step 5: Commit**

```bash
git add src/dictation/server.lua tests/test_server.lua
git commit -m "Add whisper-server lifecycle manager

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Transcriber and history

**Files:**
- Create: `src/dictation/transcriber.lua`
- Create: `src/dictation/history.lua`
- Test: `tests/test_transcriber.lua`, `tests/test_history.lua`

**Interfaces:**
- Consumes: the `srv` object from Task 7 (`srv:ensure(cb(ok, err))`, `srv:restart()`, `srv:url()`).
- Produces:
  - `transcriber.curlArgs{ path, url, language, prompt, timeout } -> list` (uses `--form-string` for text fields so a prompt starting with `@` or `<` is never read as a file).
  - `transcriber.parse(exitCode, stdout, decode) -> text` | `nil, kind, message`, where `kind` is `"connect"` (curl exit 7, 52, 56), `"timeout"` (28), `"server"` (JSON has `error`, or another curl failure) or `"bad-response"` (not JSON / no `text`).
  - `transcriber.new{ server, runCurl, settings, prompt, decode } -> t`; `t:transcribe(path, cb)` calls `cb(text)` or `cb(nil, message)`. `runCurl(args, cb(exitCode, stdout, stderr))`; `settings()` (uses `language`); `prompt() -> string`. On a `connect` failure it calls `server:restart()`, waits on `server:ensure`, and retries once.
  - `transcriber.CURL_TIMEOUT = 110` (below the controller's 120 s watchdog).
  - `history.format(text, time) -> string` — `"YYYY-MM-DD HH:MM:SS\t<text>\n"`, newlines in text replaced with spaces.
  - `history.append(path, text, [time]) -> true | nil, err`.

- [ ] **Step 1: Write the failing tests `tests/test_transcriber.lua`**

```lua
local transcriber = require("dictation.transcriber")

local function decode(s)
  -- tiny decoder for the two shapes the tests use
  local text = s:match('^{"text":"(.*)"}$')
  if text then return { text = text } end
  local err = s:match('^{"error":"(.*)"}$')
  if err then return { error = err } end
  error("not json")
end

test("curlArgs", function()
  eq(transcriber.curlArgs { path = "/tmp/a.wav", url = "http://127.0.0.1:8178", language = "uk",
      prompt = "@Стиль", timeout = 110 },
    { "-sS", "--max-time", "110", "-F", "file=@/tmp/a.wav",
      "--form-string", "language=uk", "--form-string", "temperature=0.0",
      "--form-string", "response_format=json", "--form-string", "prompt=@Стиль",
      "http://127.0.0.1:8178/inference" })
end)

test("curlArgs omits an empty prompt", function()
  local args = transcriber.curlArgs { path = "a", url = "u", language = "en", prompt = "", timeout = 5 }
  for _, a in ipairs(args) do truthy(not a:find("^prompt="), a) end
end)

test("parse success", function()
  eq(transcriber.parse(0, '{"text":" Привіт "}', decode), " Привіт ")
end)

test("parse classifies failures", function()
  local _, k1 = transcriber.parse(7, "", decode)
  eq(k1, "connect")
  local _, k2 = transcriber.parse(52, "", decode)
  eq(k2, "connect")
  local _, k3, m3 = transcriber.parse(28, "", decode)
  eq(k3, "timeout")
  truthy(m3:find("timed out", 1, true), m3)
  local _, k4, m4 = transcriber.parse(0, '{"error":"failed to read audio"}', decode)
  eq(k4, "server")
  truthy(m4:find("failed to read audio", 1, true), m4)
  local _, k5 = transcriber.parse(0, "<html>", decode)
  eq(k5, "bad-response")
  local _, k6 = transcriber.parse(22, "", decode)
  eq(k6, "server")
end)

local function harness()
  local h = { runs = {}, restarts = 0, ensures = 0 }
  h.server = {
    ensure = function(_, cb) h.ensures = h.ensures + 1; cb(h.ensureOk ~= false, h.ensureErr) end,
    restart = function() h.restarts = h.restarts + 1 end,
    url = function() return "http://127.0.0.1:8178" end,
  }
  h.t = transcriber.new {
    server = h.server,
    runCurl = function(args, cb) h.runs[#h.runs + 1] = args; cb(table.unpack(table.remove(h.replies, 1))) end,
    settings = function() return { language = "uk" } end,
    prompt = function() return "P" end,
    decode = decode,
  }
  return h
end

test("transcribe success", function()
  local h = harness()
  h.replies = { { 0, '{"text":"ok"}', "" } }
  local got
  h.t:transcribe("/tmp/a.wav", function(text, err) got = { text, err } end)
  eq(got, { "ok", nil })
  eq(#h.runs, 1)
  eq(h.runs[1][#h.runs[1]], "http://127.0.0.1:8178/inference")
end)

test("transcribe reports server not ready", function()
  local h = harness()
  h.ensureOk, h.ensureErr = false, "Missing file: model"
  local got
  h.t:transcribe("a", function(text, err) got = { text, err } end)
  eq(got, { nil, "Missing file: model" })
  eq(#h.runs, 0)
end)

test("transcribe restarts the server and retries once on connection failure", function()
  local h = harness()
  h.replies = { { 7, "", "Connection refused" }, { 0, '{"text":"ok"}', "" } }
  local got
  h.t:transcribe("a", function(text, err) got = { text, err } end)
  eq(got, { "ok", nil })
  eq(h.restarts, 1)
  eq(#h.runs, 2)
end)

test("transcribe gives up after the retry fails", function()
  local h = harness()
  h.replies = { { 7, "", "" }, { 7, "", "" } }
  local got
  h.t:transcribe("a", function(text, err) got = { text, err } end)
  eq(got[1], nil)
  truthy(got[2]:find("could not reach whisper-server", 1, true), got[2])
  eq(#h.runs, 2)
end)

test("server errors are not retried", function()
  local h = harness()
  h.replies = { { 0, '{"error":"bad wav"}', "" } }
  local got
  h.t:transcribe("a", function(text, err) got = { text, err } end)
  truthy(got[2]:find("bad wav", 1, true), got[2])
  eq(h.restarts, 0)
end)
```

- [ ] **Step 2: Write the failing tests `tests/test_history.lua`**

```lua
local history = require("dictation.history")

test("format puts timestamp and flattens newlines", function()
  local t = os.time { year = 2026, month = 10, day = 5, hour = 9, min = 3, sec = 7 }
  eq(history.format("рядок 1\nрядок 2", t), "2026-10-05 09:03:07\tрядок 1 рядок 2\n")
end)

test("append adds lines to the file", function()
  local path = os.tmpname()
  eq(history.append(path, "один", 0), true)
  eq(history.append(path, "два", 0), true)
  local f = io.open(path)
  local text = f:read("a")
  f:close()
  os.remove(path)
  local _, lines = text:gsub("\n", "")
  eq(lines, 2)
  truthy(text:find("\tодин\n", 1, true) and text:find("\tдва\n", 1, true))
end)

test("append reports an unwritable path", function()
  local ok, err = history.append("/nonexistent-dir/x.log", "a")
  eq(ok, nil)
  truthy(err)
end)
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `make test`
Expected: FAIL — load errors for `dictation.transcriber` and `dictation.history`.

- [ ] **Step 4: Write `src/dictation/transcriber.lua`**

```lua
-- Sends a WAV to the local whisper-server and returns the text.
local M = {}

M.CURL_TIMEOUT = 110

local CONNECT = { [7] = true, [52] = true, [56] = true }

function M.curlArgs(o)
  local args = {
    "-sS", "--max-time", string.format("%d", o.timeout), "-F", "file=@" .. o.path,
    "--form-string", "language=" .. o.language,
    "--form-string", "temperature=0.0",
    "--form-string", "response_format=json",
  }
  if o.prompt and o.prompt ~= "" then
    args[#args + 1] = "--form-string"
    args[#args + 1] = "prompt=" .. o.prompt
  end
  args[#args + 1] = o.url .. "/inference"
  return args
end

function M.parse(exitCode, stdout, decode)
  if CONNECT[exitCode] then return nil, "connect", "could not reach whisper-server" end
  if exitCode == 28 then return nil, "timeout", "whisper-server timed out" end
  if exitCode ~= 0 then return nil, "server", "curl failed with code " .. tostring(exitCode) end
  local ok, body = pcall(decode, stdout)
  if not ok or type(body) ~= "table" then
    return nil, "bad-response", "unexpected response from whisper-server"
  end
  if body.error then return nil, "server", "whisper-server: " .. tostring(body.error) end
  if type(body.text) ~= "string" then
    return nil, "bad-response", "unexpected response from whisper-server"
  end
  return body.text
end

local T = {}
T.__index = T

function M.new(deps)
  return setmetatable({ deps = deps }, T)
end

function T:transcribe(path, cb, retried)
  local d = self.deps
  d.server:ensure(function(ready, err)
    if not ready then return cb(nil, err) end
    local args = M.curlArgs {
      path = path, url = d.server:url(), language = d.settings().language,
      prompt = d.prompt(), timeout = M.CURL_TIMEOUT,
    }
    d.runCurl(args, function(code, stdout)
      local text, kind, message = M.parse(code, stdout, d.decode)
      if text then return cb(text) end
      if kind == "connect" and not retried then
        d.server:restart()
        return self:transcribe(path, cb, true)
      end
      cb(nil, message)
    end)
  end)
end

return M
```

- [ ] **Step 5: Write `src/dictation/history.lua`**

```lua
-- Every transcript is appended here so text is never lost if a paste misses.
local M = {}

function M.format(text, time)
  return os.date("%Y-%m-%d %H:%M:%S", time) .. "\t" .. text:gsub("[\r\n]+", " ") .. "\n"
end

function M.append(path, text, time)
  local f, err = io.open(path, "a")
  if not f then return nil, err end
  f:write(M.format(text, time or os.time()))
  f:close()
  return true
end

return M
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `make test`
Expected: `102 passed, 0 failed`; Python `OK`.

- [ ] **Step 7: Commit**

```bash
git add src/dictation/transcriber.lua src/dictation/history.lua tests/test_transcriber.lua tests/test_history.lua
git commit -m "Add transcriber client with retry and transcript history

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Menu bar model

**Files:**
- Create: `src/dictation/menubar.lua`
- Test: `tests/test_menubar.lua`

**Interfaces:**
- Consumes: `config.MODES`, `config.MODELS`, `config.LANGUAGES` (Task 5).
- Produces:
  - `menubar.title(state, serverStatus) -> string`: `"🔴"` while recording, `"⏳"` while transcribing; when idle, `"🎙"`, or `"🎙⚠"` if the server status is `"error"`.
  - `menubar.statusLine(view) -> string`.
  - `menubar.build(view, actions) -> list of hs.menubar item tables` (`{title=, fn=, checked=, disabled=, menu=}`; separator `{title="-"}`).
  - `view = { state, serverStatus, serverDetail, settings, installedModels = {name=true,...}, configErrors = {strings} }`.
  - `actions = { setMode(m), setModel(m), setLanguage(l), editDictionary(), editSettings(), reload(), restartServer(), openHistory(), quit() }`.
  - `menubar.create() -> { update(view, actions), delete() }` — thin `hs.menubar` wrapper (requires `hs`; not unit-tested).

- [ ] **Step 1: Write the failing tests `tests/test_menubar.lua`**

```lua
local menubar = require("dictation.menubar")

local function view(over)
  local v = {
    state = "idle", serverStatus = "ready", serverDetail = "large-v3",
    settings = { mode = "toggle", model = "large-v3", language = "uk" },
    installedModels = { ["large-v3"] = true },
    configErrors = {},
  }
  for k, x in pairs(over or {}) do v[k] = x end
  return v
end

local calls
local actions = setmetatable({}, {
  __index = function(_, name)
    return function(arg) calls[#calls + 1] = name .. "(" .. tostring(arg) .. ")" end
  end,
})

local function find(items, title)
  for _, it in ipairs(items) do
    if it.title == title then return it end
  end
end

test("title reflects state and server error", function()
  eq(menubar.title("idle", "ready"), "🎙")
  eq(menubar.title("idle", "error"), "🎙⚠")
  eq(menubar.title("recording", "ready"), "🔴")
  eq(menubar.title("transcribing", "loading"), "⏳")
end)

test("status line for each situation", function()
  eq(menubar.statusLine(view()), "Ready — large-v3")
  eq(menubar.statusLine(view { serverStatus = "loading" }), "Loading model large-v3…")
  eq(menubar.statusLine(view { serverStatus = "error", serverDetail = "Missing file: x" }),
    "Error: Missing file: x")
  eq(menubar.statusLine(view { serverStatus = "stopped", serverDetail = "unloaded after idle" }),
    "Model unloaded — loads on next use")
  eq(menubar.statusLine(view { state = "recording" }), "Recording… (Esc to cancel)")
  eq(menubar.statusLine(view { state = "transcribing" }), "Transcribing…")
end)

test("long error details are shortened", function()
  local line = menubar.statusLine(view { serverStatus = "error", serverDetail = string.rep("x", 200) })
  truthy(utf8.len(line) <= 90, tostring(utf8.len(line)))
end)

test("menu has status, submenus and actions in order", function()
  local items = menubar.build(view(), actions)
  local titles = {}
  for _, it in ipairs(items) do titles[#titles + 1] = it.title end
  eq(titles, { "Ready — large-v3", "-", "Mode", "Model", "Language", "-",
    "Edit dictionary…", "Edit settings…", "Reload config", "Restart whisper server",
    "Open history", "-", "Quit dictation" })
  eq(items[1].disabled, true)
end)

test("mode submenu checks current mode and calls setMode", function()
  calls = {}
  local mode = find(menubar.build(view(), actions), "Mode").menu
  eq(mode[1].title, "Toggle")
  eq(mode[1].checked, true)
  eq(mode[2].title, "Hold to talk")
  eq(mode[2].checked, false)
  mode[2].fn()
  eq(calls, { "setMode(hold)" })
end)

test("language submenu", function()
  calls = {}
  local lang = find(menubar.build(view(), actions), "Language").menu
  eq({ lang[1].title, lang[2].title, lang[3].title }, { "Ukrainian", "English", "Auto-detect" })
  eq(lang[1].checked, true)
  lang[3].fn()
  eq(calls, { "setLanguage(auto)" })
end)

test("model submenu lists installed models only", function()
  calls = {}
  local model = find(menubar.build(view(), actions), "Model").menu
  eq(#model, 1)
  eq(model[1].title, "large-v3")
  eq(model[1].checked, true)

  local both = find(menubar.build(view { installedModels = { ["large-v3"] = true, ["large-v3-turbo"] = true } },
    actions), "Model").menu
  eq(#both, 2)
  both[2].fn()
  eq(calls, { "setModel(large-v3-turbo)" })
end)

test("configured but missing model is shown disabled", function()
  local model = find(menubar.build(view { installedModels = {} }, actions), "Model").menu
  eq(#model, 1)
  eq(model[1].title, "large-v3 (not downloaded)")
  eq(model[1].disabled, true)
end)

test("settings submenus are disabled while recording or transcribing", function()
  local items = menubar.build(view { state = "recording" }, actions)
  eq(find(items, "Mode").disabled, true)
  eq(find(items, "Model").disabled, true)
  eq(find(items, "Language").disabled, true)
  eq(find(items, "Restart whisper server").disabled, true)
end)

test("config errors appear under the status line", function()
  local items = menubar.build(view { configErrors = { 'settings.json: "mode" bad' } }, actions)
  eq(items[2].title, '⚠ settings.json: "mode" bad')
  eq(items[2].disabled, true)
end)

test("action items call their actions", function()
  calls = {}
  local items = menubar.build(view(), actions)
  find(items, "Edit dictionary…").fn()
  find(items, "Restart whisper server").fn()
  find(items, "Quit dictation").fn()
  eq(calls, { "editDictionary(nil)", "restartServer(nil)", "quit(nil)" })
end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test`
Expected: FAIL — `tests/test_menubar.lua (load error) … module 'dictation.menubar' not found`.

- [ ] **Step 3: Write `src/dictation/menubar.lua`**

```lua
-- Menu bar icon and dropdown. build/title/statusLine are pure; create() wraps hs.menubar.
local config = require("dictation.config")

local M = {}

local MODE_TITLES = { toggle = "Toggle", hold = "Hold to talk" }
local LANGUAGE_TITLES = { uk = "Ukrainian", en = "English", auto = "Auto-detect" }
local MAX_LINE = 90

function M.title(state, serverStatus)
  if state == "recording" then return "🔴" end
  if state == "transcribing" then return "⏳" end
  return serverStatus == "error" and "🎙⚠" or "🎙"
end

local function shorten(s)
  if utf8.len(s) and utf8.len(s) > MAX_LINE then
    return s:sub(1, utf8.offset(s, MAX_LINE - 1) - 1) .. "…"
  end
  return s
end

function M.statusLine(view)
  if view.state == "recording" then return "Recording… (Esc to cancel)" end
  if view.state == "transcribing" then return "Transcribing…" end
  local s = view.serverStatus
  if s == "loading" then return "Loading model " .. view.settings.model .. "…" end
  if s == "error" then return shorten("Error: " .. tostring(view.serverDetail)) end
  if s == "stopped" then return "Model unloaded — loads on next use" end
  return "Ready — " .. view.settings.model
end

local function choices(list, titles, current, onPick)
  local items = {}
  for _, value in ipairs(list) do
    items[#items + 1] = {
      title = titles[value] or value,
      checked = value == current,
      fn = function() onPick(value) end,
    }
  end
  return items
end

local function modelChoices(view, actions)
  local items = {}
  for _, name in ipairs(config.MODELS) do
    if view.installedModels[name] then
      items[#items + 1] = {
        title = name,
        checked = name == view.settings.model,
        fn = function() actions.setModel(name) end,
      }
    elseif name == view.settings.model then
      items[#items + 1] = { title = name .. " (not downloaded)", disabled = true }
    end
  end
  return items
end

function M.build(view, actions)
  local busy = view.state ~= "idle"
  local items = { { title = M.statusLine(view), disabled = true } }
  for _, err in ipairs(view.configErrors or {}) do
    items[#items + 1] = { title = shorten("⚠ " .. err), disabled = true }
  end
  local rest = {
    { title = "-" },
    { title = "Mode", disabled = busy,
      menu = choices(config.MODES, MODE_TITLES, view.settings.mode, actions.setMode) },
    { title = "Model", disabled = busy, menu = modelChoices(view, actions) },
    { title = "Language", disabled = busy,
      menu = choices(config.LANGUAGES, LANGUAGE_TITLES, view.settings.language, actions.setLanguage) },
    { title = "-" },
    { title = "Edit dictionary…", fn = function() actions.editDictionary() end },
    { title = "Edit settings…", fn = function() actions.editSettings() end },
    { title = "Reload config", fn = function() actions.reload() end },
    { title = "Restart whisper server", disabled = busy, fn = function() actions.restartServer() end },
    { title = "Open history", fn = function() actions.openHistory() end },
    { title = "-" },
    { title = "Quit dictation", fn = function() actions.quit() end },
  }
  for _, it in ipairs(rest) do items[#items + 1] = it end
  return items
end

function M.create()
  local item = hs.menubar.new()
  local current = { view = nil, actions = nil }
  item:setMenu(function()
    if not current.view then return {} end
    return M.build(current.view, current.actions)
  end)
  return {
    update = function(view, actions)
      current.view, current.actions = view, actions
      item:setTitle(M.title(view.state, view.serverStatus))
      item:setTooltip("Dictation: " .. M.statusLine(view))
    end,
    delete = function() item:delete() end,
  }
end

return M
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test`
Expected: `113 passed, 0 failed`; Python `OK`.

- [ ] **Step 5: Commit**

```bash
git add src/dictation/menubar.lua tests/test_menubar.lua
git commit -m "Add menu bar model and hs.menubar wrapper

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: Hammerspoon glue — platform, recorder, paster

These modules call `hs.*` directly, so they can't be unit-tested. Each is small, and it's verified in the Hammerspoon console.

**Files:**
- Create: `src/dictation/platform.lua`
- Create: `src/dictation/recorder.lua`
- Create: `src/dictation/paster.lua`

**Interfaces:**
- Consumes: `paths` (Task 3).
- Produces:
  - `platform.after(sec, fn) -> timer` (keeps a reference until it fires, so it can't be garbage-collected), `platform.fileExists(path) -> bool`, `platform.spawn(path, args, onExit(code, stderrTail)) -> {terminate=fn} | nil, err` (only the last 4 KB of output is kept), `platform.httpGet(url, cb(status))`, `platform.runCurl(args, cb(code, stdout, stderr))`, `platform.killStale(serverPath, port)`, `platform.perfCores() -> number`, `platform.keepFailed(path)`, `platform.cleanupFailed()`, `platform.sound(name)`, `platform.openInEditor(path)`.
  - `recorder.new{ recPath, onUnexpectedExit(code, stderr) } -> { start(path) -> true | false, err; stop(done); cancel() }`, matching the controller's `deps.recorder` from Task 6.
  - `paster.paste(text, app, { refocus = bool, restore = bool })`; constants `paster.REFOCUS_DELAY = 0.2`, `paster.RESTORE_DELAY = 1.0`, `paster.KEYCODE_V = 9`.

- [ ] **Step 1: Install Hammerspoon and sox**

Run: `brew list --cask hammerspoon >/dev/null 2>&1 || brew install --cask hammerspoon; brew list sox >/dev/null 2>&1 || brew install sox; open -a Hammerspoon`
Then ask the human partner to:
1. Grant **Accessibility** to Hammerspoon (System Settings → Privacy & Security → Accessibility).
2. In Hammerspoon Preferences, turn on "Launch Hammerspoon at login".

- [ ] **Step 2: Write `src/dictation/platform.lua`**

```lua
-- Thin wrappers over hs.* used by the pure modules. Requires Hammerspoon.
local paths = require("dictation.paths")

local M = {}

local live = {} -- keeps timers and tasks referenced until they finish

function M.after(sec, fn)
  local timer
  timer = hs.timer.doAfter(sec, function()
    live[timer] = nil
    fn()
  end)
  live[timer] = true
  return {
    stop = function()
      live[timer] = nil
      timer:stop()
    end,
  }
end

function M.fileExists(path)
  return hs.fs.attributes(path) ~= nil
end

local TAIL = 4096

function M.spawn(path, args, onExit)
  local tail = ""
  local task
  task = hs.task.new(path, function(code, _, stderr)
    live[task] = nil
    onExit(code, (tail .. (stderr or "")):sub(-TAIL))
  end, function(_, stdout, stderr)
    tail = (tail .. (stdout or "") .. (stderr or "")):sub(-TAIL)
    return true
  end, args)
  if not task or not task:start() then return nil, "failed to launch " .. path end
  live[task] = true
  return { terminate = function() task:terminate() end }
end

function M.httpGet(url, cb)
  hs.http.asyncGet(url, nil, function(status) cb(status) end)
end

function M.runCurl(args, cb)
  local task
  task = hs.task.new(paths.curl, function(code, stdout, stderr)
    live[task] = nil
    cb(code, stdout, stderr)
  end, args)
  if not task or not task:start() then return cb(-1, "", "failed to launch curl") end
  live[task] = true
end

-- A server left over from a crashed Hammerspoon session would hold the port.
function M.killStale(serverPath, port)
  hs.execute(string.format("/usr/bin/pkill -f '^%s .*--port %d( |$)'", serverPath, port))
end

function M.perfCores()
  local out = hs.execute("/usr/sbin/sysctl -n hw.perflevel0.physicalcpu")
  return tonumber(out) or 4
end

function M.cleanupFailed()
  if not M.fileExists(paths.failedDir) then return end
  local cutoff = os.time() - 24 * 3600
  for name in hs.fs.dir(paths.failedDir) do
    local full = paths.failedDir .. "/" .. name
    local mod = name:match("%.wav$") and hs.fs.attributes(full, "modification")
    if mod and mod < cutoff then os.remove(full) end
  end
end

-- Keep the audio of a failed transcription for 24 h.
function M.keepFailed(path)
  hs.fs.mkdir(paths.failedDir)
  os.rename(path, paths.failedDir .. "/" .. path:match("[^/]+$"))
  M.cleanupFailed()
end

local SOUNDS = { start = "Tink", done = "Pop", error = "Basso" }

function M.sound(name)
  local s = hs.sound.getByName(SOUNDS[name])
  if s then s:play() end
end

function M.openInEditor(path)
  hs.task.new("/usr/bin/open", nil, { "-t", path }):start()
end

return M
```

- [ ] **Step 3: Write `src/dictation/recorder.lua`**

```lua
-- Records 16 kHz mono 16-bit WAV with sox `rec`. Requires Hammerspoon.
local M = {}

function M.new(opts)
  local self = {}
  local task, path, stopping, onStopped

  function self.start(p)
    if not hs.fs.attributes(opts.recPath) then
      return false, "sox is not installed (brew install sox)"
    end
    -- true = show the macOS prompt if access was never decided; returns the current state
    if not hs.microphoneState(true) then
      return false, "no microphone access — System Settings → Privacy & Security → Microphone → Hammerspoon"
    end
    path, stopping, onStopped = p, false, nil
    task = hs.task.new(opts.recPath, function(code, _, stderr)
      task = nil
      local done = onStopped
      onStopped = nil
      if done then
        done()
      elseif not stopping then
        opts.onUnexpectedExit(code, stderr)
      end
    end, { "-q", "-c", "1", "-r", "16000", "-b", "16", p })
    if not task or not task:start() then
      task = nil
      return false, "could not start " .. opts.recPath
    end
    return true
  end

  -- SIGINT makes sox finish writing the WAV header before exiting.
  function self.stop(done)
    if not task then return done() end
    stopping, onStopped = true, done
    task:interrupt()
  end

  function self.cancel()
    local p = path
    self.stop(function() if p then os.remove(p) end end)
  end

  return self
end

return M
```

- [ ] **Step 4: Write `src/dictation/paster.lua`**

```lua
-- Puts text into the target app: refocus, clipboard, ⌘V, restore clipboard. Requires Hammerspoon.
local M = {}

M.REFOCUS_DELAY = 0.2
M.RESTORE_DELAY = 1.0 -- Electron apps (Slack, VS Code) read the clipboard late
M.KEYCODE_V = 9       -- physical V key; works in Ukrainian layout too (where it types «м»)

local pending = {}

local function later(sec, fn)
  local t
  t = hs.timer.doAfter(sec, function()
    pending[t] = nil
    fn()
  end)
  pending[t] = true
end

local function pressCmdV()
  hs.eventtap.event.newKeyEvent({ "cmd" }, M.KEYCODE_V, true):post()
  hs.eventtap.event.newKeyEvent({ "cmd" }, M.KEYCODE_V, false):post()
end

function M.paste(text, app, opts)
  local delay = 0
  if opts.refocus and app and app:isRunning() then
    local front = hs.application.frontmostApplication()
    if not front or front:pid() ~= app:pid() then
      app:activate()
      delay = M.REFOCUS_DELAY
    end
  end

  local saved = opts.restore and hs.pasteboard.readAllData() or nil
  hs.pasteboard.setContents(text)
  local ours = hs.pasteboard.changeCount()

  later(delay, function()
    pressCmdV()
    if not saved then return end
    later(M.RESTORE_DELAY, function()
      if hs.pasteboard.changeCount() ~= ours then return end -- user copied something since
      if next(saved) then
        hs.pasteboard.writeAllData(saved)
      else
        hs.pasteboard.clearContents()
      end
    end)
  end)
end

return M
```

- [ ] **Step 5: Verify in the Hammerspoon console**

Open the Hammerspoon Console (menu bar 🔨 → Console) and paste these one block at a time. Replace `REPO` with the absolute repo path.

```lua
package.path = "REPO/src/?.lua;REPO/src/?/init.lua;" .. package.path
for k in pairs(package.loaded) do if k:match("^dictation") then package.loaded[k] = nil end end
hs.microphoneState(true)
```
Expected: the first time, macOS asks for Microphone access for Hammerspoon. Tell the human partner to click Allow.

```lua
r = require("dictation.recorder").new{ recPath = "/opt/homebrew/bin/rec",
  onUnexpectedExit = function(c, e) print("unexpected", c, e) end }
print(r.start("/tmp/dict-test.wav"))
```
Expected: `true`. Have the human partner speak for about 3 seconds, then run:

```lua
r.stop(function() print("stopped", hs.fs.attributes("/tmp/dict-test.wav", "size")) end)
```
Expected: `stopped <size>`, where size is about 96000 bytes or more for 3 s. Then run `hs.execute("/opt/homebrew/bin/soxi /tmp/dict-test.wav")` and expect `Sample Rate : 16000`, `Channels : 1`, and a duration of about 3 s. This proves SIGINT finalized the header.

```lua
r.start("/tmp/dict-cancel.wav"); hs.timer.doAfter(1, function() r.cancel() end)
```
Expected after about 1 s: `hs.fs.attributes("/tmp/dict-cancel.wav")` returns `nil`, and no "unexpected" line was printed.

```lua
p = require("dictation.paster")
hs.pasteboard.setContents("OLD CLIPBOARD")
hs.timer.doAfter(3, function() p.paste("Привіт, pull request ✅", nil, { refocus = false, restore = true }) end)
```
Expected: within 3 s the human partner clicks into a TextEdit document. `Привіт, pull request ✅` is pasted there, and about 1 s later `hs.pasteboard.getContents()` returns `OLD CLIPBOARD`. Repeat with the **Ukrainian keyboard layout active**; the paste must still work.

- [ ] **Step 6: Commit**

```bash
git add src/dictation/platform.lua src/dictation/recorder.lua src/dictation/paster.lua
git commit -m "Add Hammerspoon platform, recorder and paster modules

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 11: Wire everything together in `init.lua`

**Files:**
- Create: `src/dictation/init.lua`

**Interfaces:**
- Consumes: every module from Tasks 3–10 using the signatures listed in their Interfaces blocks.
- Produces: `require("dictation")` returns `M` with `M.start()` and `M.stop()`; while running, it also exposes `M.ctl`, `M.srv` and `M.store` so they can be inspected from the console. The Hammerspoon loader (installed in Task 12) is:
  ```lua
  package.path = "REPO/src/?.lua;REPO/src/?/init.lua;" .. package.path
  dictation = require("dictation"); dictation.start()
  ```
- Behaviour:
  - Config changes on disk are reloaded automatically, debounced by 0.3 s through `hs.pathwatcher`, and also by "Reload config". While a dictation is in progress the reload waits and retries every 1 s.
  - The server restarts if `model` or `serverPort` changes. Hotkeys are rebound if `hotkey` or `cancelKey` changes.
  - A hotkey that can't be bound (invalid key name, or one the system reserves) shows an alert naming the key.
  - When a recording starts and the model is unloaded, the server starts warming up straight away (`srv:ensure`) so it's ready by the time you stop.
  - "Edit dictionary…" and "Edit settings…" copy the matching `examples/` file if the user file doesn't exist yet, then open it in the default text editor.
  - On a Hammerspoon reload or quit: the server is terminated, and the hotkeys and menu bar item are deleted. Any existing `hs.shutdownCallback` is preserved.

- [ ] **Step 1: Write `src/dictation/init.lua`**

```lua
-- Hammerspoon entry point: wires the modules together. Requires Hammerspoon.
local config = require("dictation.config")
local controller = require("dictation.controller")
local dictionary = require("dictation.dictionary")
local history = require("dictation.history")
local menubar = require("dictation.menubar")
local paster = require("dictation.paster")
local paths = require("dictation.paths")
local platform = require("dictation.platform")
local recorder = require("dictation.recorder")
local server = require("dictation.server")
local transcriber = require("dictation.transcriber")

local M = {}

local PROMPT_TOKENS = 200
local REPO = debug.getinfo(1, "S").source:match("^@(.*)/src/dictation/init%.lua$")

local menu, hotkey, cancelHotkey, watcher, reloadTimer
local configErrors = {}
local serverStatus, serverDetail = "stopped", nil

local function alert(msg, seconds)
  hs.alert.show("Dictation: " .. msg, seconds or 3)
end

local function installedModels()
  local found = {}
  for _, name in ipairs(config.MODELS) do
    found[name] = platform.fileExists(paths.model(name))
  end
  return found
end

local actions -- defined below; menu items call into it

local function refresh()
  if not menu then return end
  menu.update({
    state = M.ctl and M.ctl.state or "idle",
    serverStatus = serverStatus,
    serverDetail = serverDetail,
    settings = M.store.settings,
    installedModels = installedModels(),
    configErrors = configErrors,
  }, actions)
end

local function bindHotkeys()
  if hotkey then hotkey:delete() end
  if cancelHotkey then cancelHotkey:delete() end
  hotkey, cancelHotkey = nil, nil
  local s = M.store.settings

  local ok, hk = pcall(hs.hotkey.new, s.hotkey.mods, s.hotkey.key,
    function()
      if M.ctl.state == "idle" then M.srv:ensure(function() end) end
      M.ctl:hotkeyDown()
    end,
    function() M.ctl:hotkeyUp() end)
  local label = table.concat(s.hotkey.mods, "+") .. "+" .. s.hotkey.key
  if ok and hk and hk:enable() then
    hotkey = hk
  else
    alert("cannot bind hotkey " .. label .. " — change \"hotkey\" in settings.json", 6)
  end

  local okC, ck = pcall(hs.hotkey.new, {}, s.cancelKey, function() M.ctl:cancel() end)
  if okC and ck then
    cancelHotkey = ck -- enabled only while recording (controller → bindCancel)
  else
    alert("invalid cancelKey \"" .. tostring(s.cancelKey) .. "\" in settings.json", 6)
  end
end

local function reloadConfig(announce)
  if M.ctl and M.ctl.state ~= "idle" then
    reloadTimer = platform.after(1, function() reloadConfig(announce) end)
    return
  end
  local before = M.store.settings
  local ok, errors = M.store:load()
  configErrors = errors
  for _, e in ipairs(errors) do alert(e, 6) end
  local after = M.store.settings
  if before.model ~= after.model or before.serverPort ~= after.serverPort then
    M.srv:restart()
  elseif before.idleUnloadMinutes ~= after.idleUnloadMinutes then
    M.srv:touch()
  end
  if before.hotkey.key ~= after.hotkey.key
      or table.concat(before.hotkey.mods, "+") ~= table.concat(after.hotkey.mods, "+")
      or before.cancelKey ~= after.cancelKey then
    bindHotkeys()
  end
  if ok and announce then alert("config reloaded") end
  refresh()
end

local function editFile(path, example)
  if not platform.fileExists(path) then
    hs.execute(string.format("/bin/mkdir -p '%s' && /bin/cp -n '%s/examples/%s' '%s'",
      paths.configDir, REPO, example, path))
  end
  platform.openInEditor(path)
end

local function updateSetting(key, value)
  local ok, err = M.store:update(key, value)
  if not ok then alert(err, 6) end
  refresh()
  return ok
end

actions = {
  setMode = function(m) updateSetting("mode", m) end,
  setLanguage = function(l) updateSetting("language", l) end,
  setModel = function(m)
    if m ~= M.store.settings.model and updateSetting("model", m) then M.srv:restart() end
  end,
  editDictionary = function() editFile(paths.dictionary, "dictionary.json") end,
  editSettings = function() editFile(paths.settings, "settings.json") end,
  reload = function() reloadConfig(true) end,
  restartServer = function() M.srv:restart() end,
  openHistory = function()
    if not platform.fileExists(paths.history) then history.append(paths.history, "(history started)") end
    platform.openInEditor(paths.history)
  end,
  quit = function() M.stop() end,
}

function M.start()
  if M.ctl then M.stop() end
  hs.execute(string.format("/bin/mkdir -p '%s' '%s'", paths.configDir, paths.dataDir))

  local readJson, writeJson = config.jsonFileIo(hs.json.decode,
    function(t) return hs.json.encode(t, true) end)
  M.store = config.newStore {
    readJson = readJson, writeJson = writeJson,
    settingsPath = paths.settings, dictionaryPath = paths.dictionary,
  }
  local _, errors = M.store:load()
  configErrors = errors
  for _, e in ipairs(errors) do alert(e, 6) end

  local function settings() return M.store.settings end

  M.srv = server.new {
    settings = settings, paths = paths, threads = platform.perfCores(),
    fileExists = platform.fileExists, killStale = platform.killStale,
    spawn = platform.spawn, httpGet = platform.httpGet, after = platform.after,
    onStatus = function(status, detail)
      serverStatus, serverDetail = status, detail
      if status == "error" then alert(detail, 6) end
      refresh()
    end,
  }

  local trans = transcriber.new {
    server = M.srv, runCurl = platform.runCurl, settings = settings, decode = hs.json.decode,
    prompt = function()
      return dictionary.buildPrompt(M.store.settings.stylePrompt, M.store.dictionary.terms, PROMPT_TOKENS)
    end,
  }

  local rec = recorder.new {
    recPath = paths.rec,
    onUnexpectedExit = function(code, stderr) M.ctl:recorderExited(code, stderr) end,
  }

  M.ctl = controller.new {
    settings = settings,
    clock = hs.timer.secondsSinceEpoch,
    after = platform.after,
    tempWav = paths.tempWav,
    frontApp = hs.application.frontmostApplication,
    recorder = rec,
    transcribe = function(path, cb) trans:transcribe(path, cb) end,
    process = function(text) return dictionary.process(text, M.store.dictionary) end,
    paste = function(text, app)
      paster.paste(text, app, {
        refocus = M.store.settings.refocusOriginalApp,
        restore = M.store.settings.restoreClipboard,
      })
    end,
    history = function(text)
      local ok, err = history.append(paths.history, text)
      if not ok then print("dictation: history: " .. tostring(err)) end
    end,
    removeFile = function(path) os.remove(path) end,
    keepFailed = platform.keepFailed,
    setState = function() refresh() end,
    notify = function(msg) alert(msg) end,
    sound = function(name) if M.store.settings.sounds then platform.sound(name) end end,
    bindCancel = function(on)
      if not cancelHotkey then return end
      if on then cancelHotkey:enable() else cancelHotkey:disable() end
    end,
  }

  menu = menubar.create()
  bindHotkeys()
  refresh()

  if not hs.accessibilityState(false) then
    alert("grant Accessibility to Hammerspoon (System Settings → Privacy & Security) for hotkeys and paste", 8)
  end

  watcher = hs.pathwatcher.new(paths.configDir, function()
    if reloadTimer then reloadTimer.stop() end
    reloadTimer = platform.after(0.3, function() reloadConfig(false) end)
  end):start()

  local previous = M.previousShutdown or hs.shutdownCallback
  M.previousShutdown = previous
  hs.shutdownCallback = function()
    M.stop()
    if previous then previous() end
  end

  platform.cleanupFailed()
  M.srv:start()
end

function M.stop()
  if not M.ctl then return end
  if M.ctl.state == "recording" then M.ctl:cancel() end
  if watcher then watcher:stop() end
  if reloadTimer then reloadTimer.stop() end
  if hotkey then hotkey:delete() end
  if cancelHotkey then cancelHotkey:delete() end
  if menu then menu.delete() end
  watcher, reloadTimer, hotkey, cancelHotkey, menu = nil, nil, nil, nil, nil
  M.srv:stop()
  M.ctl = nil
end

return M
```

- [ ] **Step 2: Check that the module files compile**

Run: `for f in src/dictation/*.lua; do /opt/homebrew/opt/lua@5.4/bin/luac -p "$f" || exit 1; done && echo OK && make test`
Expected: `OK`, then all unit tests pass. The count is unchanged from Task 9.

- [ ] **Step 3: Load it in Hammerspoon by hand (the installer automates this in Task 12)**

Append this to `~/.hammerspoon/init.lua`, replacing `REPO` with the absolute repo path:
```lua
package.path = "REPO/src/?.lua;REPO/src/?/init.lua;" .. package.path
dictation = require("dictation"); dictation.start()
```
Then reload Hammerspoon from the 🔨 menu with "Reload Config".
Expected:
- A 🎙 icon appears in the menu bar.
- The dropdown's status line reads `Loading model large-v3…` and changes to `Ready — large-v3` within about 15 s.
- The Hammerspoon Console shows no Lua errors.
- `ps aux | grep whisper-server` shows one process with `--port 8178`.

- [ ] **Step 4: End-to-end smoke test**

Ask the human partner to:
1. Click into a TextEdit document.
2. Press ⌥Space and say: «Сьогодні я відкрив pull request у GitHub».
3. Press ⌥Space again.

Expected:
- The icon changes 🎙 → 🔴 → ⏳ → 🎙 and the start and done sounds play.
- The text is pasted, with `pull request` and `GitHub` in Latin script.
- `~/.local/share/dictation/history.log` has a new line containing the text.
- No `/tmp/dictation-*.wav` file is left behind.

- [ ] **Step 5: Reload and lifecycle checks**

1. Reload Hammerspoon twice. Then `pgrep -fl whisper-server` must show exactly **one** process. This proves the old server is killed and nothing is left over.
2. Choose "Quit dictation" in the menu. The icon disappears and `pgrep -fl whisper-server` shows nothing.
3. Reload Hammerspoon to bring it back.

- [ ] **Step 6: Commit**

```bash
git add src/dictation/init.lua
git commit -m "Wire dictation modules together in Hammerspoon entry point

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 12: Installer, uninstaller, README

**Files:**
- Create: `scripts/install.sh`
- Create: `scripts/uninstall.sh`
- Create: `README.md`
- Test: `tests/install_test.sh`
- Modify: `Makefile`

**Interfaces:**
- Consumes: `scripts/build-whisper.sh` and `scripts/download-models.sh` from Task 1; the loader lines from Task 11; `examples/*.json` from Task 5.
- Produces: `scripts/install.sh [--with-turbo]` and `scripts/uninstall.sh [--purge]`. Both are idempotent.
  - Both honour the environment variables `DICTATION_HOME` (default `$HOME`) and `DICTATION_SKIP_DEPS=1`, which skips brew, the build and the downloads. These exist only so the test script can run them against a temporary home directory.
  - The loader block in `~/.hammerspoon/init.lua` is wrapped in the marker lines `-- >>> dictation-tool >>>` and `-- <<< dictation-tool <<<`.

- [ ] **Step 1: Write the failing test `tests/install_test.sh`**

```bash
#!/usr/bin/env bash
# Runs install/uninstall against a temporary HOME. No brew, build or downloads.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export DICTATION_HOME="$T" DICTATION_SKIP_DEPS=1
fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$T/.hammerspoon"
printf 'hs.alert.show("mine")\n' > "$T/.hammerspoon/init.lua"

"$REPO/scripts/install.sh" >/dev/null
"$REPO/scripts/install.sh" >/dev/null   # second run must be a no-op

[[ -f "$T/.config/dictation/settings.json" ]] || fail "settings.json not created"
[[ -f "$T/.config/dictation/dictionary.json" ]] || fail "dictionary.json not created"
grep -q 'hs.alert.show("mine")' "$T/.hammerspoon/init.lua" || fail "user init.lua content lost"
[[ "$(grep -c '>>> dictation-tool >>>' "$T/.hammerspoon/init.lua")" == 1 ]] || fail "loader not added exactly once"
grep -q "$REPO/src/?.lua" "$T/.hammerspoon/init.lua" || fail "loader has wrong repo path"

echo '{"mode":"hold"}' > "$T/.config/dictation/settings.json"
"$REPO/scripts/install.sh" >/dev/null
grep -q '"hold"' "$T/.config/dictation/settings.json" || fail "installer overwrote user settings"

"$REPO/scripts/uninstall.sh" >/dev/null
grep -q 'dictation-tool' "$T/.hammerspoon/init.lua" && fail "loader not removed"
grep -q 'hs.alert.show("mine")' "$T/.hammerspoon/init.lua" || fail "uninstall removed user content"
[[ -f "$T/.config/dictation/settings.json" ]] || fail "uninstall without --purge removed config"

"$REPO/scripts/install.sh" >/dev/null
"$REPO/scripts/uninstall.sh" --purge >/dev/null
[[ -e "$T/.config/dictation" ]] && fail "--purge kept config"
[[ -e "$T/.local/share/dictation" ]] && fail "--purge kept data"

echo "install tests passed"
```

- [ ] **Step 2: Add the test to the Makefile and run it**

Replace the contents of `Makefile` with:
```makefile
LUA ?= /opt/homebrew/opt/lua@5.4/bin/lua

.PHONY: test
test:
	$(LUA) tests/run.lua
	cd tools/accuracy && python3 -m unittest -q test_evaluate
	bash tests/install_test.sh
```
Run: `chmod +x tests/install_test.sh && make test`
Expected: the Lua and Python tests pass, then the install test fails with `scripts/install.sh: No such file or directory`.

- [ ] **Step 3: Write `scripts/install.sh`**

```bash
#!/usr/bin/env bash
# Install the dictation tool. Usage: scripts/install.sh [--with-turbo]
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
H="${DICTATION_HOME:-$HOME}"
CONFIG="$H/.config/dictation"
DATA="$H/.local/share/dictation"
HS_INIT="$H/.hammerspoon/init.lua"
BEGIN="-- >>> dictation-tool >>>"
END="-- <<< dictation-tool <<<"

if [[ "${DICTATION_SKIP_DEPS:-}" != "1" ]]; then
  echo "==> Homebrew packages"
  for f in sox cmake lua@5.4; do brew list "$f" >/dev/null 2>&1 || brew install "$f"; done
  brew list --cask hammerspoon >/dev/null 2>&1 || brew install --cask hammerspoon

  echo "==> whisper-server"
  "$REPO/scripts/build-whisper.sh"

  echo "==> models"
  "$REPO/scripts/download-models.sh" "$@"
fi

echo "==> config"
mkdir -p "$CONFIG" "$DATA"
for f in settings.json dictionary.json; do
  if [[ -f "$CONFIG/$f" ]]; then
    echo "keep $CONFIG/$f"
  else
    cp "$REPO/examples/$f" "$CONFIG/$f"
    echo "new  $CONFIG/$f"
  fi
done

echo "==> Hammerspoon loader"
mkdir -p "$(dirname "$HS_INIT")"
touch "$HS_INIT"
if grep -qF -e "$BEGIN" "$HS_INIT"; then
  echo "loader already present in $HS_INIT"
else
  cat >> "$HS_INIT" <<EOF

$BEGIN
package.path = "$REPO/src/?.lua;$REPO/src/?/init.lua;" .. package.path
dictation = require("dictation"); dictation.start()
$END
EOF
  echo "added loader to $HS_INIT"
fi

cat <<'EOF'

Done. One-time steps:
  1. Open Hammerspoon (it is in /Applications) and enable "Launch Hammerspoon at login" in its Preferences.
  2. System Settings → Privacy & Security → Accessibility → enable Hammerspoon.
  3. The first recording asks for Microphone access for Hammerspoon → Allow.
  4. Hammerspoon menu (🔨) → Reload Config. A 🎙 icon appears; wait for "Ready — large-v3".
Default hotkey: ⌥Space (toggle). Change it via 🎙 → Edit settings…
EOF
```

- [ ] **Step 4: Write `scripts/uninstall.sh`**

```bash
#!/usr/bin/env bash
# Remove the dictation tool. Usage: scripts/uninstall.sh [--purge]
#   --purge also deletes settings, dictionary, history, models and the built server.
set -euo pipefail

H="${DICTATION_HOME:-$HOME}"
HS_INIT="$H/.hammerspoon/init.lua"
BEGIN="-- >>> dictation-tool >>>"
END="-- <<< dictation-tool <<<"

if [[ "${DICTATION_SKIP_DEPS:-}" != "1" ]]; then
  pkill -f "$H/.local/share/dictation/bin/whisper-server" 2>/dev/null || true
fi

if [[ -f "$HS_INIT" ]] && grep -qF -e "$BEGIN" "$HS_INIT"; then
  tmp="$(mktemp)"
  awk -v b="$BEGIN" -v e="$END" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    !skip
  ' "$HS_INIT" > "$tmp"
  mv "$tmp" "$HS_INIT"
  echo "removed loader from $HS_INIT (reload Hammerspoon to apply)"
fi

if [[ "${1:-}" == "--purge" ]]; then
  rm -rf "$H/.config/dictation" "$H/.local/share/dictation"
  echo "deleted config, history, models and whisper-server build"
else
  echo "kept ~/.config/dictation and ~/.local/share/dictation (use --purge to delete)"
fi
echo "Homebrew packages (sox, cmake, lua@5.4, hammerspoon) were left installed."
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `chmod +x scripts/install.sh scripts/uninstall.sh && make test`
Expected: the Lua and Python tests pass, then `install tests passed`.

- [ ] **Step 6: Write `README.md`**

````markdown
# dictation-tool

Local dictation for macOS. Press a hotkey, speak Ukrainian (English terms are fine mid-sentence), and the text is pasted where your cursor is. It runs entirely on your Mac using whisper.cpp (`large-v3`) on the GPU.

## Install

```bash
scripts/install.sh            # add --with-turbo to also download large-v3-turbo
```

This installs sox, cmake, lua@5.4 and Hammerspoon with Homebrew. It builds `whisper-server` (whisper.cpp v1.9.4), downloads about 3 GB of models with checksum verification, creates your config files and adds a loader to `~/.hammerspoon/init.lua`. Then:

1. Open Hammerspoon and enable "Launch Hammerspoon at login".
2. System Settings → Privacy & Security → **Accessibility** → enable Hammerspoon. This is needed for hotkeys and for pasting.
3. On the first recording, allow **Microphone** access for Hammerspoon.
4. Hammerspoon menu → Reload Config. A 🎙 icon appears in the menu bar.

Uninstall with `scripts/uninstall.sh`. Add `--purge` to also delete models, config and history.

## Use

| Mode | How |
|---|---|
| Toggle (default) | Press ⌥Space to start, press again to stop and paste |
| Hold to talk | Hold ⌥Space while speaking, release to paste |

Press **Esc** while recording to cancel. The icon shows the state: 🎙 ready · 🔴 recording · ⏳ transcribing · 🎙⚠ problem (open the menu for details).

Mode, model and language can be switched from the 🎙 menu. Every transcript is also saved to `~/.local/share/dictation/history.log` (🎙 → Open history).

## Settings — `~/.config/dictation/settings.json`

Changes are picked up automatically when you save the file. If the file has an error, the last working settings stay active and the menu shows what's wrong.

| Field | Default | Meaning |
|---|---|---|
| `mode` | `"toggle"` | `"toggle"` or `"hold"` |
| `hotkey` | `{"mods": ["alt"], "key": "space"}` | `mods`: any of `cmd`, `alt`, `ctrl`, `shift`. `key`: a single character or a name like `space`, `f13`, `return` |
| `cancelKey` | `"escape"` | Key that cancels a recording (active only while recording) |
| `model` | `"large-v3"` | `"large-v3"` (more accurate) or `"large-v3-turbo"` (faster; needs `--with-turbo`) |
| `language` | `"uk"` | `"uk"`, `"en"` or `"auto"`. Keep `"uk"` for Ukrainian with English terms — `"auto"` may translate |
| `stylePrompt` | Ukrainian sentence with English terms | Example text whisper imitates. Keep English terms in Latin script here |
| `refocusOriginalApp` | `true` | Paste into the app that was in front when you started recording |
| `restoreClipboard` | `true` | Put your previous clipboard back after pasting |
| `sounds` | `true` | Start/done/error sounds |
| `maxRecordingSeconds` | `300` | Recording stops automatically after this |
| `serverPort` | `8178` | Local port for whisper-server (127.0.0.1 only) |
| `idleUnloadMinutes` | `0` | Free the model's ~4 GB of memory after this many idle minutes (`0` = keep loaded) |

## Dictionary — `~/.config/dictation/dictionary.json`

```json
{
  "terms": ["Kubernetes", "Terraform", "pull request"],
  "replace": { "пул реквест": "pull request", "кубернетіс": "Kubernetes" },
  "dropPhrases": []
}
```

| Field | Meaning |
|---|---|
| `terms` | Words to recognize and spell correctly. They're sent to whisper as a hint, most important first; if the list is too long, terms at the end are skipped |
| `replace` | Fixes applied after transcription. Matching ignores upper/lower case and only matches whole words; the longer phrase wins. Add a rule whenever a word comes out wrong |
| `dropPhrases` | Phrases whisper sometimes invents (e.g. «Дякую за перегляд!»). They're removed when they're the last sentence. Common ones are built in |

## Troubleshooting

- **Nothing happens on the hotkey:** check the Accessibility permission. Another app may be using the same shortcut; change `hotkey`.
- **"no microphone access":** System Settings → Privacy & Security → Microphone → enable Hammerspoon.
- **🎙⚠ icon:** open the menu to see the error. Use "Restart whisper server", or re-run `scripts/install.sh` if a file is missing.
- **English words come out in Cyrillic:** add them to `terms`, and add a `replace` rule for the Cyrillic spelling.
- **Text didn't paste:** it's in history (🎙 → Open history).
- **Audio of failed transcriptions** is kept for 24 h in `~/.local/share/dictation/failed/`.

## Development

```bash
make test                       # Lua unit tests, harness tests, installer test
tools/accuracy/record.sh        # record your own test clips
tools/accuracy/evaluate.py      # compare models and prompt on those clips
```
````

- [ ] **Step 7: Run the real installer on this machine**

Run: `scripts/install.sh --with-turbo`
Expected: everything already present prints `ok` or `keep`, the loader is added once, and the final instructions are printed. If the loader from Task 11 Step 3 was added by hand, remove those two lines from `~/.hammerspoon/init.lua` first, so only the marked block remains. Then reload Hammerspoon and confirm the 🎙 icon reaches `Ready — large-v3`.

- [ ] **Step 8: Commit**

```bash
git add scripts/install.sh scripts/uninstall.sh tests/install_test.sh Makefile README.md
git commit -m "Add installer, uninstaller and README

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 13: Manual acceptance checklist

**Files:**
- Create: `docs/manual-test-checklist.md`

**Interfaces:**
- Consumes: the installed tool from Task 12.
- Produces: a checklist file with each result filled in.

- [ ] **Step 1: Write `docs/manual-test-checklist.md`**

```markdown
# Manual acceptance checklist

Date: ____  Model: ____  Result legend: ✅ pass · ❌ fail (note what happened)

| # | Scenario | Expected | Result |
|---|---|---|---|
| 1 | Toggle: ⌥Space, speak 10 s Ukrainian with 2 English terms, ⌥Space (TextEdit) | Text pasted; terms in Latin; ≤ 6 s from stop to paste | |
| 2 | Switch to Hold mode in menu; hold ⌥Space, speak, release | Text pasted; settings.json now has "mode": "hold" | |
| 3 | Hold mode: quick tap (< 0.3 s) | Nothing happens, no alert | |
| 4 | Esc while recording | "Cancelled", nothing pasted, Esc works normally afterwards in other apps | |
| 5 | Paste into Terminal, Safari/Chrome text field, Slack, VS Code | Text appears in each; clipboard restored afterwards (Review Focus 1) | |
| 6 | Start recording in Slack, switch to TextEdit, stop | Text pasted into Slack | |
| 7 | Copy something during ⏳, then dictation finishes | Your new copy stays on the clipboard (not overwritten by restore) | |
| 8 | Ukrainian keyboard layout active | Paste still works | |
| 9 | Record 2 s of silence | "Nothing recognized" or empty; no «Дякую за перегляд!» pasted | |
| 10 | `pkill -f whisper-server` then dictate | Server restarts automatically; dictation succeeds (maybe slower) | |
| 11 | Break settings.json (delete a comma), save | Alert with error; menu shows ⚠ line; dictation still works with last settings | |
| 12 | With settings.json broken, change Mode in menu | Refused with "fix it first"; broken file left as is (Review Focus 3) | |
| 13 | Fix settings.json, save | Alert gone, menu ⚠ line gone | |
| 14 | Change hotkey to {"mods":["ctrl","alt"],"key":"d"}, save | New hotkey works, ⌥Space no longer triggers | |
| 15 | Switch model to large-v3-turbo in menu | "Loading model…" then "Ready — large-v3-turbo"; dictation works | |
| 16 | Add "replace": {"тест": "TEST"}, save, say «це тест» | Pasted "це TEST" | |
| 17 | Set idleUnloadMinutes to 1, wait 70 s | Menu says "Model unloaded"; next dictation works (loads first) | |
| 18 | Revoke Microphone for Hammerspoon, press hotkey | Alert explains how to grant access; icon back to 🎙 | |
| 19 | Reload Hammerspoon 3 times | Exactly one whisper-server process (`pgrep -fl whisper-server`) | |
| 20 | Dictate 2 minutes continuously | Full text pasted, nothing cut off in the middle | |
```

- [ ] **Step 2: Go through the checklist with the human partner**

Run each scenario and fill in the Result column. For each ❌: use the superpowers:systematic-debugging skill to find the cause, fix it with a test where the code is unit-testable, and run the scenario again.

- [ ] **Step 3: Restore the defaults changed during testing**

Set `settings.json` back to `mode` `"toggle"`, `hotkey` ⌥Space, `model` `"large-v3"` and `idleUnloadMinutes` `0`, unless the human partner wants to keep their changes. Remove the `"тест"` rule from the dictionary.

- [ ] **Step 4: Run the full test suite one last time**

Run: `make test`
Expected: all Lua tests pass, Python prints `OK`, and the last line is `install tests passed`.

- [ ] **Step 5: Commit**

```bash
git add docs/manual-test-checklist.md
git commit -m "Add completed manual acceptance checklist

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```
