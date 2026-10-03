import AppKit
import Foundation
import QuothDomain

/// macOS's own Dictation, whose keyboard shortcut can share Quoth's hotkey.
///
/// With Dictation on, macOS starts it on a double press of a modifier,
/// "Press 🌐 twice" by default. That is Quoth's hands-free gesture too, and
/// Quoth's tap only listens, so macOS sees the double press as well and
/// both start. Only the user can turn the shortcut off, in System Settings ›
/// Keyboard › Dictation.
public enum SystemDictation {
    public enum Clash: Equatable {
        /// Dictation's shortcut is a double press of this key's modifier.
        case clashes
        case none
        /// The settings can't be read (the App Store edition's sandbox).
        case unknown
    }

    /// Whether Dictation's shortcut clashes with `key` on this Mac.
    public static func clash(with key: HotkeyKey) -> Clash {
        // The sandbox keeps other apps' settings out of reach; don't knock.
        guard !Edition.isAppStore else { return .unknown }
        return clash(
            with: key,
            dictationEnabled: CFPreferencesCopyAppValue("Dictation Enabled" as CFString, "com.apple.assistant.support" as CFString) as? Bool,
            hotkeys: CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, "com.apple.symbolichotkeys" as CFString) as? [String: Any]
        )
    }

    /// Dictation's shortcut is system hotkey 164. A double press of a
    /// modifier is `type` "modifier" with that modifier's flag (the same bit
    /// as `CGEventFlags`: fn 0x800000, ⌘ 0x100000, ⌃ 0x40000) first in its
    /// `parameters`.
    public static func clash(with key: HotkeyKey, dictationEnabled: Bool?, hotkeys: [String: Any]?) -> Clash {
        guard let hotkeys else { return .unknown }
        guard dictationEnabled != false,
              let entry = hotkeys["164"] as? [String: Any],
              (entry["enabled"] as? Bool) ?? ((entry["enabled"] as? Int) == 1),
              let value = entry["value"] as? [String: Any],
              value["type"] as? String == "modifier",
              let modifier = (value["parameters"] as? [Any])?.first as? UInt64
        else { return .none }
        return modifier & key.flag.rawValue != 0 ? .clashes : .none
    }

    /// Opens System Settings › Keyboard, where the Dictation shortcut is.
    @MainActor
    public static func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
