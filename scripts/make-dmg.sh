#!/usr/bin/env bash
# Builds Quoth.app, notarizes and staples it, and packages it into a
# signed, notarized, stapled DMG with an Applications shortcut, plus the
# zipped app that Sparkle downloads as the in-app update.
#   scripts/make-dmg.sh <version>   → dist/Quoth-<version>.dmg and .dmg.sha256,
#                                     dist/Quoth-<version>.zip
#
# Signing the update archive and writing the appcast (Sparkle's
# sign_update and generate_appcast, with Quoth's EdDSA key) are separate
# steps; Quoth has no release workflow or update feed yet (ADR-005).
#
# Notary credentials, first match wins:
#
#   NOTARY_KEY=/path/to/key.p8     App Store Connect API key (CI)
#   NOTARY_KEY_ID=ABC123DEFG       its Key ID
#   NOTARY_ISSUER_ID=xxxxxxxx-...  the team's Issuer ID
#
# or a notarytool keychain profile, NOTARY_KEYCHAIN_PROFILE, default
# "quoth-notary" (local builds; created once with
# `xcrun notarytool store-credentials quoth-notary`).
#
# QUOTH_NOTARIZE=0 builds a signed but unnotarized DMG, for a quick look.
# Needs a Developer ID Application identity; see scripts/build-app.sh.

set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/make-dmg.sh <version>}"
VERSION="${VERSION#v}"
OUT="dist"
DMG="$OUT/Quoth-$VERSION.dmg"
BUILD="${QUOTH_BUILD_DIR:-build}"
APP="$BUILD/Quoth.app"
STAGE="$BUILD/dmg-stage"

IDENTITY="${QUOTH_SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
if [ -z "$IDENTITY" ]; then
    echo "no Developer ID Application identity in the keychain; a release DMG needs one" >&2
    exit 1
fi
export QUOTH_SIGN_IDENTITY="$IDENTITY"
unset QUOTH_TIMESTAMP

NOTARIZE="${QUOTH_NOTARIZE:-1}"

notarize() {
    # $1: the file to submit. Waits, and fails the build on rejection.
    if [ -n "${NOTARY_KEY:-}" ]; then
        xcrun notarytool submit "$1" --wait \
            --key "$NOTARY_KEY" --key-id "${NOTARY_KEY_ID:?}" --issuer "${NOTARY_ISSUER_ID:?}"
    else
        xcrun notarytool submit "$1" --wait \
            --keychain-profile "${NOTARY_KEYCHAIN_PROFILE:-quoth-notary}"
    fi
}

scripts/build-app.sh "$VERSION"

if [ "$NOTARIZE" = 1 ]; then
    echo "→ notarizing the app"
    ZIP="$BUILD/Quoth-$VERSION.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    notarize "$ZIP"
    rm -f "$ZIP"
    # The ticket goes on the app, so it opens offline once copied out of
    # the DMG.
    xcrun stapler staple "$APP"
    spctl -a -vv -t exec "$APP"
else
    echo "! QUOTH_NOTARIZE=0: signed but not notarized; Gatekeeper will block it on other Macs."
fi

# The update archive: the stapled app, zipped the way Sparkle recommends,
# so the ticket travels with it and the update opens offline.
UPDATE="$OUT/Quoth-$VERSION.zip"
echo "→ packaging the update archive $UPDATE"
mkdir -p "$OUT"
rm -f "$UPDATE"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$UPDATE"

echo "→ packaging $DMG"
rm -rf "$STAGE" && mkdir -p "$STAGE" "$OUT"
ditto "$APP" "$STAGE/Quoth.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Quoth" -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ -quiet "$DMG"
rm -rf "$STAGE"
codesign --sign "$IDENTITY" --timestamp "$DMG"

if [ "$NOTARIZE" = 1 ]; then
    echo "→ notarizing the DMG"
    notarize "$DMG"
    xcrun stapler staple "$DMG"
    spctl -a -vv -t open --context context:primary-signature "$DMG"
fi

(cd "$OUT" && shasum -a 256 "Quoth-$VERSION.dmg" > "Quoth-$VERSION.dmg.sha256")
cat "$OUT/Quoth-$VERSION.dmg.sha256"
echo "$DMG"
