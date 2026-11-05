#!/bin/bash
# Package without automating Finder. Install scripts/requirements-dmg.txt first.
# Usage: scripts/create-dmg.sh <path-to-UsageNow.app> [output-directory]
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:?usage: create-dmg.sh <path-to-UsageNow.app> [output-directory]}"
OUTPUT="${2:-build/release}"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
DMG="$OUTPUT/UsageNow-$VERSION.dmg"
BUILDER="${DMGBUILD_BIN:-dmgbuild}"
if ! command -v "$BUILDER" >/dev/null 2>&1; then
    echo "error: install scripts/requirements-dmg.txt or set DMGBUILD_BIN" >&2
    exit 1
fi
mkdir -p "$OUTPUT"
rm -f "$DMG"
echo "==> Building compact disk image"
"$BUILDER" -s scripts/dmg-settings.py -D app="$APP" "UsageNow $VERSION" "$DMG"
echo "==> Signing the disk image"
IDENTITY=$(sed -nE 's/^CODE_SIGN_IDENTITY[[:space:]]*=[[:space:]]*(.*)/\1/p' Config/Local.xcconfig)
codesign --sign "$IDENTITY" --timestamp "$DMG"
codesign --verify --verbose=2 "$DMG"
echo "==> Created $DMG"
