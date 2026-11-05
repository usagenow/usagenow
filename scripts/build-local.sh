#!/bin/bash
# Developer ID signed, universal app for local acceptance. Nothing is uploaded,
# notarized or installed. Uses the production identity for widget upgrade tests.
set -euo pipefail
cd "$(dirname "$0")/.."
local_version=$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);/\1/p' UsageNow.xcodeproj/project.pbxproj | head -n 1)
local_output="${1:-build/Local-$local_version}"
USAGENOW_LOCAL_BUILD=1 ./scripts/build-release.sh "$local_output"
local_app="$local_output/export/UsageNow.app"
test -z "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$local_app/Contents/Info.plist")"
test -z "$(/usr/libexec/PlistBuddy -c 'Print :UsageNowTelemetryEndpoint' "$local_app/Contents/Info.plist")"
local_zip="$local_output/UsageNow-$local_version-local.zip"
ditto -c -k --keepParent "$local_app" "$local_zip"
shasum -a 256 "$local_zip"
echo "==> Local candidate: $local_zip"
