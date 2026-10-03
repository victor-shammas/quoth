import AppKit
import Observation
import QuothDomain

/// The menu bar item: Quoth's only lasting control surface, since it runs
/// as `.accessory`, with no Dock icon and no main window.
///
/// A view of `AppModel`: it shows the model's state and sends every click
/// to one of its intents. `render` re-runs whenever a property it read
/// changes.
@MainActor
final class MenuBarController: NSObject {
    private let model: AppModel
    private let statusItem: NSStatusItem

    /// What the dictation loop is doing, or why the hotkey isn't working.
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    /// A model downloading or loading; hidden otherwise.
    private let modelLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    /// Reopens the onboarding window while a grant is missing.
    private let finishSetupItem = NSMenuItem(title: "Finish Setup", action: #selector(finishSetup), keyEquivalent: "")
    /// Ends a locked recording, for when the hotkey can't (secure input).
    private let stopLockItem = NSMenuItem(title: "Stop Dictation", action: #selector(stopDictation), keyEquivalent: "")
    private let copyLastItem = NSMenuItem(title: "Copy Last Dictation", action: #selector(copyLastDictation), keyEquivalent: "")

    init(model: AppModel) {
        self.model = model
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        let menu = NSMenu()
        menu.autoenablesItems = false
        statusLine.isEnabled = false
        modelLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(modelLine)
        menu.addItem(finishSetupItem)
        menu.addItem(stopLockItem)
        menu.addItem(.separator())
        menu.addItem(item("New Quote Card", #selector(newQuoteCard)))
        menu.addItem(copyLastItem)
        menu.addItem(.separator())
        menu.addItem(item("Settings", #selector(openSettings), key: ","))
        // The App Store build updates through the App Store only (2.4.5).
        #if !APPSTORE
        if Updater.isRunning {
            menu.addItem(item("Check for Updates", #selector(checkForUpdates)))
        }
        #endif
        menu.addItem(.separator())
        menu.addItem(item("Quit Quoth", #selector(quit), key: "q"))
        for item in menu.items { item.target = self }
        statusItem.menu = menu

        render()
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        NSMenuItem(title: title, action: action, keyEquivalent: key)
    }

    /// Shows the model's state, and runs again when any of it changes.
    private func render() {
        withObservationTracking {
            statusLine.title = model.statusText
            modelLine.title = model.modelStatus ?? ""
            modelLine.isHidden = model.modelStatus == nil
            finishSetupItem.isHidden = !model.setupNeeded
            stopLockItem.isHidden = model.activity != .locked
            copyLastItem.isEnabled = model.hasLastDictation
            statusItem.button?.image = QuoteGlyph.image(model.glyph)
        } onChange: { [weak self] in
            // Called before the change lands; render once it has.
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.render() }
            }
        }
    }

    @objc private func finishSetup() { model.finishSetup() }
    @objc private func stopDictation() { model.stopDictation() }
    @objc private func newQuoteCard() { model.newQuoteCard() }
    @objc private func copyLastDictation() { model.copyLastDictation() }
    @objc private func openSettings() { model.openSettings() }
    @objc private func quit() { model.quit() }

    @objc private func checkForUpdates() {
        #if !APPSTORE
        Updater.checkForUpdates()
        #endif
    }
}
