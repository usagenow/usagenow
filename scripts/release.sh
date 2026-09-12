#!/bin/bash
# The whole release in one command: build, notarize the app, package the
# disk image, notarize and staple it, then print the checksum for the
# GitHub release and the Homebrew cask.
#
# Requires Config/Local.xcconfig and a notarytool keychain profile.
#
# Usage: scripts/release.sh [keychain-profile]
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE="${1:-${NOTARY_PROFILE:-UsageNow}}"
OUTPUT="build/release"
APP="$OUTPUT/export/UsageNow.app"

scripts/build-release.sh "$OUTPUT"

# The app is notarized before packaging so the copy inside the image is
# already trusted; the image is then notarized as its own artifact.
scripts/notarize.sh "$APP" "$PROFILE"
scripts/create-dmg.sh "$APP" "$OUTPUT"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="$OUTPUT/UsageNow-$VERSION.dmg"
scripts/notarize.sh "$DMG" "$PROFILE"

echo
echo "===================================================="
echo "UsageNow $VERSION"
echo "$DMG"
echo "SHA256: $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
echo "Size:   $(du -h "$DMG" | cut -f1)"
echo "===================================================="
echo "Next: attach the disk image to the v$VERSION GitHub release,"
echo "then fill the checksum into the Homebrew cask (docs/homebrew-cask.rb)."
