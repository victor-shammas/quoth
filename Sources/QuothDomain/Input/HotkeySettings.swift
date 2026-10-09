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

/// The keys Quoth can use as its dictation key (ADR-003): a modifier held on
/// its own in the direct edition, a key combination in the App Store
/// edition, which can't watch modifier keys (App Review, Guideline
/// 2.4.5(v)). The raw value is the name in `settings.json`.
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
    case optionSpace = "option-space"
    case controlOptionSpace = "control-option-space"
    case optionShiftSpace = "option-shift-space"
    case commandShiftSpace = "command-shift-space"

    /// The modifier keys, held on their own: the direct edition's choices.
    public static let modifierKeys: [HotkeyKey] = [
        .fn, .leftOption, .rightOption, .leftCommand, .rightCommand, .leftControl, .rightControl, .leftShift, .rightShift,
    ]
    /// Key combinations, registered with the system: the App Store
    /// edition's choices. None is a macOS shortcut by default.
    public static let shortcuts: [HotkeyKey] = [.optionSpace, .controlOptionSpace, .optionShiftSpace, .commandShiftSpace]

    /// Whether this is a key combination rather than a modifier key.
    public var isShortcut: Bool { Self.shortcuts.contains(self) }

    /// The keys an edition offers: `shortcuts` when its hotkey must be a
    /// key combination, else `modifierKeys`.
    public static func choices(shortcuts: Bool) -> [HotkeyKey] {
        shortcuts ? Self.shortcuts : modifierKeys
    }

    /// This key, or the edition's default when the edition can't use it: a
    /// settings file from the other edition, or from before the App Store
    /// edition used key combinations.
    public func usable(shortcuts: Bool) -> HotkeyKey {
        guard isShortcut != shortcuts else { return self }
        return shortcuts ? .optionSpace : .fn
    }

    /// The modifiers of a key combination, in the order macOS shows them
    /// (⌃⌥⇧⌘); empty for a modifier key.
    public var shortcutModifiers: [ShortcutModifier] {
        switch self {
        case .optionSpace: return [.option]
        case .controlOptionSpace: return [.control, .option]
        case .optionShiftSpace: return [.option, .shift]
        case .commandShiftSpace: return [.shift, .command]
        default: return []
        }
    }

    /// Everything about a key, in one place: which side, which modifier,
    /// and the virtual keycode its `flagsChanged` events carry (`kVK_…`).
    private var facts: (side: String?, modifier: String, symbol: String, keycode: Int64) {
        if isShortcut {
            let symbols = shortcutModifiers.map(\.symbol).joined()
            return (nil, symbols + "Space", symbols + "Space", 49)
        }
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
        default: return (nil, "", "", 0)
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

    /// A modifier's keycode, or for a key combination its key's (Space).
    public var keycode: Int64 { facts.keycode }
}

/// A modifier in a key combination.
public enum ShortcutModifier: Sendable {
    case control, option, shift, command

    public var symbol: String {
        switch self {
        case .control: return "⌃"
        case .option: return "⌥"
        case .shift: return "⇧"
        case .command: return "⌘"
        }
    }
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
