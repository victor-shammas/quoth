import AppKit
import CoreGraphics
import Foundation
import QuothDomain

/// How a transcript goes in at the cursor.
///
/// Paste works in every app that pastes, including the terminals and
/// Electron editors that silently drop typed Unicode. It borrows the
/// clipboard for `TextInjector.settleDelay` and always gives it back.
/// Typing leaves the clipboard alone (`QUOTH_INJECT_MODE=type-unicode`).
public enum InjectMode: String, CaseIterable, Sendable {
    case paste
    case typeUnicode = "type-unicode"
}

/// Puts text at the cursor of the app in front, with synthesized key
/// presses: ⌘V over a borrowed clipboard, or typed Unicode.
@MainActor
public final class TextInjector {
    /// How long the app in front gets to read the clipboard before it is
    /// given back.
    public static let settleDelay: TimeInterval = 0.25

    public let mode: InjectMode
    private let clipboard: PasteboardSession

    public init(mode: InjectMode, pasteboard: NSPasteboard = .general) {
        self.mode = mode
        clipboard = PasteboardSession(
            pasteboard: SystemPasteboard(pasteboard),
            settleDelay: Self.settleDelay,
            postPaste: { Keystrokes.press(Keystrokes.v, flags: .maskCommand) }
        )
    }

    /// Inserts `text` at the cursor. Returns false when a paste wasn't
    /// read by the app in front, which leaves `text` on the clipboard.
    /// Typed text can't be checked, so it counts as landed.
    public func inject(_ text: String) async -> Bool {
        guard !text.isEmpty else { return true }
        switch mode {
        case .paste:
            return await withCheckedContinuation { done in
                clipboard.paste(text) { done.resume(returning: $0) }
            }
        case .typeUnicode:
            Keystrokes.type(text)
            return true
        }
    }

    /// Deletes `count` characters before the cursor, for "scratch that".
    public func deleteBackward(_ count: Int) {
        for _ in 0..<max(count, 0) {
            Keystrokes.press(Keystrokes.delete)
        }
    }

    /// Leaves `text` on the clipboard for the user to paste.
    public func copyToClipboard(_ text: String) {
        guard !text.isEmpty else { return }
        clipboard.copy(text)
    }
}

/// Synthesized key presses.
///
/// Each comes from a private `CGEventSource` with its flags set explicitly:
/// an event with no source takes on the modifiers the user is holding, and
/// a held Control or fn turned typed text into shortcuts.
///
/// They're posted at `.cgSessionEventTap`, where hardware events enter the
/// login session, so the app in front gets them exactly as key presses.
/// Quoth's own tap only listens, so it can't swallow them.
enum Keystrokes {
    static let v: CGKeyCode = 9 // kVK_ANSI_V
    static let delete: CGKeyCode = 51 // kVK_Delete
    /// `CGEventKeyboardSetUnicodeString` takes about 20 UTF-16 units an event.
    static let unicodeChunk = 20

    /// One press and release of `key` with exactly `flags`, carrying `unicode`
    /// on the key-down: some apps also insert a key-up's text, which typed
    /// everything twice.
    static func press(_ key: CGKeyCode, flags: CGEventFlags = [], unicode: [UniChar]? = nil, source: CGEventSource? = nil) {
        let source = source ?? CGEventSource(stateID: .privateState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else { return }
        down.flags = flags
        up.flags = flags
        if var unicode {
            down.keyboardSetUnicodeString(stringLength: unicode.count, unicodeString: &unicode)
        }
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
    }

    /// Types `text` as Unicode key events, a chunk at a time, never splitting
    /// a surrogate pair across two.
    static func type(_ text: String) {
        let source = CGEventSource(stateID: .privateState)
        let units = Array(text.utf16)
        var start = 0
        while start < units.count {
            var end = min(start + unicodeChunk, units.count)
            if end < units.count, UTF16.isLeadSurrogate(units[end - 1]) { end -= 1 }
            press(0, unicode: Array(units[start..<end]), source: source)
            start = end
        }
    }
}
