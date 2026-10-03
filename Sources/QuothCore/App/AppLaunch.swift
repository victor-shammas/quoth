import AppKit
import ApplicationServices
import Foundation
import QuothDomain
import QuothPlatform

/// Quoth.app, when this process runs from it.
public enum AppBundle {
    /// Quoth's bundle identifier. TCC grants and the login item key to it,
    /// so it never changes (ADR-005): `com.victorshammas.quoth.direct` for the direct edition,
    /// `com.victorshammas.quoth` for the App Store build.
    static let identifiers: Set<String> = ["com.victorshammas.quoth.direct", "com.victorshammas.quoth"]

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
        if isatty(STDERR_FILENO) == 0 { LogFiles.redirectOutput() }

        switch InstanceLock.claim(Paths.instanceLock) {
        case .held(let lock): instanceLock = lock
        case .unavailable: break
        case .heldElsewhere:
            // LaunchServices normally brings the running copy forward instead;
            // this is `open -n`, or a login item racing a manual launch.
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

    /// Held for the life of the process.
    @MainActor private static var instanceLock: InstanceLock?

    /// Passed to the new launch by `relaunch()`, which opens it on the
    /// welcome window: Reopen was clicked there, so that's where the user
    /// expects to be, seeing the grant take.
    private static let continueSetupArgument = "--continue-setup"

    /// Whether this launch came from Reopen Quoth.
    static var isContinuingSetup: Bool { CommandLine.arguments.contains(continueSetupArgument) }

    /// Opens a new Quoth and quits this one, for a grant macOS shows only to
    /// a new launch (`Permissions.showsAfterRelaunch`). The new one starts
    /// once this one has let go of the instance lock.
    @MainActor
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = [continueSetupArgument]
        instanceLock = nil
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            Task { @MainActor in
                if let error {
                    Log.error("relaunch failed: \(error)")
                    if case .held(let lock) = InstanceLock.claim(Paths.instanceLock) { instanceLock = lock }
                    return
                }
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: - Startup failures

    /// Explains why Quoth can't start, in a dialog, since nobody reads the
    /// log, and offers the pane that fixes it.
    @MainActor
    static func presentStartupFailure(_ failure: StartupFailure) {
        NSApplication.shared.setActivationPolicy(.accessory)
        let message = appMessage(for: failure)
        if alert(message.title, message.body, buttons: ["Open System Settings", "Quit"]) == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(message.pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// The dialog's title and body, and the Privacy & Security pane it opens.
    static func appMessage(for failure: StartupFailure) -> (title: String, body: String, pane: String) {
        switch failure {
        case .microphoneDenied:
            return (
                "Quoth needs the microphone",
                "Turn on Quoth in System Settings → Privacy & Security → Microphone, then open Quoth again.",
                "Privacy_Microphone"
            )
        }
    }

    // MARK: -

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
