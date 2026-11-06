#!/usr/bin/env bash
# Install Shepit: build and sign the app into ~/Applications, download whisper.cpp large-v3-turbo and the meeting models,
# create settings and dictionary if absent, remove the old Hammerspoon loader, open the app.
# Usage: scripts/install.sh [--with-whisperkit] [--with-parakeet]   (extra models, optional)
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
H="${DICTATION_HOME:-$HOME}"
CONFIG="$H/.config/dictation"
DATA="$H/.local/share/dictation"
HS_INIT="$H/.hammerspoon/init.lua"
BEGIN="-- >>> dictation-tool >>>"
END="-- <<< dictation-tool <<<"

models=()
for arg in "$@"; do
  [[ "$arg" == "--native" ]] || models+=("$arg") # --native: accepted from the switchover period
done

if [[ "${DICTATION_SKIP_DEPS:-}" != "1" ]]; then
  echo "==> build tools"
  xcrun --find swift >/dev/null 2>&1 || { echo "Xcode or the Command Line Tools are needed: xcode-select --install" >&2; exit 1; }
  command -v cmake >/dev/null 2>&1 || brew install cmake
  echo "==> Shepit.app"
  "$REPO/scripts/build-app.sh"
  echo "==> models"
  "$REPO/scripts/download-models.sh" --with-turbo --skip-large --with-meetings ${models[@]+"${models[@]}"}
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

# The Hammerspoon version of this tool is replaced by Shepit; Hammerspoon itself stays installed.
# Only with both markers (a lone one would swallow the rest of the file); a backup first; written in
# place so a symlinked init.lua stays a symlink.
if [[ -f "$HS_INIT" ]] && grep -qxF -e "$BEGIN" "$HS_INIT" && grep -qxF -e "$END" "$HS_INIT"; then
  cp "$HS_INIT" "$HS_INIT.before-shepit"
  tmp="$(mktemp)"
  awk -v b="$BEGIN" -v e="$END" '$0 == b { skip = 1; next } $0 == e { skip = 0; next } !skip' "$HS_INIT" > "$tmp"
  cat "$tmp" > "$HS_INIT"
  rm -f "$tmp"
  echo "removed the old dictation loader from $HS_INIT (backup: init.lua.before-shepit) — choose Reload Config in Hammerspoon's menu"
fi

[[ "${DICTATION_SKIP_DEPS:-}" == "1" ]] || open "$H/Applications/Shepit.app"

cat <<'EOF'

Done. Shepit is in ~/Applications and in the menu bar (🎙); it starts at login.
  1. System Settings → Privacy & Security → Accessibility → turn on Shepit (needed to paste).
  2. Click into any text field, press ⌥Space, speak, press ⌥Space again.
     macOS asks for Microphone access for Shepit the first time → Allow.
Settings: 🎙 → Settings… (⌘,)   Help: README.md
EOF
