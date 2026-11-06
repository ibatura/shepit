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
