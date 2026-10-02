import AppKit

/// Status bar item in the top-right of the menu bar. Shows recording state at
/// a glance and provides the only persistent control surface for the daemon
/// (since we run as `.accessory` — no dock icon, no main window).
///
/// The menu has named slots, top to bottom: `statusLine`, `modelLine`,
/// `grantPermissionsItem`, `copyLastItem`, `fixLastItem`, `settingsItem`,
/// `checkForUpdatesItem`, `quitItem`. Features update a slot
/// rather than rebuilding the menu.
@MainActor
final class MenuBarController {
    private static func readyStatus(_ key: HotkeyKey) -> String { "Ready — hold \(key.shortName) to dictate" }

    private let statusItem: NSStatusItem
    /// Slot: what the dictation loop is doing. Driven as a `DictationObserver`.
    let statusLine: NSMenuItem
    /// Slot: a model downloading or loading; hidden otherwise.
    let modelLine: NSMenuItem
    /// Slot: reopens the onboarding window (#51). Shown in Quoth.app while
    /// a permission is missing.
    let grantPermissionsItem: NSMenuItem
    /// What `grantPermissionsItem` does; set by `OnboardingWindow`.
    var onGrantPermissions: (() -> Void)?
    /// Slot: opens the Settings window (#41) through `onOpenSettings`.
    let settingsItem: NSMenuItem
    /// Called by Settings…; set by the daemon, which owns the window.
    var onOpenSettings: (() -> Void)?
    /// Slot: asks Sparkle to check now. Hidden unless the updater is running,
    /// which it is only in Quoth.app's release builds.
    let checkForUpdatesItem: NSMenuItem
    /// Slot: quits quoth.
    let quitItem: NSMenuItem
    /// Copies the last dictation (`LastDictation`); disabled without one.
    let copyLastItem: NSMenuItem
    /// Opens Fix Last Dictation.
    let fixLastItem: NSMenuItem
    var onCopyLast: (() -> Void)?
    var onFixLast: (() -> Void)?

    /// A degraded hotkey tap replaces the idle line, so the menu bar does not
    /// claim fn works when it does not (#37).
    private var hotkeyHealth: HotkeyHealth = .ok
    /// The key the idle line tells the user to hold (#42).
    private var hotkey: HotkeyKey = .fn
    private var isIdle = true
    private var idleStatus: String { hotkeyHealth.statusText ?? Self.readyStatus(hotkey) }

    init(modelID: String) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.autoenablesItems = false

        statusLine = NSMenuItem(title: Self.readyStatus(.fn), action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)

        modelLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        modelLine.isEnabled = false
        modelLine.isHidden = true
        menu.addItem(modelLine)

        grantPermissionsItem = NSMenuItem(
            title: "Finish Setup…",
            action: #selector(grantPermissionsClicked),
            keyEquivalent: ""
        )
        grantPermissionsItem.isHidden = true
        menu.addItem(grantPermissionsItem)

        menu.addItem(.separator())

        copyLastItem = NSMenuItem(title: "Copy Last Dictation", action: #selector(copyLastClicked), keyEquivalent: "")
        copyLastItem.isEnabled = false
        menu.addItem(copyLastItem)
        fixLastItem = NSMenuItem(title: "Fix Last Dictation…", action: #selector(fixLastClicked), keyEquivalent: "")
        menu.addItem(fixLastItem)

        menu.addItem(.separator())

        settingsItem = NSMenuItem(title: "Settings…", action: #selector(settingsClicked), keyEquivalent: ",")
        menu.addItem(settingsItem)


        checkForUpdatesItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdatesClicked),
            keyEquivalent: ""
        )
        #if !APPSTORE
        checkForUpdatesItem.isHidden = !Updater.isRunning
        #endif
        menu.addItem(checkForUpdatesItem)

        menu.addItem(.separator())

        quitItem = NSMenuItem(
            title: "Quit Quoth",
            action: #selector(quitClicked),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        statusItem.menu = menu
        quitItem.target = self
        settingsItem.target = self
        copyLastItem.target = self
        fixLastItem.target = self
        checkForUpdatesItem.target = self
        grantPermissionsItem.target = self
        configureButton()
    }

    func setStatus(_ text: String) {
        statusLine.title = text
    }

    func setHotkeyHealth(_ health: HotkeyHealth) {
        hotkeyHealth = health
        if isIdle { setStatus(idleStatus) }
    }

    func setHotkey(_ key: HotkeyKey) {
        hotkey = key
        if isIdle { setStatus(idleStatus) }
    }

    /// A model downloading or loading, or nil to hide the line.
    func setModelStatus(_ text: String?) {
        modelLine.title = text ?? ""
        modelLine.isHidden = text == nil
    }

    private func configureButton() {
        setGlyph(.idle)
    }

    private func setGlyph(_ style: QuoteGlyph.Style) {
        statusItem.button?.image = QuoteGlyph.image(style)
    }

    /// Whether there is a last dictation to copy.
    func setLastDictationAvailable(_ available: Bool) {
        copyLastItem.isEnabled = available
    }

    @objc private func copyLastClicked() {
        onCopyLast?()
    }

    @objc private func fixLastClicked() {
        onFixLast?()
    }

    @objc private func settingsClicked() {
        onOpenSettings?()
    }

    @objc private func grantPermissionsClicked() {
        onGrantPermissions?()
    }

    @objc private func checkForUpdatesClicked() {
        #if !APPSTORE
        Updater.checkForUpdates()
        #endif
    }

    @objc private func quitClicked() {
        NSApp.terminate(nil)
    }
}

extension MenuBarController: DictationObserver {
    func dictationStarted() {
        isIdle = false
        setGlyph(.recording)
        setStatus("Recording…")
    }

    func dictationLocked() {
        isIdle = false
        setGlyph(.locked)
        setStatus("Locked — tap \(hotkey.shortName) to stop")
    }

    func dictationTranscribing() {
        isIdle = false
        setGlyph(.transcribing)
        setStatus("Transcribing…")
    }

    func dictationFinished(_ result: DictationResult) {
        isIdle = true
        setGlyph(.idle)
        setStatus(idleStatus)
    }

    func dictationFailed(_ error: Error) {
        isIdle = true
        setGlyph(.idle)
        setStatus(idleStatus)
    }
}
