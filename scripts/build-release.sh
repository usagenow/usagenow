#!/bin/bash
# Archives UsageNow in Release and exports a Developer ID signed app,
# then verifies the signature of the app and its widget extension.
#
# Signing comes from Config/Local.xcconfig (team, identity, App Group).
# Nothing here contains credentials.
#
# Usage: scripts/build-release.sh [output-directory]
set -euo pipefail
cd "$(dirname "$0")/.."

OUTPUT="${1:-build/release}"
ARCHIVE="$OUTPUT/UsageNow.xcarchive"
EXPORT="$OUTPUT/export"
APP="$EXPORT/UsageNow.app"

if [ ! -f Config/Local.xcconfig ]; then
    echo "error: Config/Local.xcconfig is missing — copy Local.xcconfig.example and set your team." >&2
    exit 1
fi

# Where opt-in telemetry goes, if anywhere. Not a secret, and not required:
# a build made without it sends nothing at all. It's passed as a build
# setting rather than put in an xcconfig, where the // in a URL would start
# a comment.
TELEMETRY_ENDPOINT="${USAGENOW_TELEMETRY_ENDPOINT:-}"
if [ -n "$TELEMETRY_ENDPOINT" ]; then
    echo "==> Telemetry endpoint: $TELEMETRY_ENDPOINT"
else
    echo "==> No telemetry endpoint: this build sends no analytics"
fi

echo "==> Archiving Release"
rm -rf "$ARCHIVE" "$EXPORT"
mkdir -p "$OUTPUT"
xcodebuild -project UsageNow.xcodeproj -scheme UsageNow -configuration Release \
    -archivePath "$ARCHIVE" archive -quiet \
    USAGENOW_TELEMETRY_ENDPOINT="$TELEMETRY_ENDPOINT"

echo "==> Exporting Developer ID application"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
    -exportOptionsPlist Config/ExportOptions.plist \
    -exportPath "$EXPORT" -quiet

echo "==> Verifying signatures"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign --verify --strict --verbose=2 "$APP/Contents/PlugIns/UsageNowWidget.appex"

for target in "$APP" "$APP/Contents/PlugIns/UsageNowWidget.appex"; do
    echo "--- $(basename "$target")"
    # Collect once: piping codesign into grep -q would kill it with SIGPIPE.
    signature=$(codesign -dvvv "$target" 2>&1 || true)
    entitlements=$(codesign -d --entitlements - --xml "$target" 2>/dev/null | plutil -p - 2>/dev/null || true)

    grep -E "^(Authority=Developer ID|TeamIdentifier|Identifier=)" <<<"$signature" || true
    grep -E "application-groups|app-sandbox|get-task-allow" <<<"$entitlements" || true

    case "$signature" in
        *"flags="*"runtime"*) ;;
        *) echo "error: $(basename "$target") is not signed with the hardened runtime" >&2; exit 1 ;;
    esac
    case "$signature" in
        *"Authority=Developer ID Application"*) ;;
        *) echo "error: $(basename "$target") is not signed with a Developer ID certificate" >&2; exit 1 ;;
    esac
    # Release builds must not carry the debugging entitlement; it blocks notarization.
    case "$entitlements" in
        *get-task-allow*) echo "error: $(basename "$target") carries get-task-allow" >&2; exit 1 ;;
    esac
done

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")
echo "==> Built UsageNow $VERSION ($BUILD) at $APP"
