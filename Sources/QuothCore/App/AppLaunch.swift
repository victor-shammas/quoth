import AppKit
import ApplicationServices
import Foundation

/// Quoth.app, when this process runs from it.
public enum AppBundle {
    /// Quoth's bundle identifier. TCC grants and the login item key to it,
    /// so it never changes (ADR-005): `local.quoth` for local direct builds,
    /// `com.victorshammas.quoth` for the App Store build.
    static let identifiers: Set<String> = ["local.quoth", "com.victorshammas.quoth"]

    /// The bundle's URL when the main bundle is Quoth.app, else nil (a bare
    /// `swift build` binary).
    static var current: URL? {
        let url = Bundle.main.bundleURL
        guard url.pathExtension == "app", let id = Bundle.main.bundleIdentifier, identifiers.contains(id) else { return nil }
        return url
    }

    /// The release version from Info.plist, or "dev" outside the bundle.
    public static var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"
    }
}

/// Setup before the dictation loop: logging to files, the single-instance
/// lock, refusing to run from the disk image, and explaining startup
/// failures in a dialog.
enum AppLaunch {
    /// Runs before the dictation loop. Exits the process if another Quoth is
    /// already running or the app runs from the DMG.
    @MainActor
    static func prepare() {
        // Started from a terminal, a developer reads the log there.
        if isatty(STDERR_FILENO) == 0 { redirectOutput() }

        guard claimSingleInstance() else {
            // LaunchServices normally activates the running copy instead; this
            // is `open -n` or a login item racing a manual launch.
            Log.info("another Quoth is running; exiting")
            exit(0)
        }

        NSApplication.shared.setActivationPolicy(.accessory)
        guard let bundle = AppBundle.current else { return }

        if isOnDiskImageOrTranslocated(bundle) {
            _ = alert(
                "Move Quoth to Applications",
                "Quoth is running from the disk image. Drag it to the Applications folder, then open it from there.",
                buttons: ["Quit"]
            )
            exit(0)
        }
    }

    // MARK: - Single instance

    private static var lockDescriptor: Int32 = -1

    /// Takes the instance lock for this process's lifetime. False if another
    /// Quoth holds it. Idempotent. If the lock file can't be opened, runs
    /// anyway: one extra instance is better than none.
    static func claimSingleInstance() -> Bool {
        if lockDescriptor >= 0 { return true }
        do {
            try Paths.prepareDirectory(Paths.appSupport)
        } catch {
            Log.warning("couldn't prepare \(Paths.appSupport.path): \(error)")
            return true
        }
        let fd = open(Paths.instanceLock.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else {
            Log.warning("couldn't open \(Paths.instanceLock.path)")
            return true
        }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            return false
        }
        lockDescriptor = fd
        return true
    }

    // MARK: - Startup failures

    /// Explains a startup failure in a dialog, since nobody reads the log.
    @MainActor
    static func presentStartupFailure(_ failure: StartupFailure) {
        NSApplication.shared.setActivationPolicy(.accessory)
        let (title, message, pane) = appMessage(for: failure)
        if let pane {
            if alert(title, message, buttons: ["Open System Settings", "Quit"]) == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
                NSWorkspace.shared.open(url)
            }
        } else {
            _ = alert(title, message, buttons: ["Quit"])
        }
    }

    /// Title, body, and the Privacy & Security pane to open, for the dialog.
    static func appMessage(for failure: StartupFailure) -> (String, String, String?) {
        switch failure {
        case .microphoneDenied:
            return (
                "Quoth needs the microphone",
                "Turn on Quoth in System Settings → Privacy & Security → Microphone, then open Quoth again.",
                "Privacy_Microphone"
            )
        case .unknownModel, .noModelsRegistered:
            return (
                "Quoth couldn't find its speech model",
                "Reinstall Quoth, then open it again. Your settings and dictionary are kept.",
                nil
            )
        case .hotkeyUnavailable:
            return (
                "Quoth can't watch the dictation key",
                "Allow Quoth under System Settings → Privacy & Security → \(HotkeyAccess.name), then open Quoth again.",
                HotkeyAccess.settingsPane
            )
        case .warmupFailed:
            return ("Quoth couldn't start", "Quit Quoth and open it again. If this keeps happening, reinstall it.", nil)
        }
    }

    // MARK: -

    /// The app has no terminal: send stdout and stderr to the owner-only log
    /// files in `Paths.logs`.
    private static func redirectOutput() {
        do {
            try Paths.prepareDirectory(Paths.logs)
            for (file, fd) in [(Paths.daemonOutLog, STDOUT_FILENO), (Paths.daemonErrLog, STDERR_FILENO)] {
                try Paths.preparePrivateFile(file)
                let out = open(file.path, O_WRONLY | O_APPEND | O_NOFOLLOW | O_CLOEXEC)
                guard out >= 0 else { continue }
                dup2(out, fd)
                close(out)
            }
            setvbuf(stdout, nil, _IOLBF, 0)
        } catch {
            // Logging is best effort; the app still runs.
        }
    }

    private static func isOnDiskImageOrTranslocated(_ bundle: URL) -> Bool {
        let path = bundle.path
        if path.contains("/AppTranslocation/") { return true }
        let values = try? bundle.resourceValues(forKeys: [.volumeIsReadOnlyKey])
        return values?.volumeIsReadOnly == true
    }

    @MainActor
    private static func alert(_ title: String, _ message: String, buttons: [String]) -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        for button in buttons { alert.addButton(withTitle: button) }
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }
}
