#!/usr/bin/env python3
"""Compare Shepit's speech engines and prompt variants on the user's own recordings.

Reports word error rate (WER), how many Latin-script terms from the reference
text came out in Latin script, speed, load time and memory.

Usage: evaluate.py [--engines whispercpp:large-v3-turbo whisperkit:large-v3 parakeet apple] [--shepit PATH]
"""
import argparse
import json
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

RECORDINGS = Path(__file__).parent / "recordings"
SHEPIT = Path.home() / "Applications/Shepit.app/Contents/MacOS/Shepit"

# Must match examples/settings.json "stylePrompt" and examples/dictionary.json "terms".
STYLE_PROMPT = ("Сьогодні я відкрив pull request у GitHub, задеплоїв сервіс у "
                "Kubernetes і оновив README.")
DEFAULT_TERMS = ["Kubernetes", "Terraform", "pull request", "PitchBook", "Hammerspoon", "code review", "commit", "release", "stack trace", "Kibana", "feature branch", "roadmap", "deadline", "config"]

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


def parse_engine(spec):
    engine, _, model = spec.partition(":")
    return engine, model


def parse_bench(lines):
    out = {"results": []}
    for line in lines:
        event = json.loads(line)
        if event["event"] == "error":
            raise RuntimeError(event["message"])
        if event["event"] == "load":
            out["load_s"], out["resident_mb"] = event["seconds"], event["residentMB"]
        elif event["event"] == "result":
            out["results"].append((Path(event["file"]).name, event["text"], event["seconds"]))
    if "load_s" not in out or not out["results"]:
        raise RuntimeError("no results (did Shepit crash?)")
    return out


def bench_engines(args, clips, variants):
    """One `Shepit bench` run per engine and prompt variant; prints the table."""
    rows = []
    for spec in args.engines:
        engine, model = parse_engine(spec)
        # Parakeet can't be forced to a language and has no prompt; the rest run Ukrainian with both variants.
        language = "auto" if engine == "parakeet" else "uk"
        for name, prompt in variants.items():
            if engine == "parakeet" and prompt:
                continue
            cmd = [str(args.shepit), "bench", "--engine", engine, "--language", language]
            cmd += ["--model", model] if model else []
            cmd += ["--prompt", prompt] if prompt else []
            proc = subprocess.run(cmd + [str(c) for c in clips], capture_output=True, text=True)
            try:
                bench = parse_bench(proc.stdout.splitlines())
            except RuntimeError as error:
                print(f"skip {spec} / {name}: {error} {proc.stderr.strip()[-300:]}")
                continue
            errs, hits, total, secs = [], 0, 0, 0.0
            for file, text, took in bench["results"]:
                ref = normalize((RECORDINGS / file).with_suffix(".txt").read_text())
                hyp = normalize(text)
                errs.append(wer(ref, hyp))
                h, t = latin_hit_rate(ref, hyp)
                hits, total, secs = hits + h, total + t, secs + took
                print(f"[{spec} / {name}] {file}: {text}")
            rows.append((engine, model, name, sum(errs) / len(errs), hits, total, secs / len(errs),
                         bench["load_s"], bench["resident_mb"]))

    print(f"\n| engine | model | prompt | WER | Latin terms | avg s/clip | load s | resident MB |")
    print("|---|---|---|---|---|---|---|---|")
    for engine, model, name, w, h, t, s, load, mb in rows:
        print(f"| {engine} | {model or '—'} | {name} | {w:.1%} | {h}/{t} | {s:.2f} | {load:.1f} | {mb:.0f} |")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--engines", nargs="+", default=["whispercpp:large-v3-turbo"],
                    help="engine[:model] specs run through Shepit bench")
    ap.add_argument("--shepit", type=Path, default=SHEPIT)
    args = ap.parse_args()

    clips = sorted(RECORDINGS.glob("*.wav"))
    if not clips:
        sys.exit(f"no recordings in {RECORDINGS}; run record.sh first")

    variants = {"no prompt": "", "style+terms": STYLE_PROMPT + " " + ", ".join(DEFAULT_TERMS)}
    bench_engines(args, clips, variants)


if __name__ == "__main__":
    main()
