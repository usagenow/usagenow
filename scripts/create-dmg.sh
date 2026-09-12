#!/bin/bash
# Builds the distributable disk image: UsageNow.app beside an Applications
# shortcut, on the UsageNow background.
#
# Usage: scripts/create-dmg.sh <path-to-UsageNow.app> [output-directory]
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:?usage: create-dmg.sh <path-to-UsageNow.app> [output-directory]}"
OUTPUT="${2:-build/release}"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="$OUTPUT/UsageNow-$VERSION.dmg"
STAGING="$OUTPUT/dmg-staging"
VOLUME="UsageNow $VERSION"

echo "==> Staging disk image contents"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING/.background"
cp -R "$APP" "$STAGING/UsageNow.app"
ln -s /Applications "$STAGING/Applications"
cp docs/dmg-background.png "$STAGING/.background/background.png"

echo "==> Creating read-write image"
TEMP_DMG="$OUTPUT/UsageNow-rw.dmg"
rm -f "$TEMP_DMG"
hdiutil create -srcfolder "$STAGING" -volname "$VOLUME" -fs HFS+ \
    -format UDRW -ov "$TEMP_DMG" -quiet

echo "==> Arranging the Finder window"
# Finder ignores volumes mounted with -nobrowse, so mount it normally. macOS
# renames a volume whose name is already taken ("UsageNow 0.2.0 1"), so read
# the mount point back instead of assuming it.
ATTACH_PLIST=$(mktemp)
trap 'rm -f "$ATTACH_PLIST"' EXIT
hdiutil attach "$TEMP_DMG" -plist > "$ATTACH_PLIST"
MOUNT_DIR=$(/usr/libexec/PlistBuddy -c "Print :system-entities" "$ATTACH_PLIST" |
    sed -n 's/^ *mount-point = //p' | head -1)
[ -d "$MOUNT_DIR" ] || { echo "error: the image didn't mount" >&2; exit 1; }
MOUNTED_VOLUME=$(basename "$MOUNT_DIR")
osascript <<APPLESCRIPT || echo "warning: couldn't style the window (needs permission to control Finder); the image is still valid" >&2
tell application "Finder"
    tell disk "$MOUNTED_VOLUME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 150, 720, 510}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 112
        set background picture of viewOptions to file ".background:background.png"
        set position of item "UsageNow.app" of container window to {135, 170}
        set position of item "Applications" of container window to {385, 170}
        close
        open
        update without registering applications
        delay 1
    end tell
end tell
APPLESCRIPT
# Hide the helpers so the window shows only the app and the shortcut.
chflags hidden "$MOUNT_DIR/.background" 2>/dev/null || true
sync
# Finder can still hold the volume for a moment after closing the window.
for attempt in 1 2 3 4 5; do
    hdiutil detach "$MOUNT_DIR" -quiet && break
    [ "$attempt" = 5 ] && { echo "error: couldn't unmount $MOUNT_DIR" >&2; exit 1; }
    sleep 2
done

echo "==> Compressing"
hdiutil convert "$TEMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG" -quiet
rm -f "$TEMP_DMG"
rm -rf "$STAGING"

echo "==> Signing the disk image"
IDENTITY=$(grep -E "^CODE_SIGN_IDENTITY" Config/Local.xcconfig | sed -E 's/.*= *//')
codesign --sign "$IDENTITY" --timestamp "$DMG"
codesign --verify --verbose=2 "$DMG"

echo "==> Created $DMG"
