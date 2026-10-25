#!/bin/bash
# Bundle a Foundation-only CLI; no provider or credential implementation is linked.
set -euo pipefail
cli_work="$TEMP_DIR/UsageNowCLI"
mkdir -p "$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers" "$cli_work"
cli_parts=()
for cli_arch in $ARCHS; do
    cli_part="$cli_work/usagenow-$cli_arch"
    xcrun swiftc -O -swift-version 6 -sdk "$SDKROOT" -target "$cli_arch-apple-macosx15.0" \
        -module-cache-path "$cli_work/modules" \
        "$SRCROOT/Shared/CLI/StatusCommand.swift" "$SRCROOT/CLI/main.swift" -o "$cli_part"
    cli_parts+=("$cli_part")
done
cli_output="$cli_work/usagenow"
xcrun lipo -create "${cli_parts[@]}" -output "$cli_output"
if [ "${CODE_SIGNING_ALLOWED:-YES}" != NO ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
    cli_entitlements="$cli_work/entitlements.plist"
    /usr/libexec/PlistBuddy -c Clear "$cli_entitlements" >/dev/null 2>&1 || true
    /usr/libexec/PlistBuddy -c 'Add :com.apple.security.application-groups array' "$cli_entitlements"
    /usr/libexec/PlistBuddy -c "Add :com.apple.security.application-groups:0 string $USAGENOW_APP_GROUP" "$cli_entitlements"
    /usr/bin/codesign --force --timestamp --options runtime --identifier "$PRODUCT_BUNDLE_IDENTIFIER.cli" \
        --entitlements "$cli_entitlements" --sign "$EXPANDED_CODE_SIGN_IDENTITY" "$cli_output"
fi
# codesign creates temporary siblings. Sign inside the build phase's work
# directory, then copy only the declared final output into the app bundle.
cp "$cli_output" "$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers/usagenow"
