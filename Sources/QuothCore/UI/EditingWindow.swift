import AppKit

/// The standard editing shortcuts for a window's text fields. Quoth is a
/// menu-bar app with no main menu, and the main menu is what normally turns
/// ⌘C, ⌘V, ⌘X, ⌘A and ⌘Z into actions, so without this they do nothing.
enum EditingShortcuts {
    /// Performs `event` if it is one of them. ⌘W is the window's own
    /// business (`EditingWindow` closes, the Quote Card cancels).
    static func perform(_ event: NSEvent, in window: NSWindow) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command || flags == [.command, .shift],
              let key = event.charactersIgnoringModifiers?.lowercased()
        else { return false }
        let action: Selector?
        switch (key, flags == .command) {
        case ("x", true): action = #selector(NSText.cut(_:))
        case ("c", true): action = #selector(NSText.copy(_:))
        case ("v", true): action = #selector(NSText.paste(_:))
        case ("a", true): action = #selector(NSText.selectAll(_:))
        case ("z", true): action = Selector(("undo:"))
        case ("z", false): action = Selector(("redo:"))
        default: action = nil
        }
        guard let action else { return false }
        return NSApp.sendAction(action, to: nil, from: window)
    }

    static func isCloseWindow(_ event: NSEvent) -> Bool {
        event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
            && event.charactersIgnoringModifiers?.lowercased() == "w"
    }
}

/// A window whose text fields take the standard editing shortcuts, and that
/// closes on ⌘W and Escape, which the main menu would otherwise carry.
final class EditingWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if EditingShortcuts.isCloseWindow(event) {
            performClose(nil)
            return true
        }
        return EditingShortcuts.perform(event, in: self) || super.performKeyEquivalent(with: event)
    }

    /// Escape closes the window, unless a field editor takes it first.
    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }
}
