import AppKit

/// A window whose text fields take the standard editing shortcuts. Quoth is
/// a menu-bar app with no main menu, and the main menu is what normally
/// turns ⌘C, ⌘V, ⌘X, ⌘A and ⌘Z into actions, so without this they do
/// nothing. Also closes on ⌘W and Escape, which the main menu would
/// otherwise carry.
final class EditingWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command || flags == [.command, .shift],
              let key = event.charactersIgnoringModifiers?.lowercased()
        else { return super.performKeyEquivalent(with: event) }
        let action: Selector?
        switch (key, flags == .command) {
        case ("w", true): action = #selector(NSWindow.performClose(_:))
        case ("x", true): action = #selector(NSText.cut(_:))
        case ("c", true): action = #selector(NSText.copy(_:))
        case ("v", true): action = #selector(NSText.paste(_:))
        case ("a", true): action = #selector(NSText.selectAll(_:))
        case ("z", true): action = Selector(("undo:"))
        case ("z", false): action = Selector(("redo:"))
        default: action = nil
        }
        if let action, NSApp.sendAction(action, to: nil, from: self) { return true }
        return super.performKeyEquivalent(with: event)
    }

    /// Escape closes the window, unless a field editor takes it first.
    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }
}
