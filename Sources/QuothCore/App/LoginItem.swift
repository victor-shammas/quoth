import AppKit
import Foundation
import ServiceManagement

/// Launch at login through `SMAppService.mainApp`: macOS starts Quoth.app
/// itself at login and lists it under System Settings → General → Login
/// Items. Needs the signed bundle; a bare `swift build` binary has none.
///
/// Behind `quoth install --launch-at-login`, `quoth install --uninstall`,
/// and the "Launch at login" menu item.
public enum LoginItem {
    /// Register Quoth to start at login (`quoth install --launch-at-login`),
    /// and start it now.
    public static func install() throws {
        guard let app = AppBundle.current else {
            Log.error("launch at login needs Quoth.app. Install it from the DMG, then run this again.")
            throw SilentExit(1)
        }

        do {
            try SMAppService.mainApp.register()
        } catch {
            Log.error("couldn't register the login item: \(error)")
            throw SilentExit(1)
        }

        switch SMAppService.mainApp.status {
        case .requiresApproval:
            print("! launch at login needs your approval")
            print("  System Settings → General → Login Items → allow Quoth")
            SMAppService.openSystemSettingsLoginItems()
        default:
            print("✓ launch at login on")
        }
        print("  app:  \(app.path)")
        print("  logs: \(Paths.logs.path)/")

        // The old agent started the daemon right away; so does this. A
        // second copy exits at once on the instance lock.
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = [app.path]
        try? open.run()
        open.waitUntilExit()
    }

    /// Remove launch at login, quit the app, and delete logs and caches
    /// (`quoth install --uninstall`). Config and models stay.
    public static func uninstall() throws {
        if AppBundle.current != nil, SMAppService.mainApp.status != .notRegistered {
            do {
                try SMAppService.mainApp.unregister()
                print("✓ launch at login off")
            } catch {
                Log.warning("couldn't unregister the login item: \(error)")
            }
        } else {
            print("launch at login was not on")
        }
        let me = ProcessInfo.processInfo.processIdentifier
        for running in NSRunningApplication.runningApplications(withBundleIdentifier: AppBundle.identifier)
        where running.processIdentifier != me {
            running.terminate()
            print("  quit Quoth (pid \(running.processIdentifier))")
        }

        for dir in [Paths.logs, Paths.caches] where Paths.fileType(dir.path) != nil {
            try FileManager.default.removeItem(at: dir)
            print("  removed \(dir.path)")
        }
    }

    /// Whether the menu item can work: only inside Quoth.app.
    static var isAvailable: Bool { AppBundle.current != nil }

    /// On, or waiting for approval in System Settings.
    static var isEnabled: Bool {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval: return true
        default: return false
        }
    }

    /// Turns launch at login on or off from the menu.
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
