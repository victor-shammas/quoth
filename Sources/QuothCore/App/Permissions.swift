import AppKit
import ApplicationServices
import AVFoundation
import Foundation

/// The microphone grant as the onboarding window shows it.
enum MicrophonePermission: Equatable {
    case granted
    /// The system has never asked; a request shows its prompt.
    case notDetermined
    /// Denied or restricted: only System Settings can change it.
    case denied

    init(_ status: AVAuthorizationStatus) {
        switch status {
        case .authorized: self = .granted
        case .notDetermined: self = .notDetermined
        case .denied, .restricted: self = .denied
        @unknown default: self = .denied
        }
    }
}

/// The grants Quoth needs, read at one moment.
struct PermissionState: Equatable {
    /// The hotkey's grant (`HotkeyAccess`): Accessibility in the direct
    /// build, Input Monitoring in the App Store build.
    var accessibility: Bool
    var microphone: MicrophonePermission
    /// Pasting at the cursor (`PasteAccess`). Optional in the App Store
    /// build, which copies instead without it; covered by Accessibility in
    /// the direct build.
    var paste: Bool = true

    var allGranted: Bool { accessibility && microphone == .granted }

    /// This process's grants now.
    static var current: PermissionState {
        PermissionState(
            accessibility: HotkeyAccess.isGranted,
            microphone: MicrophonePermission(MicrophoneAccess.status),
            paste: Edition.isAppStore ? PasteAccess.isGranted : true
        )
    }
}

/// Reading and asking for Accessibility and Microphone (#51). The onboarding
/// window explains both before any of these requests is made.
enum Permissions {
    /// One thing an Allow button does.
    enum Step: Equatable {
        /// The hotkey grant's prompt (`HotkeyAccess.request`), which also
        /// lists Quoth in its pane.
        case promptAccessibility
        case openAccessibilitySettings
        /// The paste grant's prompt, App Store build only.
        case promptPaste
        case openPasteSettings
        case requestMicrophone
        case openMicrophoneSettings
    }

    /// The two grants, each with its own Allow button in the onboarding
    /// window, so macOS never shows both prompts at once.
    enum Kind: Equatable {
        case microphone
        case accessibility
        case paste
    }

    /// What Allow does for `kind` in `state`: the microphone prompt while
    /// the system has never asked, its System Settings pane once denied;
    /// the Accessibility prompt and its pane, so the user ends up where the
    /// switch is. Nothing once granted.
    static func allowSteps(for kind: Kind, in state: PermissionState) -> [Step] {
        switch kind {
        case .microphone:
            switch state.microphone {
            case .granted: return []
            case .notDetermined: return [.requestMicrophone]
            case .denied: return [.openMicrophoneSettings]
            }
        case .accessibility:
            return state.accessibility ? [] : [.promptAccessibility, .openAccessibilitySettings]
        case .paste:
            return state.paste ? [] : [.promptPaste, .openPasteSettings]
        }
    }

    static func perform(_ step: Step) {
        switch step {
        case .promptAccessibility:
            Log.info("asking for \(HotkeyAccess.name)")
            HotkeyAccess.request()
        case .openAccessibilitySettings:
            openSettings(pane: HotkeyAccess.settingsPane)
        case .promptPaste:
            Log.info("asking to paste at the cursor")
            PasteAccess.request()
        case .openPasteSettings:
            openSettings(pane: "Privacy_Accessibility")
        case .requestMicrophone:
            MicrophoneAccess.requestIfUndetermined()
        case .openMicrophoneSettings:
            openSettings(pane: "Privacy_Microphone")
        }
    }

    /// Opens System Settings → Privacy & Security at `pane`.
    static func openSettings(pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }
}
