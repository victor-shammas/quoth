# Releasing Quoth

Quoth ships through two channels from this repo, plus the website:

- **Direct edition — GitHub release** on `victor-shammas/quoth`: a notarized
  DMG for new installs, and a signed Sparkle appcast and zip that installed
  copies update from. Made by `scripts/release.sh`.
- **App Store edition — Mac App Store** ($1.99, sandboxed), uploaded with
  `scripts/appstore.sh`, submitted in App Store Connect.
- **Website** in `docs/` (GitHub Pages, https://victorshammas.com/quoth/).

The two editions are versioned separately today: direct releases are git
tags (`v1.0.0`, `v1.0.1`, `v1.0.2`), the App Store build is version `1.0` in
`AppStore/Quoth.xcconfig`.

TODO (author): should the App Store `MARKETING_VERSION` follow the direct
release numbers (e.g. 1.0.2), or stay on its own track?

## Where the version lives

- **Direct edition:** nowhere in a file. The version is the argument to
  `scripts/release.sh X.Y.Z`, which becomes the tag `vX.Y.Z`;
  `scripts/build-app.sh` writes it into `CFBundleShortVersionString` and
  `CFBundleVersion` of the built app. The `0.0.0` in `packaging/Info.plist`
  is a placeholder; leave it. Sparkle compares versions, so use numbers and
  dots only, each release higher than the last.
- **App Store edition:** `AppStore/Quoth.xcconfig` —
  `MARKETING_VERSION` (the version users see) and `CURRENT_PROJECT_VERSION`
  (the build number, which must increase with every App Store Connect
  upload). The file holds the next unused build number: build 2 was
  uploaded and it now says 3.

## One-time setup on the Mac that releases

- Direct: a Developer ID Application certificate in the keychain; the
  notarytool profile (`xcrun notarytool store-credentials quoth-notary`);
  Quoth's Sparkle private key in the keychain (run Sparkle's
  `generate_appcast` once by hand and choose Always Allow); `gh` logged in.
- App Store: `brew install xcodegen`; an App Store Connect API key with the
  Admin role at `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8`, and
  its key ID and issuer ID.

TODO (author): which of the three Macs holds the Developer ID certificate,
the Sparkle private key and the API key? If only one, releases must be cut
there.

## Checklist

1. **Changelog.** Add an entry at the top of `CHANGELOG.md` (move items out
   of "Unreleased"). Write the release notes for GitHub in a file outside
   the tracked tree, e.g. `release/notes-X.Y.Z.md` (`release/` is
   gitignored); `scripts/release.sh` refuses a dirty working tree.
2. **App Store version.** If this release goes to the App Store, set
   `MARKETING_VERSION` in `AppStore/Quoth.xcconfig` (when the visible
   version changes) and check that `CURRENT_PROJECT_VERSION` is higher than
   the last uploaded build.
3. **Commit and push** to `main`. CI (`.github/workflows/ci.yml`) runs
   `swift test` and `scripts/appstore.sh build`; wait for it to pass
   (`gh run list -R victor-shammas/quoth`). This push also publishes
   anything changed in `docs/`.
4. **Test the direct edition.**

       swift test
       scripts/dev-install.sh

   Hold-to-talk into a text field, a double-tap lock with live text, a
   voice command, and the Quote Card. Optionally check a signed but
   unnotarized DMG with `QUOTH_NOTARIZE=0 scripts/make-dmg.sh X.Y.Z`.
5. **Test the App Store edition.**

       scripts/appstore.sh build

   Open `build/appstore/Build/Products/Release/Quoth.app` and check
   onboarding (Microphone, Input Monitoring, Paste at cursor), dictation
   with and without the paste grant (copy for ⌘V), and the Quote Card.
6. **Dependencies changed?** Regenerate the acknowledgements and commit:

       swift package resolve && python3 scripts/make-acknowledgements.py

   Keep `project.yml`'s `exactVersion` pins equal to `Package.resolved`.
7. **GitHub release (direct edition).**

       scripts/release.sh X.Y.Z release/notes-X.Y.Z.md

   It builds, notarizes and staples the app and DMG, writes and signs
   `appcast.xml`, tags `vX.Y.Z` and pushes the tag, and creates the release
   "Quoth X.Y.Z" with `Quoth-X.Y.Z.dmg`, `Quoth.dmg`,
   `Quoth-X.Y.Z.dmg.sha256`, `Quoth-X.Y.Z.zip` and `appcast.xml`. Without a
   notes file it uses GitHub's generated notes (as 1.0.2 did). Do not tag
   by hand.
8. **Check the release.** https://github.com/victor-shammas/quoth/releases/latest/download/Quoth.dmg
   downloads the new DMG; an installed older copy finds the update with
   Check for Updates in the menu.
9. **App Store screenshots**, only if the UI in them changed:

       QUOTH_RENDER_DIR=/tmp/quoth-shots swift test -Xswiftc -DAPPSTORE --filter ScreenshotRenderTests
       swift AppStore/screenshots/compose.swift /tmp/quoth-shots AppStore/screenshots

   Commit the new PNGs.
10. **Archive and upload to App Store Connect.**

        ASC_KEY_ID=… ASC_ISSUER_ID=… scripts/appstore.sh archive
        ASC_KEY_ID=… ASC_ISSUER_ID=… scripts/appstore.sh upload

    `archive` writes `build/appstore/Quoth.xcarchive` and fails if any
    Accessibility function is linked; `upload` exports with
    `AppStore/ExportOptions.plist` and uploads it. Opening
    `Quoth.xcodeproj` (after `xcodegen`) and using Product › Archive and the
    Organizer works too.
11. **Bump the build number** after the upload: `CURRENT_PROJECT_VERSION`
    in `AppStore/Quoth.xcconfig` to N+1, committed as "App Store: build N+1
    is next (build N uploaded)", as in `f7481ca`.
12. **Submit in App Store Connect.** On the app version, select the new
    build, fill in What's New, update the listing and review notes if they
    changed (text kept locally in `AppStore/metadata.md` and
    `AppStore/review-notes.md`, gitignored), and confirm App Privacy still
    says Data Not Collected. Submit for review.

    TODO (author): `AppStore/metadata.md` and `AppStore/review-notes.md` are
    not in git. Where is the master copy, so the other Macs can reach it?
13. **Website** (`docs/`), then commit and push to `main` (that publishes it):
    - First App Store approval only: in `docs/index.html`, replace the
      "Coming soon to the Mac App Store" span with the link in the HTML
      comment above it (fill in the app ID), and replace "Coming soon" in
      the Mac App Store card of "Two ways to get Quoth".
    - Update `support.html` answers if behaviour changed.
    - If data handling changed, update `privacy.html` and its effective
      date, `AppStore/PrivacyInfo.xcprivacy`, and the App Privacy answers,
      together.
    - The direct download link uses `releases/latest`, so it needs no edit.
14. **Changelog status.** Note in `CHANGELOG.md` when the App Store build
    was submitted and when it went live.

TODO (author): no step here covers App Store Connect pricing,
availability or TestFlight; add them if you use them.

## If App Review rejects it

ADR-006 has the planned fallback for automatic pasting (guideline 2.4.5):
set `Edition.allowsAutoPaste = false` in
`Sources/QuothPlatform/Support/Edition.swift`, which makes the App Store
build copy-only, and say so in the listing. For anything else, fix it,
bump `CURRENT_PROJECT_VERSION`, archive, upload and resubmit.

TODO (author): record past review outcomes here once there are any.
