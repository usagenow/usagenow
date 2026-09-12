#!/bin/bash
# Submits an artifact to Apple's notary service, staples the ticket, and
# validates the result.
#
# Credentials come from a notarytool keychain profile, never from this
# repository. Create one once with:
#
#   xcrun notarytool store-credentials "UsageNow" \
#       --apple-id "you@example.com" --team-id "YOURTEAMID"
#
# Usage: scripts/notarize.sh <path-to-dmg-or-app> [keychain-profile]
set -euo pipefail

ARTIFACT="${1:?usage: notarize.sh <path-to-dmg-or-app> [keychain-profile]}"
PROFILE="${2:-${NOTARY_PROFILE:-UsageNow}}"

if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    cat >&2 <<MESSAGE
error: no notarytool keychain profile named "$PROFILE".
Create one (it asks for an app-specific password):

    xcrun notarytool store-credentials "$PROFILE" \\
        --apple-id "your-apple-id" --team-id "your-team-id"
MESSAGE
    exit 1
fi

# The notary service accepts only .zip, .pkg and .dmg, so an app bundle is
# submitted as a zip. The ticket is stapled to the bundle itself afterwards.
SUBMISSION="$ARTIFACT"
case "$ARTIFACT" in
*.app)
    STAGING=$(mktemp -d)
    trap 'rm -rf "$STAGING"' EXIT
    SUBMISSION="$STAGING/$(basename "$ARTIFACT").zip"
    /usr/bin/ditto -c -k --keepParent "$ARTIFACT" "$SUBMISSION"
    ;;
esac

echo "==> Submitting $(basename "$ARTIFACT") for notarization"
xcrun notarytool submit "$SUBMISSION" --keychain-profile "$PROFILE" --wait

echo "==> Stapling the ticket"
xcrun stapler staple "$ARTIFACT"
xcrun stapler validate "$ARTIFACT"

echo "==> Gatekeeper assessment"
case "$ARTIFACT" in
    *.dmg) spctl --assess --type open --context context:primary-signature -vv "$ARTIFACT" ;;
    *)     spctl --assess --type execute -vv "$ARTIFACT" ;;
esac

echo "==> Notarized $(basename "$ARTIFACT")"
