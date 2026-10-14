#!/usr/bin/env bash
# Generates Resources/AppIcon.icns from scripts/make-icon.swift (macOS only, needs iconutil).
set -euo pipefail
cd "$(dirname "$0")/.."
ICONSET="Resources/AppIcon.iconset"
rm -rf "$ICONSET"
swift scripts/make-icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
rm -rf "$ICONSET"
echo "Created Resources/AppIcon.icns"
