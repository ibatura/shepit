#!/usr/bin/env bash
# Build whisper.cpp as a static xcframework (app/Vendor/whisper.xcframework) for Shepit
# to link in-process. Pinned to an exact commit (a tag name can be moved).
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="v1.9.4"
COMMIT="927cfce34f31707e17f2bff35c349632fb9e2c3a"
SRC="$HOME/.local/share/dictation/src/whisper.cpp-lib"
VENDOR="$REPO/app/Vendor"
OUT="$VENDOR/whisper.xcframework"
STAMP_FILE="$VENDOR/.whisper-stamp"

# The stamp changes whenever the commit or this script changes, forcing a rebuild.
STAMP="$VERSION $COMMIT $(shasum -a 256 "$0" | cut -d' ' -f1)"

if [[ -d "$OUT" && -f "$STAMP_FILE" && "$(cat "$STAMP_FILE")" == "$STAMP" ]]; then
  echo "whisper.xcframework $VERSION already built"
  exit 0
fi

command -v cmake >/dev/null || { echo "cmake is missing: brew install cmake" >&2; exit 1; }

rm -rf "$SRC"
mkdir -p "$(dirname "$SRC")" "$VENDOR"
git clone --depth 1 --branch "$VERSION" https://github.com/ggml-org/whisper.cpp "$SRC"

actual="$(git -C "$SRC" rev-parse HEAD)"
if [[ "$actual" != "$COMMIT" ]]; then
  echo "whisper.cpp $VERSION points to $actual, expected $COMMIT — refusing to build" >&2
  exit 1
fi

cmake -S "$SRC" -B "$SRC/build" \
  -DBUILD_SHARED_LIBS=OFF \
  -DGGML_METAL=ON \
  -DGGML_METAL_EMBED_LIBRARY=ON \
  -DGGML_NATIVE=OFF \
  -DWHISPER_BUILD_EXAMPLES=OFF \
  -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_SERVER=OFF \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=14.2 \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_BUILD_TYPE=Release
cmake --build "$SRC/build" --config Release -j

STAGE="$SRC/xcframework-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE/include"
find "$SRC/build" -name '*.a' -print0 | xargs -0 libtool -static -o "$STAGE/libwhisper-all.a"
cp "$SRC/include/whisper.h" "$SRC"/ggml/include/ggml*.h "$STAGE/include/"
cat > "$STAGE/include/module.modulemap" <<'EOF'
module whisper {
    header "whisper.h"
    link "c++"
    export *
}
EOF

rm -rf "$OUT"
xcodebuild -create-xcframework -library "$STAGE/libwhisper-all.a" -headers "$STAGE/include" -output "$OUT"
echo "$STAMP" > "$STAMP_FILE"
echo "built $OUT"
