import CoreGraphics
import QuothDomain

/// What a `flagsChanged` event means for the hotkey. Pure, so the matching
/// is tested without a tap.
///
/// Side-specific keys match by the keycode each event carries, because left
/// and right share one flag bit, and the device-dependent low bits vary by
/// keyboard. fn matches by its flag.
public enum HotkeyMatching {
    /// The keycodes that count as another key in a chord: both sides of
    /// ⌘ ⇧ ⌥ ⌃, and fn. Not Caps Lock, nor keycodes Quoth doesn't know.
    public static let modifierKeycodes: Set<Int64> = [54, 55, 56, 58, 59, 60, 61, 62, 63]
    /// Flags that mean another modifier is down at the press.
    public static let chordFlags: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]

    /// The gesture input one event is for `key`, given whether the key is
    /// already held, or nil for an event that doesn't concern it.
    ///
    /// - A press: the key's keycode with its flag set (fn: its flag set on
    ///   any event).
    /// - A release: the key's keycode again, or its flag clear on any event
    ///   while held, which also catches a release that was never seen.
    /// - Another modifier's keycode while held: a chord.
    public static func input(keycode: Int64, flags: CGEventFlags, key: HotkeyKey, held: Bool) -> Gesture.Input? {
        let down = flags.contains(key.flag)
        if held {
            if !down { return .hotkeyUp }
            // This side went up while the other side still holds the shared flag.
            if key != .fn, keycode == key.keycode { return .hotkeyUp }
            if keycode != key.keycode, modifierKeycodes.contains(keycode) { return .otherModifier }
            return nil
        }
        guard down, key == .fn || keycode == key.keycode else { return nil }
        return .hotkeyDown(othersHeld: !flags.intersection(chordFlags).subtracting(key.flag).isEmpty)
    }

    /// Whether the hotkey was released while the tap was off: held when last
    /// seen, not held now. Only that is caught up on; a press missed while
    /// the tap was off doesn't start a recording halfway through.
    public static func missedRelease(wasHeld: Bool, heldNow: Bool) -> Bool {
        wasHeld && !heldNow
    }
}
