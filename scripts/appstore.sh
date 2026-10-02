#!/usr/bin/env bash
# The Mac App Store edition (ADR-006), built from project.yml.
#
#   scripts/appstore.sh build     a local, ad-hoc signed build in build/appstore, to run and test
#   scripts/appstore.sh archive   a Release archive signed for the App Store
#   scripts/appstore.sh upload    export the archive and upload it to App Store Connect
#
# archive and upload sign through Xcode's automatic signing with an App Store
# Connect API key (Admin role, so cloud signing works), as Plainview does:
#
#   ASC_KEY_ID=ABC123DEFG          the key's ID
#   ASC_ISSUER_ID=xxxxxxxx-...     the team's issuer ID
#   ASC_KEY_PATH=...               default ~/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8
#
# The first archive registers the bundle ID com.victorshammas.quoth with the
# team. Bump CURRENT_PROJECT_VERSION in AppStore/Quoth.xcconfig before every
# upload. Keys never go in this repository.

set -euo pipefail
cd "$(dirname "$0")/.."

OUT=build/appstore
ARCHIVE="$OUT/Quoth.xcarchive"

xcodegen --quiet

auth() {
    : "${ASC_KEY_ID:?set ASC_KEY_ID}" "${ASC_ISSUER_ID:?set ASC_ISSUER_ID}"
    local key="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8}"
    [ -f "$key" ] || { echo "no API key at $key" >&2; exit 1; }
    echo -allowProvisioningUpdates -authenticationKeyPath "$key" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID"
}

case "${1:-}" in
build)
    xcodebuild -project Quoth.xcodeproj -scheme Quoth -configuration Release -derivedDataPath "$OUT" \
        CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build
    # Xcode registers what it builds with Launch Services; unregister it, so
    # `open -a Quoth` and Spotlight find the installed app, not this build.
    /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister \
        -u "$OUT/Build/Products/Release/Quoth.app" || true
    echo "$OUT/Build/Products/Release/Quoth.app"
    ;;
archive)
    # shellcheck disable=SC2046
    xcodebuild archive -project Quoth.xcodeproj -scheme Quoth -configuration Release \
        -archivePath "$ARCHIVE" $(auth)
    echo "$ARCHIVE"
    ;;
upload)
    [ -d "$ARCHIVE" ] || { echo "no archive; run scripts/appstore.sh archive first" >&2; exit 1; }
    # shellcheck disable=SC2046
    xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist AppStore/ExportOptions.plist \
        -exportPath "$OUT/export" $(auth)
    ;;
*)
    sed -n '2,8p' "$0"
    exit 64
    ;;
esac
