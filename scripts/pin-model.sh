#!/usr/bin/env bash
# Maintainer helper: download a Hugging Face model folder and write SHA-256 entries.
set -euo pipefail

if [[ "$#" -lt 4 ]]; then
  echo "usage: pin-model.sh <repo> <revision> <remote-dir> <out-manifest> [file ...]" >&2
  exit 2
fi

repo="$1" revision="$2" remote_dir="${3%/}" out_manifest="$4"
[[ "$remote_dir" != "." ]] || remote_dir=""
shift 4
[[ -n "$repo" && -n "$revision" ]] || { echo "repo and revision must not be empty" >&2; exit 2; }
api="https://huggingface.co/api/models/$repo/tree/$revision${remote_dir:+/$remote_dir}?recursive=1"
tmp="$(mktemp -d)"
manifest_tmp="$out_manifest.part"
manifest_tmp_owned=false
trap 'rm -rf "$tmp"; [[ "$manifest_tmp_owned" != true ]] || rm -f "$manifest_tmp"' EXIT
mkdir -p "$(dirname "$out_manifest")"
if ! (set -o noclobber; : > "$manifest_tmp") 2>/dev/null; then
  echo "refusing to overwrite temporary manifest: $manifest_tmp" >&2
  exit 1
fi
manifest_tmp_owned=true

files="$(curl -fLsS "$api" | jq -er --arg prefix "${remote_dir:+$remote_dir/}" --args '
  [ .[] | select(.type == "file") | .path
    | select(($ARGS.positional | length) == 0 or (IN($ARGS.positional[])))
    | if $prefix == "" then . else select(startswith($prefix)) | ltrimstr($prefix) end
  ] | .[]
' -- "$@")" || {
  echo "could not list requested files in $repo${remote_dir:+/$remote_dir} at $revision" >&2
  exit 1
}
[[ -n "$files" ]] || { echo "no files found in $repo${remote_dir:+/$remote_dir} at $revision" >&2; exit 1; }

while IFS= read -r full_path; do
  if [[ -z "$remote_dir" ]]; then
    path="$full_path"
  else
    case "$full_path" in
      "$remote_dir"/*) path="${full_path#"$remote_dir"/}" ;;
      *) echo "unexpected path outside $remote_dir: $full_path" >&2; exit 1 ;;
    esac
  fi
  [[ -n "$path" && "$path" != /* && "$path" != *".."* && "$path" != *[$'\t\n']* ]] || {
    echo "invalid model path: $path" >&2
    exit 1
  }
  mkdir -p "$tmp/$(dirname "$path")"
  if ! curl -fLsS --retry 3 -o "$tmp/$path" "https://huggingface.co/$repo/resolve/$revision/$full_path"; then
    exit 1
  fi
  sha="$(shasum -a 256 "$tmp/$path" | cut -d ' ' -f 1)"
  printf '%s  %s\n' "$sha" "$path" >> "$manifest_tmp"
done <<< "$files"

[[ -s "$manifest_tmp" ]] || { echo "empty manifest for $repo/$remote_dir" >&2; exit 1; }
mv "$manifest_tmp" "$out_manifest"
