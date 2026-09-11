#!/bin/sh
# Updates Shared/Resources/Localizable.xcstrings from the strings used in
# source. Xcode does this automatically when building in the IDE; run this
# after command-line builds (it builds first).
set -eu
cd "$(dirname "$0")/.."

DERIVED_DATA="build/DerivedData"
xcodebuild -project UsageNow.xcodeproj -scheme UsageNow -configuration Debug \
    -derivedDataPath "$DERIVED_DATA" build -quiet

set --
for file in $(find "$DERIVED_DATA/Build/Intermediates.noindex/UsageNow.build/Debug" -name '*.stringsdata'); do
    set -- "$@" --stringsdata "$file"
done
xcrun xcstringstool sync Shared/Resources/Localizable.xcstrings "$@"
echo "Localizable.xcstrings is up to date."
