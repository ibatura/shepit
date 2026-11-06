#!/usr/bin/env bash
# Download whisper models with SHA-256 verification.
# Usage: download-models.sh [--with-turbo] [--skip-large] [--with-whisperkit] [--with-parakeet] [--with-meetings]
#   --skip-large: don't fetch ggml-large-v3 (Shepit's default is large-v3-turbo)
#   --with-meetings: voice detection and speaker models for meeting transcripts (~25 MB)
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$HOME/.local/share/dictation/models"
HF="https://huggingface.co"
mkdir -p "$DIR"

fetch() { # file-name url   (sha256 from scripts/models/ggml.sha256, shared with the app)
  local name="$1" url="$2" dest="$DIR/$1" sha
  sha="$(awk -v f="$name" '$2 == f { print $1 }' "$REPO/scripts/models/ggml.sha256")"
  [[ "$sha" =~ ^[[:xdigit:]]{64}$ ]] || { echo "no checksum for $name in scripts/models/ggml.sha256" >&2; exit 1; }
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

parse_manifest_entry() {
  local line="$1"
  IFS=$' \t' read -r sha path extra <<< "$line"
  [[ "$sha" =~ ^[[:xdigit:]]{64}$ && -n "$path" && -z "$extra" && "$path" != /* && "$path" != *".."* ]]
}

fetch_dir() { # hf-repo revision remote-dir local-dir manifest [only-path ...]
  local repo="$1" revision="$2" remote_dir="$3" local_dir="$4" manifest="$5"
  local sha path extra line part="$local_dir.part" entry_count=0 seen_paths
  shift 5
  local -a only_paths=("$@")
  if [[ -f "$local_dir/.complete" ]]; then
    local verified=true checked=0
    seen_paths='|'
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ "$line" =~ ^[[:space:]]*$ ]] && continue
      # A bad manifest is our bug, not a bad model: stop without deleting the folder.
      parse_manifest_entry "$line" || { echo "invalid manifest entry: $line" >&2; exit 1; }
      [[ "$seen_paths" != *"|$path|"* ]] || { echo "duplicate manifest entry: $path" >&2; exit 1; }
      seen_paths+="$path|"
      if ((${#only_paths[@]})) && [[ ! " ${only_paths[*]} " == *" $path "* ]]; then
        continue
      fi
      checked=$((checked + 1))
      if ! echo "$sha  $local_dir/$path" | shasum -a 256 -c --status; then
        echo "completed model file missing or checksum mismatch: $local_dir/$path" >&2
        verified=false
        break
      fi
    done < "$manifest"
    if [[ "$verified" == true && "$checked" -gt 0 ]]; then
      echo "ok   $local_dir"
      return
    fi
    rm -r "$local_dir"
  fi
  if [[ -e "$part" ]]; then
    echo "refusing to overwrite partial download: $part" >&2
    exit 1
  fi
  mkdir -p "$part"
  seen_paths='|'
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    if ! parse_manifest_entry "$line"; then
      rm -r "$part"
      echo "invalid manifest entry: $line" >&2
      exit 1
    fi
    if [[ "$seen_paths" == *"|$path|"* ]]; then
      rm -r "$part"
      echo "duplicate manifest entry: $path" >&2
      exit 1
    fi
    seen_paths+="$path|"
    entry_count=$((entry_count + 1))
    if ((${#only_paths[@]})) && [[ ! " ${only_paths[*]} " == *" $path "* ]]; then
      continue
    fi
    mkdir -p "$part/$(dirname "$path")"
    local remote_path="${remote_dir:+$remote_dir/}$path"
    echo "get  $remote_path"
    if ! curl -fL --retry 3 -o "$part/$path" "$HF/$repo/resolve/$revision/$remote_path"; then
      rm -r "$part"
      exit 1
    fi
    if ! echo "$sha  $part/$path" | shasum -a 256 -c --status; then
      rm -r "$part"
      echo "checksum mismatch for $remote_path" >&2
      exit 1
    fi
  done < "$manifest"
  local only_path
  for only_path in ${only_paths[@]+"${only_paths[@]}"}; do
    [[ "$seen_paths" == *"|$only_path|"* ]] || { rm -r "$part"; echo "not in manifest: $only_path" >&2; exit 1; }
  done
  if [[ "$entry_count" == 0 ]]; then
    rm -r "$part"
    echo "empty manifest: $manifest" >&2
    exit 1
  fi
  [[ ! -e "$local_dir" ]] || { rm -r "$part"; echo "model folder exists without .complete: $local_dir" >&2; exit 1; }
  mv "$part" "$local_dir"
  : > "$local_dir/.complete"
}

with_turbo=false
skip_large=false
with_whisperkit=false
with_parakeet=false
with_meetings=false
for arg in "$@"; do
  case "$arg" in
    --with-turbo) with_turbo=true ;;
    --skip-large) skip_large=true ;;
    --with-whisperkit) with_whisperkit=true ;;
    --with-parakeet) with_parakeet=true ;;
    --with-meetings) with_meetings=true ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

[[ "$skip_large" == true ]] || fetch ggml-large-v3.bin "$HF/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin"
fetch ggml-silero-v6.2.0.bin "$HF/ggml-org/whisper-vad/resolve/main/ggml-silero-v6.2.0.bin"

if [[ "$with_turbo" == true ]]; then
  fetch ggml-large-v3-turbo.bin "$HF/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin"
fi

if [[ "$with_whisperkit" == true ]]; then
  revision=0f63a7800b00dd0226abd051b906c246e1907482
  fetch_dir argmaxinc/whisperkit-coreml "$revision" openai_whisper-large-v3 \
    "$DIR/whisperkit/large-v3" "$REPO/scripts/models/whisperkit-large-v3.sha256"
  fetch_dir argmaxinc/whisperkit-coreml "$revision" openai_whisper-large-v3-v20240930 \
    "$DIR/whisperkit/large-v3-turbo" "$REPO/scripts/models/whisperkit-large-v3-turbo.sha256"
  fetch_dir openai/whisper-large-v3 06f233fe06e710322aca913c1bc4249a0d71fce1 . \
    "$DIR/whisperkit/tokenizer" "$REPO/scripts/models/whisperkit-tokenizer.sha256" tokenizer.json tokenizer_config.json config.json
fi

if [[ "$with_parakeet" == true ]]; then
  fetch_dir FluidInference/parakeet-tdt-0.6b-v3-coreml 7dd20fe6b1797d35f5e3307e8b1732d9a178edfe "" \
    "$DIR/parakeet/parakeet-tdt-0.6b-v3" "$REPO/scripts/models/parakeet-tdt-0.6b-v3.sha256"
fi

if [[ "$with_meetings" == true ]]; then
  fetch_dir FluidInference/silero-vad-coreml b419383c55c110e2c9271fa6ee0ea83d03c70d96 "" \
    "$DIR/silero-vad" "$REPO/scripts/models/silero-vad.sha256"
  fetch_dir FluidInference/speaker-diarization-coreml df2625ac79a7ac6b65ad868fee6d80f320da4232 "" \
    "$DIR/diarization" "$REPO/scripts/models/diarization.sha256"
fi
