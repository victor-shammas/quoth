#!/usr/bin/env bash
# Publishes a direct-edition release on GitHub: the notarized DMG people
# download, and the zip and signed appcast that installed copies update
# from (ADR-005).
#   scripts/release.sh <version> [notes.md]
#
# Needs, once:
#   - a Developer ID Application certificate in the keychain;
#   - the notary profile `quoth-notary` (xcrun notarytool store-credentials);
#   - Quoth's Sparkle private key in the keychain (generate_keys), whose
#     public half is SUPublicEDKey in packaging/Info.plist;
#   - gh, logged in to GitHub.
#
# Installed copies read releases/latest/download/appcast.xml, which always
# points at the newest release, so each release carries its own appcast.

set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/release.sh <version> [notes.md]}"
VERSION="${VERSION#v}"
NOTES="${2:-}"
TAG="v$VERSION"
REPO="victor-shammas/quoth"
SPARKLE=".build/artifacts/sparkle/Sparkle/bin"

# Sparkle compares versions; a release is dot-separated numbers only.
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]] || { echo "version must be numbers and dots, like 1.0.1" >&2; exit 64; }
[ -z "$(git status --porcelain)" ] || { echo "commit or stash your changes first: a release is built from a commit" >&2; exit 1; }
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then echo "$TAG already exists" >&2; exit 1; fi
[ -x "$SPARKLE/generate_appcast" ] || swift package resolve

# 1. Build, sign, notarize and staple: the DMG and the update zip.
scripts/make-dmg.sh "$VERSION"

# 2. The appcast, from the update zip alone, signed with the Sparkle key in
#    the keychain (the feed itself is signed too: SURequireSignedFeed).
FEED="dist/feed-$VERSION"
rm -rf "$FEED" && mkdir -p "$FEED"
cp "dist/Quoth-$VERSION.zip" "$FEED/"
"$SPARKLE/generate_appcast" "$FEED" --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/"
grep -q 'sparkle:edSignature' "$FEED/appcast.xml" || { echo "the appcast isn't signed: is the Sparkle key in this keychain?" >&2; exit 1; }

# 3. Tag the commit and publish.
git tag "$TAG"
git push origin "$TAG"
if [ -n "$NOTES" ]; then NOTE_ARGS=(--notes-file "$NOTES"); else NOTE_ARGS=(--generate-notes); fi
gh release create "$TAG" -R "$REPO" --title "Quoth $VERSION" "${NOTE_ARGS[@]}" \
    "dist/Quoth-$VERSION.dmg" "dist/Quoth-$VERSION.dmg.sha256" "dist/Quoth-$VERSION.zip" "$FEED/appcast.xml"
echo "✓ https://github.com/$REPO/releases/tag/$TAG"
