#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Shepit"
BUNDLE_ID="dev.shepit.Shepit"
BUILD_DIR="$REPO/build"
APP_BUNDLE="$BUILD_DIR/Shepit.app"
INSTALL_DIR="$HOME/Applications"
INSTALL_APP="$INSTALL_DIR/Shepit.app"

source "$REPO/scripts/signing.sh"

"$REPO/scripts/build-whisper-lib.sh"
swift build -c release --package-path "$REPO/app"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
cp "$REPO/app/.build/release/Shepit" "$APP_BUNDLE/Contents/MacOS/Shepit"
cp "$REPO/app/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
# Pinned model manifests, so Settings can download and verify models like download-models.sh does.
mkdir -p "$APP_BUNDLE/Contents/Resources/models"
cp "$REPO"/scripts/models/*.sha256 "$APP_BUNDLE/Contents/Resources/models/"

if ! identity="$(choose_identity)"; then
    ensure_self_signed
    identity="$(choose_identity)"
fi

codesign --force --sign "$identity" --identifier "$BUNDLE_ID" "$APP_BUNDLE"
codesign --verify --strict "$APP_BUNDLE"
printf 'Signed Shepit with identity: %s\n' "$identity"

mkdir -p "$INSTALL_DIR"
if [[ -d "$INSTALL_APP" ]]; then
    osascript -e 'quit app id "dev.shepit.Shepit"' >/dev/null 2>&1 || true
fi

install_stage="$(/usr/bin/mktemp -d "$INSTALL_DIR/.Shepit.app.new.XXXXXX")"
trap '/bin/rm -rf "$install_stage"' EXIT
cp -R "$APP_BUNDLE" "$install_stage/Shepit.app"
if [[ -e "$INSTALL_APP" ]]; then
    # mktemp keeps two installs in the same second from moving the old app into an existing backup.
    backup="$(/usr/bin/mktemp -u "$INSTALL_DIR/Shepit.app.previous.$(/bin/date +%Y%m%d%H%M%S).XXXXXX")"
    mv "$INSTALL_APP" "$backup"
    if ! mv "$install_stage/Shepit.app" "$INSTALL_APP"; then
        mv "$backup" "$INSTALL_APP"
        echo "Could not install Shepit; restored previous app from $backup" >&2
        exit 1
    fi
else
    mv "$install_stage/Shepit.app" "$INSTALL_APP"
fi
# Keep only the newest backup.
ls -dt "$INSTALL_DIR"/Shepit.app.previous.* 2>/dev/null | tail -n +2 | while IFS= read -r old; do /bin/rm -rf "$old"; done
printf 'Installed %s\n' "$INSTALL_APP"
