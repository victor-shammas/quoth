import Foundation
import ServiceManagement

/// Launch at login through `SMAppService.mainApp`: macOS starts Quoth.app
/// itself at login and lists it under System Settings → General → Login
/// Items. Needs the signed bundle; a bare `swift build` binary has none.
///
/// Behind "Open at login" in Settings › General.
enum LoginItem {
    /// Whether the setting can work: only inside Quoth.app.
    static var isAvailable: Bool { AppBundle.current != nil }

    /// On, or waiting for approval in System Settings.
    static var isEnabled: Bool {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval: return true
        default: return false
        }
    }

    /// Turns launch at login on or off.
    static func setEnabled(_ on: Bool) throws {
        if on {
            try SMAppService.mainApp.register()
            if SMAppService.mainApp.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
