#!/bin/bash
# Signs a release for in-app updates and writes the appcast feed.
#
# Sparkle installs an update only when it carries a signature made with the
# private EdDSA key. That key lives in the maintainer's login keychain, put
# there once by Sparkle's generate_keys, and it never appears in this
# repository or in any build output.
#
# Usage: scripts/appcast.sh [disk-image-directory] [appcast-output-path]
#
# The directory holds every published disk image, because the feed lists the
# releases people may be coming from, not just the newest one.
set -euo pipefail
cd "$(dirname "$0")/.."

IMAGES="${1:-build/release/published}"
APPCAST="${2:-build/release/appcast.xml}"
DOWNLOAD_PREFIX="https://usagenow.com/download/"

# Sparkle ships its tools inside the resolved Swift package.
find_tool() {
    if [ -n "${SPARKLE_BIN:-}" ] && [ -x "$SPARKLE_BIN/$1" ]; then
        echo "$SPARKLE_BIN/$1"
        return
    fi
    find "$HOME/Library/Developer/Xcode/DerivedData" \
        -path "*artifacts/sparkle/Sparkle/bin/$1" -type f -print -quit 2>/dev/null
}

GENERATE=$(find_tool generate_appcast)
if [ -z "$GENERATE" ]; then
    echo "error: generate_appcast not found. Build the app once so Xcode resolves Sparkle," >&2
    echo "       or set SPARKLE_BIN to Sparkle's bin directory." >&2
    exit 1
fi

if [ ! -d "$IMAGES" ]; then
    echo "error: $IMAGES doesn't exist. Put every published UsageNow-<version>.dmg there." >&2
    exit 1
fi

count=$(find "$IMAGES" -name "UsageNow-*.dmg" | wc -l | tr -d ' ')
if [ "$count" -eq 0 ]; then
    echo "error: no UsageNow-<version>.dmg in $IMAGES" >&2
    exit 1
fi

echo "==> Signing $count disk image(s) from $IMAGES"
# generate_appcast reads the private key from the login keychain itself; it
# is never passed on the command line, where it would reach the shell history.
"$GENERATE" \
    --download-url-prefix "$DOWNLOAD_PREFIX" \
    --link "https://usagenow.com" \
    --full-release-notes-url "https://github.com/usagenow/usagenow/blob/main/CHANGELOG.md" \
    -o "$APPCAST" \
    "$IMAGES"

# Sparkle decides what is newer by CFBundleVersion, so two releases sharing
# one build number are indistinguishable to it and the update never offers.
duplicates=$(grep -o '<sparkle:version>[^<]*</sparkle:version>' "$APPCAST" | sort | uniq -d)
if [ -n "$duplicates" ]; then
    echo "error: two releases share a build number, so Sparkle can't tell them apart:" >&2
    echo "$duplicates" | sed 's/^/       /' >&2
    echo "       Raise CURRENT_PROJECT_VERSION for every release." >&2
    exit 1
fi

echo
echo "==> Wrote $APPCAST"
grep -o '<sparkle:shortVersionString>[^<]*' "$APPCAST" | sed 's/<sparkle:shortVersionString>/    /'
echo
echo "Next: copy it to the site repository and deploy, so the feed is live at"
echo "      https://usagenow.com/appcast.xml"
echo
echo "      cp \"$APPCAST\" ../UsageNow/public/appcast.xml"
