# Changelog

Entries up to and including 1.0.2 were reconstructed on 2026-10-09 from
`git log`, the tags `v1.0.0`–`v1.0.2` and the GitHub releases. Versions are
the direct edition's (GitHub releases); the App Store edition's status is
noted where the history records it.

## Unreleased

- Website: Staple added to the app bar on every page, with its tagline
  (2026-10-09).
- Docs: `CLAUDE.md`, `RELEASING.md` and this changelog.

## 1.0.2 — 2026-10-07

GitHub release (generated notes only).

- A paste that nothing receives (for example Messages or WhatsApp with the
  message box unfocused) no longer vanishes: the text stays on the
  clipboard, the pill says so, and "scratch that" doesn't count it. A
  locked recording keeps the rest of its segments for the clipboard.

## 1.0.1 — 2026-10-04

GitHub release; the tagged commit is from 2026-10-03.

- The welcome window comes back after each permission prompt or a visit to
  System Settings, instead of seeming to quit.
- Reopen Quoth, for grants macOS applies only to a new launch (also in
  Settings after allowing Paste at cursor); it reopens on the welcome
  window.
- `scripts/appstore.sh build` signs as Apple Development, so grants survive
  a rebuild.
- Website and README: the App Store edition up front, the free download
  under the editions, with a link to the latest release.
- App Store edition: version 1.0, build 2 uploaded to App Store Connect on
  2026-10-03; the build number now reads 3.

## 1.0.0 — 2026-10-03

First release of Quoth, as a notarized DMG on GitHub. Built on 2026-10-02 and
2026-10-03 on top of Parrot v0.2.3.

- Renamed from Parrot to Quoth, with a new icon (an amber quote on an
  espresso squircle) and a quote glyph in the menu bar. Parrot's legacy
  migrations, website and release CI removed.
- Hands-free: double-tap the hotkey to lock recording on; text appears at
  each pause; a lock never throws words away.
- Voice commands (English): spoken punctuation, "new paragraph", "new line",
  "bullet point", "quote … unquote", and "scratch that".
- The Quote Card: dictate into a floating card, edit, then ⌘↩ to insert.
- Dictionary: an editor in Settings, Fix Last Dictation, Copy Last
  Dictation; matching through apostrophes, hyphens and missing spaces; a
  hand edit is never overwritten.
- Models: Whisper Large v3 Turbo (compressed, 646 MB) added; downloaded
  models can be deleted in Settings.
- Mixed-language dictation: each part transcribed in its own language,
  never translated.
- Settings with toolbar tabs, a Help tab and a voice-command list; Settings,
  the welcome window and the Quote Card in Quoth's latte look.
- A warning when macOS Dictation's shortcut shares the hotkey.
- Acknowledgements window, and a copyright line for the fork.
- Two editions from one codebase (ADR-006): the direct Swift package and a
  sandboxed App Store edition generated from `project.yml`, with
  Input Monitoring for the hotkey and an optional paste grant.
- Restructured into QuothDomain, QuothPlatform, QuothSpeech and QuothCore,
  with a tested dictation state machine and one app model (ADR-007). No
  command line any more; `quoth-bench` is the benchmark only.
- Direct edition: the permanent bundle ID `com.victorshammas.quoth.direct`
  and a Sparkle update feed from GitHub releases (ADR-005).
- Website at victorshammas.com/quoth: home, support and privacy pages, and
  an app bar linking Plainview, Gaugeline and Quoth.
- App Store: version 1.0, Apple silicon only; screenshots rendered from the
  app's real UI; listing text and review notes kept out of the repo.
- CI builds and tests both editions.

## Before the fork: Parrot (2026-05-10 – 2026-09-30)

Parrot by Humanitas Labs, released upstream as v0.1.x–v0.2.3; its history
is kept in this repo. In brief:

- A menu-bar dictation app: hold a key, speak, release, pasted at the
  cursor; WhisperKit on the Neural Engine; a recording pill with a level
  meter.
- From a LaunchAgent daemon to Parrot.app with launch at login, a signed
  and notarized DMG, and Sparkle updates.
- A dictionary (later a plain-text table) and a Whisper prompt from its
  example sentence.
- A Settings window: hotkey choice, live model switching with download
  status, multilingual models, a Language setting and Automatic detection
  among the user's languages.
- A first-run window explaining each permission before macOS asks.
- Faster capture through an AUHAL input unit, silence trimming and padding,
  a benchmark target, and a trailing space after each dictation.
