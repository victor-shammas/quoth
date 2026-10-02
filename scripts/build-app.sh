#!/usr/bin/env bash
# Builds the release binary and wraps it in a signed Quoth.app.
#   scripts/build-app.sh [version]        → build/Quoth.app
#
# The version (a tag such as v0.1.0 or 0.1.0) goes into
# CFBundleShortVersionString and CFBundleVersion. Without one it comes from
# the latest tag, or 0.0.0.
#
# Embeds Sparkle.framework (in-app updates, #50) in Contents/Frameworks and
# signs it inside-out before the app: its XPC services, Autoupdate, and
# Updater.app, then the framework, all with the same identity and the
# hardened runtime, as notarization requires.
#
# Signs with the first "Developer ID Application" identity in the keychain,
# with the hardened runtime and packaging/Quoth.entitlements. The
# designated requirement then names the bundle ID and the team, not a
# cdhash, so macOS keeps the Microphone and Accessibility grants across
# builds. Without an identity the app is ad-hoc signed and every build is a
# new identity; the script says so.
#
#   QUOTH_SIGN_IDENTITY   signing identity (default: the keychain's Developer ID)
#   QUOTH_TIMESTAMP=none  skip the secure timestamp (local builds, offline);
#                          notarization needs it, so releases leave this unset
#   QUOTH_BUILD_DIR       output directory (default: build)

set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-$(git describe --tags --abbrev=0 2>/dev/null || echo 0.0.0)}"
VERSION="${VERSION#v}"
OUT="${QUOTH_BUILD_DIR:-build}"
APP="$OUT/Quoth.app"

IDENTITY="${QUOTH_SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"

echo "→ building quoth $VERSION (release, arm64)"
swift build -c release --arch arm64 --product quoth
BIN="$(swift build -c release --arch arm64 --show-bin-path)/quoth"

echo "→ assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/quoth"
# SwiftPM links Sparkle through @rpath and puts the framework beside the
# binary; in the bundle it lives in Contents/Frameworks.
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/quoth"
strip -x "$APP/Contents/MacOS/quoth"
mkdir -p "$APP/Contents/Frameworks"
ditto "$(dirname "$BIN")/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
cp packaging/Info.plist "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$VERSION" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# SwiftPM's resource bundles (swift-transformers' fallback tokenizer
# configs, swift-crypto's privacy manifest) are left out, as they were from
# the bare binary: their accessors look beside the .app, where a signed
# bundle can't hold anything.

# packaging/AppIcon.icns is Quoth's quote on an espresso squircle, drawn
# at every size by scripts/make-quoth-icon.swift.
cp packaging/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

TIMESTAMP="--timestamp"
[ "${QUOTH_TIMESTAMP:-}" = "none" ] && TIMESTAMP="--timestamp=none"

if [ -n "$IDENTITY" ]; then
    echo "→ signing as $IDENTITY"
    SIGN_AS="$IDENTITY"
else
    echo "! no Developer ID Application identity; ad-hoc signing."
    echo "  Permissions will not survive the next build, and the app can't be notarized."
    SIGN_AS="-"
    TIMESTAMP="--timestamp=none"
fi

# Inside-out: each nested bundle before the one that contains it, as in
# Sparkle's documentation. Downloader.xpc keeps its entitlements.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for nested in \
    "$SPARKLE/XPCServices/Installer.xpc" \
    "$SPARKLE/XPCServices/Downloader.xpc" \
    "$SPARKLE/Autoupdate" \
    "$SPARKLE/Updater.app" \
    "$APP/Contents/Frameworks/Sparkle.framework"; do
    codesign --force --options runtime $TIMESTAMP --preserve-metadata=entitlements \
        --sign "$SIGN_AS" "$nested"
done
codesign --force --options runtime $TIMESTAMP \
    --entitlements packaging/Quoth.entitlements \
    --sign "$SIGN_AS" "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"
echo "  designated requirement: $(codesign -d -r- "$APP" 2>&1 | sed -n 's/^designated => //p')"
echo "$APP"
