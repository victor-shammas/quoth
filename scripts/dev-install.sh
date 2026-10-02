#!/usr/bin/env bash
# Build, sign, and install Quoth.app.
#   scripts/dev-install.sh
#
# macOS keys the Accessibility and Microphone grants to the app's code
# identity. An ad-hoc signature changes on every build, so each rebuild
# silently loses the grants. Signing with the Developer ID certificate and
# the fixed bundle ID local.quoth (packaging/Info.plist) keeps one
# identity across rebuilds and releases.
#
# Installs to /Applications, or ~/Applications when /Applications is not
# writable, and links /usr/local/bin/quoth to the app's executable. A plain
# binary already at that path (an old CLI install) is only replaced after you
# say yes. A running copy is quit and reopened.
#
#   QUOTH_SIGN_IDENTITY  signing identity (default: the keychain's Developer ID)
#   QUOTH_INSTALL_DIR    where Quoth.app goes
#   QUOTH_LINK_DIR       where the quoth link goes (default /usr/local/bin;
#                         set it empty to skip the link)
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
LINK_DIR="${QUOTH_LINK_DIR-/usr/local/bin}"
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

if [ -n "$LINK_DIR" ]; then
    LINK="$LINK_DIR/quoth"
    REPLACE=1
    if [ -e "$LINK" ] && [ ! -L "$LINK" ]; then
        REPLACE=0
        if [ -t 0 ]; then
            printf '%s is a separate quoth binary (an old CLI install). Replace it with a link to %s? [y/N] ' "$LINK" "$EXE"
            read -r answer
            case "$answer" in y|Y|yes) REPLACE=1 ;; esac
        fi
        [ "$REPLACE" = 1 ] || echo "  left $LINK as it was"
    fi
    if [ "$REPLACE" = 1 ]; then
        echo "→ linking $LINK"
        mkdir -p "$LINK_DIR" 2>/dev/null || sudo mkdir -p "$LINK_DIR"
        SUDO=""
        [ -w "$LINK_DIR" ] || SUDO="sudo"
        $SUDO ln -sfn "$EXE" "$LINK"
    fi
fi

if [ "$WAS_RUNNING" = 1 ]; then
    echo "→ reopening Quoth"
    open "$DEST"
fi

echo "✓ installed Quoth $("$EXE" --version 2>/dev/null || echo "$VERSION") at $DEST"
