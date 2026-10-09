# ADR-008 :: The App Store edition's hotkey is a registered key combination

Last updated: `2026.10.09`

> App Review ruled out Input Monitoring for the App Store edition (Guideline 2.4.5(v), review of 1.0 (2), 2026-10-08). That edition's hotkey is now a key combination registered with macOS, ⌥Space by default, which needs no permission. The direct edition keeps ADR-003's modifier key and event tap.

## 1. Decision

- **App Store edition:** the hotkey is one of four key combinations: ⌥Space (default), ⌃⌥Space, ⌥⇧Space, ⇧⌘Space. None is a macOS shortcut by default. `GlobalShortcut` registers it with `RegisterEventHotKey`, which works in the sandbox, asks for no grant, and reports both the press and the release. The press and release feed the same `Gesture`, so hold-to-talk, the 0.3 s minimum hold and the double-tap lock behave as before. A combination is never a chord, since its modifiers are part of it.
- **Direct edition:** unchanged (ADR-003): a modifier key through a listen-only `flagsChanged` tap, under Accessibility.
- **Which kind:** `Edition.hotkeyIsShortcut`. `SettingsStore` fits a saved key to the edition (`HotkeyKey.usable`). A file from the other edition, or the default `fn`, becomes the edition's default.
- **No tap in the App Store edition:** `EventTap.start` refuses there, so nothing can ask for Input Monitoring. `HotkeyAccess` reports no grant needed, and the onboarding window has no hotkey row.
- **A taken combination** (another app registered it first) shows "Another app uses this hotkey" in the menu (`HotkeyHealth.shortcutTaken`). Choosing another in Settings registers that one at once.

## 2. Rationale

Input Monitoring was the least access a modifier-key hotkey could have. App Review doesn't accept it for this purpose, and a sandboxed app can't get Accessibility. A registered combination is the system's own mechanism for global shortcuts: the app sees only its combination, so it can't see typing at all.

The cost: fn and single modifiers aren't available in the App Store edition, and the combination is consumed. With ⌥Space, the non-breaking space it would otherwise type can't be typed. A fixed short list keeps the Settings picker as it was. Recording any combination was left out to keep the resubmission small.

## 3. When to Revisit

- If users ask for other combinations: a shortcut recorder in Settings, checking that the combination isn't one macOS already uses.
- If App Review's position on Input Monitoring changes, or macOS adds a supported way to watch a single modifier without a grant.
