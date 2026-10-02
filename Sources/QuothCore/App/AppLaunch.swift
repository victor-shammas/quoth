import AppKit
import ApplicationServices
import Foundation

/// Quoth.app, when this process runs from it.
///
/// One executable, two roles: launched by LaunchServices (Finder, `open`,
/// the login item) it is the menu-bar app; run from a terminal, usually
/// through the `/usr/local/bin/quoth` symlink, it is the CLI.
public enum AppBundle {
    /// Quoth's bundle identifier. TCC grants and the login item key to it,
    /// so it never changes (ADR-005): `local.quoth` for local direct builds,
    /// `com.victorshammas.quoth` for the App Store build.
    static let identifiers: Set<String> = ["local.quoth", "com.victorshammas.quoth"]

    /// This bundle's identifier, or the direct build's outside a bundle.
    static var identifier: String {
        Bundle.main.bundleIdentifier.flatMap { identifiers.contains($0) ? $0 : nil } ?? "local.quoth"
    }

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

    /// Re-executes through the resolved path when this process was started
    /// through a symlink into a bundle. Foundation does not follow the link
    /// when it looks for the main bundle, so without this the CLI would not
    /// find Info.plist and `SMAppService.mainApp` would have no app to
    /// register. Same process, so nothing else changes. Returns if there is
    /// nothing to do or the exec fails.
    public static func resolveSymlinkedLaunch() {
        var size: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &size)
        var buffer = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&buffer, &size) == 0 else { return }
        let invoked = String(cString: buffer)
        guard let real = realpath(invoked, nil) else { return }
        let resolved = String(cString: real)
        free(real)
        guard resolved != invoked, resolved.contains(".app/Contents/MacOS/") else { return }
        // Only when a symlink is involved: realpath of an already-real path
        // that differs only in spelling (./, //) would exec for nothing.
        guard URL(fileURLWithPath: invoked).standardizedFileURL.path != resolved else { return }
        var argv: [UnsafeMutablePointer<CChar>?] = CommandLine.arguments.map { strdup($0) }
        argv.append(nil)
        execv(resolved, &argv)
    }
}

/// Setup that only the app role does: logging to files, the single-instance
/// lock, moving off a pre-app install, and explaining startup failures in a
/// dialog, since there is no terminal to print to.
public enum AppLaunch {
    /// True once `prepare()` ran: this process is the menu-bar app.
    public private(set) static var isApp = false

    /// Whether LaunchServices started this process as the app: inside the
    /// bundle, no subcommand or flags, and stdin not a terminal. Running the
    /// bundled executable from a terminal with no arguments is the CLI's
    /// foreground `run`. `-psn_` is the process serial number older systems
    /// pass to apps launched from Finder.
    static func isAppLaunch(arguments: [String], stdinIsTTY: Bool, inBundle: Bool) -> Bool {
        let args = arguments.dropFirst().filter { !$0.hasPrefix("-psn_") }
        return inBundle && !stdinIsTTY && args.isEmpty
    }

    /// `isAppLaunch` for this process.
    public static var launchedAsApp: Bool {
        isAppLaunch(
            arguments: CommandLine.arguments,
            stdinIsTTY: isatty(STDIN_FILENO) != 0,
            inBundle: AppBundle.current != nil
        )
    }

    /// Runs before the dictation loop when `launchedAsApp`. Exits the process
    /// if another Quoth is already running or the app runs from the DMG.
    @MainActor
    public static func prepare() {
        isApp = true
        redirectOutput()
        Log.info("Quoth \(AppBundle.version) starting")

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
    public static func claimSingleInstance() -> Bool {
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

    /// Explains a startup failure in a dialog when running as the app, where
    /// nobody reads stderr. The exit code rule in `Run` is unchanged.
    @MainActor
    public static func presentStartupFailure(_ failure: StartupFailure) {
        guard isApp else { return }
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

    /// Title, body, and the Privacy & Security pane to open, for the app's
    /// dialog. Permission failures get app wording; the rest reuse the CLI's.
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
        case .checksFailed, .warmupFailed:
            return ("Quoth couldn't start", Edition.hasDeveloperTools ? failure.message : "Quit Quoth and open it again. If this keeps happening, reinstall it.", nil)
        }
    }

    // MARK: -

    /// The app has no terminal: send stdout and stderr to the owner-only log
    /// files the LaunchAgent used, so `Log` output keeps landing in
    /// `Paths.logs`.
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
