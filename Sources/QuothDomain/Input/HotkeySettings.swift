import Foundation

/// The dictation key and what a double tap does (`Settings.hotkey`).
public struct HotkeySettings: Codable, Equatable {
    /// The modifier held to dictate.
    public var key: HotkeyKey = .fn
    /// Whether a double tap locks recording on, for hands-free dictation;
    /// the next tap stops it.
    public var doubleTapLock = true
    /// Whether a locked recording types its text at each pause instead of
    /// all at the end.
    public var liveText = true
    /// Where a locked dictation goes: the cursor, or the Quote Card to edit
    /// first.
    public var lockTarget: LockTarget = .cursor

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // A key or target this version doesn't know, from a hand edit or a
        // newer Quoth, falls back to the default rather than failing the file.
        key = (try? c.value(.key, or: key)) ?? key
        doubleTapLock = try c.value(.doubleTapLock, or: doubleTapLock)
        liveText = try c.value(.liveText, or: liveText)
        lockTarget = (try? c.value(.lockTarget, or: lockTarget)) ?? lockTarget
    }
}

/// The modifiers Quoth can use as its dictation key (ADR-003). The raw value
/// is the name in `settings.json`.
public enum HotkeyKey: String, Codable, CaseIterable, Sendable {
    case fn
    case leftOption = "left-option"
    case rightOption = "right-option"
    case leftCommand = "left-command"
    case rightCommand = "right-command"
    case leftControl = "left-control"
    case rightControl = "right-control"
    case leftShift = "left-shift"
    case rightShift = "right-shift"

    /// Everything about a key, in one place: which side, which modifier,
    /// and the virtual keycode its `flagsChanged` events carry (`kVK_…`).
    private var facts: (side: String?, modifier: String, symbol: String, keycode: Int64) {
        switch self {
        case .fn: return (nil, "fn", "fn", 63)
        case .leftOption: return ("left", "Option", "⌥", 58)
        case .rightOption: return ("right", "Option", "⌥", 61)
        case .leftCommand: return ("left", "Command", "⌘", 55)
        case .rightCommand: return ("right", "Command", "⌘", 54)
        case .leftControl: return ("left", "Control", "⌃", 59)
        case .rightControl: return ("right", "Control", "⌃", 62)
        case .leftShift: return ("left", "Shift", "⇧", 56)
        case .rightShift: return ("right", "Shift", "⇧", 60)
        }
    }

    /// In the Settings window: "Right Option (⌥)".
    public var displayName: String {
        guard let side = facts.side else { return facts.modifier }
        return "\(side.capitalized) \(facts.modifier) (\(facts.symbol))"
    }

    /// In the menu and the log: "hold right ⌥ to dictate".
    public var shortName: String {
        guard let side = facts.side else { return facts.symbol }
        return "\(side) \(facts.symbol)"
    }

    public var keycode: Int64 { facts.keycode }
}

/// Where a hands-free dictation goes.
public enum LockTarget: String, Codable, CaseIterable {
    case cursor
    case card

    public var displayName: String {
        switch self {
        case .cursor: return "At the cursor"
        case .card: return "Quote Card"
        }
    }
}
