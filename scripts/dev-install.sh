#!/usr/bin/env bash
# Build, sign, and install Quoth.app.
#   scripts/dev-install.sh
#
# macOS keys the Accessibility and Microphone grants to the app's code
# identity. An ad-hoc signature changes on every build, so each rebuild
# silently loses the grants. Signing with the Developer ID certificate and
# the fixed bundle ID com.victorshammas.quoth.direct (packaging/Info.plist) keeps one
# identity across rebuilds and releases.
#
# Installs to /Applications, or ~/Applications when /Applications is not
# writable. A running copy is quit and reopened.
#
#   QUOTH_SIGN_IDENTITY  signing identity (default: the keychain's Developer ID)
#   QUOTH_INSTALL_DIR    where Quoth.app goes
#   QUOTH_NO_RESTART=1   don't quit and reopen a running copy

set -euo pipefail
cd "$(dirname "$0")/.."

if [ -z "${QUOTH_INSTALL_DIR:-}" ]; then
    if [ -w /Applications ]; then
        QUOTH_INSTALL_DIR=/Applications
    else
        QUOTH_INSTALL_DIR="$HOME/Applications"
    fi
fi
BUILD="${QUOTH_BUILD_DIR:-build}"
DEST="$QUOTH_INSTALL_DIR/Quoth.app"
EXE="$DEST/Contents/MacOS/quoth"

VERSION="$(git describe --tags --always --dirty 2>/dev/null || echo 0.0.0)"
QUOTH_TIMESTAMP=none QUOTH_BUILD_DIR="$BUILD" scripts/build-app.sh "${VERSION#v}"

WAS_RUNNING=0
if [ -z "${QUOTH_NO_RESTART:-}" ] && pgrep -f "^$EXE" >/dev/null 2>&1; then
    WAS_RUNNING=1
    echo "→ quitting the running Quoth"
    pkill -TERM -f "^$EXE" || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -f "^$EXE" >/dev/null 2>&1 || break
        sleep 0.5
    done
fi

echo "→ installing to $DEST"
mkdir -p "$QUOTH_INSTALL_DIR"
rm -rf "$DEST"
ditto "$BUILD/Quoth.app" "$DEST"

# Quoth has no command line any more (ADR-007). A link left by an older
# install would start the app from a terminal; say so rather than delete it.
OLD_LINK=/usr/local/bin/quoth
if [ -L "$OLD_LINK" ] && [[ "$(readlink "$OLD_LINK")" == *Quoth.app* ]]; then
    echo "! $OLD_LINK is left from the quoth command; remove it with: sudo rm $OLD_LINK"
fi

if [ "$WAS_RUNNING" = 1 ]; then
    echo "→ reopening Quoth"
    open "$DEST"
fi

echo "✓ installed Quoth $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DEST/Contents/Info.plist" 2>/dev/null || echo "$VERSION") at $DEST"
