#!/usr/bin/env bash
# Remove the dictation tool (Shepit.app and the Hammerspoon loader). Usage: scripts/uninstall.sh [--purge]
#   --purge also deletes settings, dictionary, history, statistics, models and meeting notes in the default folder
#   (~/.local/share/dictation/meetings). A custom meetingsFolder is never touched.
set -euo pipefail

H="${DICTATION_HOME:-$HOME}"
HS_INIT="$H/.hammerspoon/init.lua"
BEGIN="-- >>> dictation-tool >>>"
END="-- <<< dictation-tool <<<"

APP="$H/Applications/Shepit.app"

if [[ "${DICTATION_SKIP_DEPS:-}" != "1" ]]; then
  pkill -f "$H/.local/share/dictation/bin/whisper-server" 2>/dev/null || true # left by the old Hammerspoon version
  if [[ -d "$APP" ]]; then
    "$APP/Contents/MacOS/Shepit" login-item off 2>/dev/null || true
    osascript -e 'quit app id "dev.shepit.Shepit"' >/dev/null 2>&1 || true
  fi
fi
if [[ -d "$APP" ]] || compgen -G "$H/Applications/Shepit.app.previous.*" >/dev/null; then
  rm -rf "$APP" "$H"/Applications/Shepit.app.previous.*
  echo "removed $APP and its backups"
fi

if [[ -f "$HS_INIT" ]] && grep -qxF -e "$BEGIN" "$HS_INIT" && grep -qxF -e "$END" "$HS_INIT"; then
  cp "$HS_INIT" "$HS_INIT.before-shepit"
  tmp="$(mktemp)"
  awk -v b="$BEGIN" -v e="$END" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    !skip
  ' "$HS_INIT" > "$tmp"
  cat "$tmp" > "$HS_INIT"
  rm -f "$tmp"
  echo "removed loader from $HS_INIT (reload Hammerspoon to apply)"
fi

if [[ "${1:-}" == "--purge" ]]; then
  rm -rf "$H/.config/dictation" "$H/.local/share/dictation"
  echo "deleted config, history, statistics, models and meeting notes in the default folder (a custom meetingsFolder is kept)"
else
  echo "kept ~/.config/dictation and ~/.local/share/dictation (use --purge to delete)"
fi
echo "cmake, Hammerspoon (if you had it) and the Shepit Local Signing certificate were left installed."
