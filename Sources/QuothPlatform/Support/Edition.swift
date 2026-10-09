import ApplicationServices
import CoreGraphics

/// Which of Quoth's two builds this is (ADR-006). One codebase:
///
/// - **Direct** (Swift package, `scripts/build-app.sh`): signed with a
///   Developer ID, free and open source. Uses Accessibility for the hotkey,
///   for pasting, and to read the focused field.
/// - **App Store** (Xcode project from `project.yml`, compiled with
///   `APPSTORE`): sandboxed. The hotkey is a key combination registered with
///   the system, which needs no grant (App Review ruled out Input
///   Monitoring, Guideline 2.4.5(v)); pasting needs its own grant; the
///   focused field can't be read.
///
/// Everything that differs is decided here, so the rest of the code asks a
/// question ("can it read the focused field?") rather than testing the flag.
public enum Edition {
    #if APPSTORE
    public static let isAppStore = true
    #else
    public static let isAppStore = false
    #endif

    /// Whether this build may insert text at the cursor by posting ⌘V. The
    /// App Store build keeps it behind its own grant, and turning this off
    /// makes it copy-only, should App Review rule out auto-paste (2.4.5).
    public static let allowsAutoPaste = true

    /// Whether the hotkey is a key combination registered with the system
    /// (`GlobalShortcut`) rather than a modifier key watched by an event tap.
    public static let hotkeyIsShortcut = isAppStore

    /// Whether the focused field can be read over Accessibility: for the
    /// password-field and focus checks, and for the text before the cursor.
    /// The sandbox forbids it, so the App Store build compares the frontmost
    /// app and asks macOS whether secure input is on instead.
    public static let readsFocusedField = !isAppStore

    /// Whether pasting is a grant of its own, offered in onboarding and
    /// Settings: in the App Store build, unless it is copy-only.
    public static let pasteNeedsOwnGrant = isAppStore && allowsAutoPaste

    /// Whether Quoth offers to open its settings and dictionary files in a
    /// text editor. In the sandbox they sit inside the container, where
    /// another app can't reliably open them; the editors in Settings cover
    /// everything there.
    public static let opensConfigFiles = !isAppStore
}

/// The grant the hotkey needs: Accessibility in the direct build (which also
/// covers pasting and reading the focused field). The App Store build's
/// hotkey, a registered key combination, needs none.
public enum HotkeyAccess {
    /// Whether the hotkey needs a grant at all.
    public static let needsGrant = !Edition.hotkeyIsShortcut

    public static var isGranted: Bool {
        #if APPSTORE
        true
        #else
        AXIsProcessTrusted()
        #endif
    }

    /// Shows the system prompt, which also lists Quoth in the pane.
    public static func request() {
        #if !APPSTORE
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        #endif
    }

    /// The grant's name in System Settings → Privacy & Security.
    public static let name = "Accessibility"

    /// Its pane, for `Permissions.openSettings(pane:)`.
    public static let settingsPane = "Privacy_Accessibility"
}

/// The grant for pasting at the cursor. The direct build has it with
/// Accessibility; the App Store build asks for it separately and, without
/// it, leaves each transcript on the clipboard.
public enum PasteAccess {
    public static var isGranted: Bool {
        guard Edition.allowsAutoPaste else { return false }
        #if APPSTORE
        return CGPreflightPostEventAccess()
        #else
        return AXIsProcessTrusted()
        #endif
    }

    public static func request() {
        #if APPSTORE
        _ = CGRequestPostEventAccess()
        #else
        HotkeyAccess.request()
        #endif
    }
}
