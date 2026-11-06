#!/usr/bin/env bash
# Runs install/uninstall against a temporary HOME. No brew, build or downloads.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export DICTATION_HOME="$T" DICTATION_SKIP_DEPS=1
fail() { echo "FAIL: $*" >&2; exit 1; }

# A Hammerspoon config with the old dictation loader next to the user's own lines.
mkdir -p "$T/.hammerspoon"
cat > "$T/.hammerspoon/init.lua" <<'EOF'
hs.alert.show("mine")

-- >>> dictation-tool >>>
dictation = require("dictation"); dictation.start()
-- <<< dictation-tool <<<
EOF

"$REPO/scripts/install.sh" >/dev/null
"$REPO/scripts/install.sh" >/dev/null   # second run must be a no-op

[[ -f "$T/.config/dictation/settings.json" ]] || fail "settings.json not created"
[[ -f "$T/.config/dictation/dictionary.json" ]] || fail "dictionary.json not created"
grep -q 'dictation-tool' "$T/.hammerspoon/init.lua" && fail "old Hammerspoon loader kept"
grep -q 'hs.alert.show("mine")' "$T/.hammerspoon/init.lua" || fail "user init.lua content lost"
[[ -f "$T/.hammerspoon/init.lua.before-shepit" ]] || fail "no backup of init.lua"

# A lone start marker must not swallow the rest of the file.
printf 'a\n-- >>> dictation-tool >>>\nb\n' > "$T/.hammerspoon/init.lua"
"$REPO/scripts/install.sh" >/dev/null
grep -q '^b$' "$T/.hammerspoon/init.lua" || fail "installer dropped lines after a lone marker"

echo '{"mode":"hold"}' > "$T/.config/dictation/settings.json"
"$REPO/scripts/install.sh" >/dev/null
grep -q '"hold"' "$T/.config/dictation/settings.json" || fail "installer overwrote user settings"

# Uninstall removes Shepit.app and its backups; --purge also the data (statistics included).
mkdir -p "$T/Applications/Shepit.app/Contents" "$T/Applications/Shepit.app.previous.20261019031215" "$T/Applications/Other.app"
touch "$T/.local/share/dictation/stats.sqlite"
"$REPO/scripts/uninstall.sh" >/dev/null
[[ -e "$T/Applications/Shepit.app" ]] && fail "uninstall kept Shepit.app"
[[ -e "$T/Applications/Shepit.app.previous.20261019031215" ]] && fail "uninstall kept an app backup"
[[ -d "$T/Applications/Other.app" ]] || fail "uninstall touched another app"
[[ -f "$T/.config/dictation/settings.json" ]] || fail "uninstall without --purge removed config"
[[ -f "$T/.local/share/dictation/stats.sqlite" ]] || fail "uninstall without --purge removed statistics"

"$REPO/scripts/install.sh" >/dev/null
mkdir -p "$T/.local/share/dictation/meetings" "$T/Vault/Meetings"
touch "$T/.local/share/dictation/meetings/2026-10-26 14-05.md" "$T/Vault/Meetings/2026-10-26 14-05.md"
"$REPO/scripts/uninstall.sh" --purge >/dev/null
[[ -e "$T/.config/dictation" ]] && fail "--purge kept config"
[[ -e "$T/.local/share/dictation" ]] && fail "--purge kept data (meeting notes in the default folder included)"
[[ -f "$T/Vault/Meetings/2026-10-26 14-05.md" ]] || fail "--purge touched a custom meetings folder"

echo "install tests passed"
