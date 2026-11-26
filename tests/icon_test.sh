#!/usr/bin/env bash
# scripts/build-icon.sh (icon and name design §5), each branch, in a temporary folder.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
build="$REPO/scripts/build-icon.sh"
icon="$REPO/app/Resources/AppIcon.icon"
# The script's output goes to $T/out, which a failing case shows.
built() { "$build" "$@" >"$T/out" 2>&1; }
fail() { echo "FAIL: $*" >&2; [[ ! -f "$T/out" ]] || cat "$T/out" >&2; exit 1; }
# What an older build left in build/Shepit.app, which is never cleaned.
stale() { mkdir -p "$1"; touch "$1/AppIcon.icns" "$1/Assets.car"; }
no_icon() { [[ ! -e "$1/AppIcon.icns" && ! -e "$1/Assets.car" ]]; }

if xcrun --find actool >/dev/null 2>&1; then
    built "$icon" "$T/good" || fail "AppIcon.icon didn't compile"
    [[ -s "$T/good/AppIcon.icns" && -s "$T/good/Assets.car" ]] || fail "no AppIcon.icns or Assets.car"

    mkdir -p "$T/broken/AppIcon.icon"
    cp -R "$icon/Assets" "$T/broken/AppIcon.icon/"
    echo '{' > "$T/broken/AppIcon.icon/icon.json"
    stale "$T/res"
    built "$T/broken/AppIcon.icon" "$T/res" && fail "a broken icon.json passed"
    grep -q "correct format" "$T/out" || fail "a broken icon.json failed for another reason"
    no_icon "$T/res" || fail "a broken icon.json left an icon"

    cp -R "$icon" "$T/Other.icon"
    stale "$T/res"
    built "$T/Other.icon" "$T/res" && fail "Other.icon passed, though actool writes nothing for it"
    grep -q "wrote no AppIcon.icns" "$T/out" || fail "Other.icon failed for another reason"
    no_icon "$T/res" || fail "Other.icon left the old icon"
else
    echo "icon tests: no actool, skipped the three that compile"
fi

if [[ -d /Library/Developer/CommandLineTools ]]; then
    stale "$T/clt"
    DEVELOPER_DIR=/Library/Developer/CommandLineTools built "$icon" "$T/clt" || fail "without actool the build stopped"
    grep -q "No actool" "$T/out" || fail "without actool it didn't say so"
    no_icon "$T/clt" || fail "without actool the old icon stayed"
else
    echo "icon tests: no Command Line Tools folder, skipped the one without actool"
fi

echo "icon tests passed"
