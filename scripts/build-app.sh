#!/usr/bin/env bash
# Builds dist/pano-squeezer.app: release build, universal binary (arm64 + x86_64), ad-hoc signed.
#
# usage: scripts/build-app.sh [version]      (default version: from the latest git tag, else 0.0.0)
set -euo pipefail
cd "$(dirname "$0")/.."

[[ "$(uname)" == "Darwin" ]] || { echo "build-app.sh needs macOS"; exit 1; }

VERSION="${1:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.0.0}"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
APP="dist/pano-squeezer.app"

echo "== Building pano-squeezer $VERSION ($BUILD), universal"
swift build -c release --arch arm64 --arch x86_64 --product PanoSqueezer
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/PanoSqueezer"

[[ -f Resources/AppIcon.icns ]] || scripts/make-icon.sh

echo "== Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PanoSqueezer"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist.template > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

echo "== Signing"
if [[ -n "${DEVELOPER_ID:-}" ]]; then
    # Prepared for later (Apple Developer account): Developer ID + hardened runtime.
    codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP"
else
    codesign --force --sign - "$APP"   # ad-hoc
fi
codesign --verify --verbose "$APP"
lipo -info "$APP/Contents/MacOS/PanoSqueezer"
echo "== Done: $APP"
