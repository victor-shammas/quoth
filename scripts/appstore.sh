#!/usr/bin/env bash
# The Mac App Store edition (ADR-006), built from project.yml.
#
#   scripts/appstore.sh build     a local build in build/appstore, to run and test
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

# The App Store build reads no other app's fields (ADR-006): no Accessibility
# function may be linked in. FocusedElement is internal to QuothPlatform so
# the optimizer can drop it; making it public brings five of them back.
no_accessibility() {
    local found
    found="$(nm -u "$1" | grep -E '^ *_AX[A-Z]' || true)"
    if [ -n "$found" ]; then
        echo "error: the App Store build links Accessibility functions:" >&2
        echo "$found" >&2
        exit 1
    fi
}

case "${1:-}" in
build)
    APP="$OUT/Build/Products/Release/Quoth.app"
    xcodebuild -project Quoth.xcodeproj -scheme Quoth -configuration Release -derivedDataPath "$OUT" \
        CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build
    # Re-signed as Apple Development when that certificate is here. macOS
    # keys Input Monitoring and Paste at cursor to the signature, and an
    # ad-hoc one changes with every build: a grant made for the last build
    # shows as on in System Settings but no longer applies.
    if security find-identity -v -p codesigning | grep -q '"Apple Development:'; then
        codesign --force --sign "Apple Development" --entitlements AppStore/Quoth.entitlements "$APP"
    fi
    # Xcode registers what it builds with Launch Services; unregister it, so
    # `open -a Quoth` and Spotlight find the installed app, not this build.
    /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister \
        -u "$APP" || true
    no_accessibility "$APP/Contents/MacOS/Quoth"
    echo "$APP"
    ;;
archive)
    # shellcheck disable=SC2046
    xcodebuild archive -project Quoth.xcodeproj -scheme Quoth -configuration Release \
        -archivePath "$ARCHIVE" $(auth)
    no_accessibility "$ARCHIVE/Products/Applications/Quoth.app/Contents/MacOS/Quoth"
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
