import AppKit

// The App Store build's entry point: always the menu-bar app. It has no
// command line, no Sparkle and no doctor checks (Support/Edition.swift).
// The direct build's entry point is Sources/quoth/main.swift.

MainActor.assumeIsolated { AppLaunch.prepare() }
do {
    try Daemon.run(DaemonOptions(skipDoctor: true, debugHotkey: false, dumpWav: false, noOverlay: false, model: nil))
} catch let failure as StartupFailure {
    // As the direct build: a permanent failure exits 0, so launch at login
    // doesn't relaunch into the same dialog.
    Log.error(failure.message)
    MainActor.assumeIsolated { AppLaunch.presentStartupFailure(failure) }
    exit(failure.isPermanent ? 0 : 1)
} catch {
    Log.error("\(error)")
    exit(1)
}
