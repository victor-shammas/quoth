# ADR-005 :: Signed app identity

Last updated: `2026.10.02`

> Each edition has one bundle ID and one signing identity, for good: macOS keys the Microphone, Accessibility and Input Monitoring grants to the code identity, so a stable one is what makes grants survive updates.

## 1. Decision

- **App Store edition: `com.victorshammas.quoth`,** team `JPP8RN6BJB`, signed by Xcode's automatic signing and distributed through the Mac App Store (ADR-006).
- **Direct edition: its own bundle ID,** so its grants, login item and Sparkle defaults never collide with the App Store app on the same Mac. Local builds use `local.quoth` until the first public release, which chooses the permanent one (for example `com.victorshammas.quoth.direct`).
- **Developer ID signing and notarization for direct releases,** with the team's Developer ID Application certificate and a Quoth-only notarization key. Until that certificate exists, local builds are signed with the Apple Development certificate through `QUOTH_SIGN_IDENTITY`, which keeps grants across rebuilds; an ad-hoc signature would not.
- **`SMAppService` for launch at login** in both editions.
- **One binary, two roles** in the direct edition: the executable inside the bundle runs the dictation loop when launched with no subcommand, and serves the CLI through a symlink.

## 2. Rationale

An ad-hoc signature changes with every build, so each build is a new identity to macOS, and a grant made to the last one silently stops applying: dictation would type nothing after an update. Changing a bundle ID after users have granted permissions forces every user to grant them again, which is why the direct edition's permanent ID is chosen before its first public release, not after.

Separate IDs for the two editions were chosen over a shared one: a sandboxed and an unsandboxed app with one ID would share grants and preferences in confusing ways, and a user may well have both.

## 3. Design implications

- Changing a bundle ID or signing team resets every user's grants; treat it as a breaking change.
- Direct-edition updates are Sparkle archives signed with Quoth's EdDSA key, and Sparkle also requires the update's code signature to match the installed app. Rotating either breaks auto-update for existing installs.
- The running app asks for its grants on first start and waits for them; it never exits over a missing grant.

## 4. When to revisit

- A change of developer team.
