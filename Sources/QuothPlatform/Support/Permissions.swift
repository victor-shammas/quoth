import AppKit
import ApplicationServices
import AVFoundation
import Foundation
import QuothDomain

/// The microphone grant as the onboarding window shows it.
public enum MicrophonePermission: Equatable {
    case granted
    /// The system has never asked; a request shows its prompt.
    case notDetermined
    /// Denied or restricted: only System Settings can change it.
    case denied

    public init(_ status: AVAuthorizationStatus) {
        switch status {
        case .authorized: self = .granted
        case .notDetermined: self = .notDetermined
        case .denied, .restricted: self = .denied
        @unknown default: self = .denied
        }
    }
}

/// The grants Quoth needs, read at one moment.
public struct PermissionState: Equatable {
    /// The hotkey's grant (`HotkeyAccess`): Accessibility in the direct
    /// build, Input Monitoring in the App Store build.
    public var hotkey: Bool
    public var microphone: MicrophonePermission
    /// Pasting at the cursor (`PasteAccess`). Optional in the App Store
    /// build, which copies instead without it; covered by Accessibility in
    /// the direct build.
    public var paste: Bool = true

    public var allGranted: Bool { hotkey && microphone == .granted }

    /// This process's grants now.
    public static var current: PermissionState {
        PermissionState(
            hotkey: HotkeyAccess.isGranted,
            microphone: MicrophonePermission(MicrophoneAccess.status),
            paste: Edition.pasteNeedsOwnGrant ? PasteAccess.isGranted : true
        )
    }
}

/// Reading and asking for Accessibility and Microphone. The onboarding
/// window explains both before any of these requests is made.
public enum Permissions {
    /// One thing an Allow button does.
    public enum Step: Equatable {
        /// The hotkey grant's prompt (`HotkeyAccess.request`), which also
        /// lists Quoth in its pane.
        case promptHotkey
        case openHotkeySettings
        /// The paste grant's prompt, App Store build only.
        case promptPaste
        case openPasteSettings
        case requestMicrophone
        case openMicrophoneSettings
    }

    /// The two grants, each with its own Allow button in the onboarding
    /// window, so macOS never shows both prompts at once.
    public enum Kind: Hashable {
        case microphone
        case hotkey
        case paste
    }

    /// What Allow does for `kind` in `state`: the microphone prompt while
    /// the system has never asked, its System Settings pane once denied;
    /// the Accessibility prompt and its pane, so the user ends up where the
    /// switch is. Nothing once granted.
    /// Whether a grant made while Quoth runs shows only to a new launch. In
    /// the App Store edition, Input Monitoring and pasting are read with
    /// CGPreflightListenEventAccess and CGPreflightPostEventAccess, which
    /// keep their first answer for the life of the process. The microphone,
    /// and Accessibility in the direct edition, are read live.
    public static func showsAfterRelaunch(_ kind: Kind) -> Bool {
        Edition.isAppStore && kind != .microphone
    }

    public static func allowSteps(for kind: Kind, in state: PermissionState) -> [Step] {
        switch kind {
        case .microphone:
            switch state.microphone {
            case .granted: return []
            case .notDetermined: return [.requestMicrophone]
            case .denied: return [.openMicrophoneSettings]
            }
        case .hotkey:
            return state.hotkey ? [] : [.promptHotkey, .openHotkeySettings]
        case .paste:
            return state.paste ? [] : [.promptPaste, .openPasteSettings]
        }
    }

    public static func perform(_ step: Step) {
        switch step {
        case .promptHotkey:
            Log.info("asking for \(HotkeyAccess.name)")
            HotkeyAccess.request()
        case .openHotkeySettings:
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
    public static func openSettings(pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }
}
