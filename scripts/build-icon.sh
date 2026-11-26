#!/usr/bin/env bash
# Compile the app icon, an Icon Composer file, into a bundle's Contents/Resources as Assets.car and
# AppIcon.icns (icon and name design §5). It needs Xcode 26's actool: without it, or when it fails
# (an older Xcode doesn't know .icon files), Shepit is built without its icon. `make test` checks the icon compiles.
# Usage: build-icon.sh <the AppIcon.icon folder> <a Contents/Resources folder>
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
icon="$1" resources="$2"

mkdir -p "$resources"
# build/Shepit.app is never cleaned: an icon an older build left must not pass for this one.
rm -f "$resources/Assets.car" "$resources/AppIcon.icns"
without() {
    echo "$1: Shepit is built without its icon" >&2
    rm -f "$resources/Assets.car" "$resources/AppIcon.icns"
    exit 0
}
xcrun --find actool >/dev/null 2>&1 || without "No actool (it comes with Xcode)"
partial="$(mktemp -d)"
trap '/bin/rm -rf "$partial"' EXIT
minimum="$(plutil -extract LSMinimumSystemVersion raw "$REPO/app/Resources/Info.plist")"
# --app-icon must be the .icon folder's name, or actool writes nothing and still exits 0.
# The partial Info.plist isn't merged: app/Resources/Info.plist names the icon itself.
if ! out="$(xcrun actool "$icon" --compile "$resources" --platform macosx --app-icon AppIcon \
    --minimum-deployment-target "$minimum" --output-partial-info-plist "$partial/AppIcon.plist" 2>&1)"; then
    echo "$out" >&2
    without "actool failed (the icon needs Xcode 26)"
fi
[[ -f "$resources/AppIcon.icns" ]] || without "actool wrote no AppIcon.icns from $icon"
