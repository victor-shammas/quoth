# ADR-003 :: Push-to-talk on a single modifier key, with a hands-free lock

Last updated: `2026.10.02`

> Quoth's main interaction is: hold a modifier key, speak, release. A double tap locks recording on for hands-free dictation, and the next tap stops it. The key is configurable among fn and the left or right Option, Command, Control, and Shift keys. The event tap listens to modifier changes only, so Quoth never sees what the user types.

## 1. Decision

- **Push-to-talk first.** Recording starts on key-down and ends on key-up.
- **A double-tap lock for long dictation.** A short tap followed within 0.4 s by a second short tap locks recording on; the next press of the hotkey stops it and transcribes. The lock is a few states in `Gesture`, has a 10-minute cap, and can be turned off in Settings. While locked, live text transcribes and types each segment at a pause.
- **The hotkey is a single modifier.** Choices are fn (default) and the left or right Option, Command, Control, and Shift keys, matched by keycode so left and right are distinct.
- **The event tap is `flagsChanged`-only and listen-only.** It never subscribes to key-down or key-up events and never swallows events.
- **Shortcuts on the hotkey do not produce text.** A capture shorter than 0.3 s is discarded without transcribing, and a recording is cancelled if another modifier changes while the hotkey is held.

## 2. Rationale

A tap that sees key-down events sees every keystroke, including passwords; that is keylogger surface Quoth does not need. A modifier-only tap cannot see the C in ⌘C, which is why side-specific shortcuts are handled with the short-capture and chord rules rather than by inspecting keys.

Upstream rejected toggle and latch modes to keep one interaction that cannot be left recording by accident. Quoth reverses that for long-form dictation, the case section 4 anticipated: holding a key for minutes is impractical. The lock keeps push-to-talk unchanged (a second press held past the minimum hold is ordinary push-to-talk, never a lock) and answers the original concerns with a length cap and a visible lock in the pill. Non-modifier keys and chords were rejected because a listen-only tap cannot stop them from also reaching the focused app.

Fn stays the default because it is otherwise unused on Apple keyboards, but it never reaches macOS on many third-party keyboards and the macOS 27 beta stops delivering it to taps, so a configurable key is required.

## 3. Design Implications

- Rule: the event tap mask is `flagsChanged` only, including in debug modes.
- Gesture logic (short-capture discard, chord cancel) is a small pure type with tests, separate from audio and UI.
- Focus-drift detection happens at delivery time through Accessibility, never by widening the tap.

## 4. When to Revisit

- If users need hands-free dictation (for long-form writing or accessibility), a toggle mode with a length cap would reopen this.
- If macOS offers a supported global-shortcut API that can consume a key without an event tap.
