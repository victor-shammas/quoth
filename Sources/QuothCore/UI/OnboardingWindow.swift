import AppKit
import QuothDomain
import QuothPlatform
import SwiftUI

/// The welcome window: the hotkey, the languages, and each permission with
/// its own Allow button, so macOS never asks before Quoth has said why.
///
/// It opens at launch until the user has been through it once (Get Started,
/// or closing it), and after that only while a grant is missing, or after
/// Reopen Quoth; Finish Setup in the menu reopens it. While a grant is missing it also keeps
/// `AppModel.setupNeeded` current, polling, since Accessibility has no
/// change notification.
@MainActor
final class OnboardingWindow: NSObject, NSWindowDelegate {
    private static let pollInterval: TimeInterval = 1

    private let store: SettingsStore
    private weak var app: AppModel?
    private var window: NSWindow?
    private var model: OnboardingModel?
    private var poll: Timer?
    /// Allow was clicked, and the window hasn't come back since.
    private var awaitingReturn = false

    init(store: SettingsStore, app: AppModel) {
        self.store = store
        self.app = app
    }

    /// At launch: opens the window if `Onboarding.showsWindow` says so.
    func startIfNeeded() {
        refresh()
        let continuing = AppLaunch.isContinuingSetup
        if continuing { Log.info("reopened from the welcome window") }
        guard continuing
            || Onboarding.showsWindow(completed: store.current.onboarding.completed, state: PermissionState.current)
        else { return }
        Log.info("showing the onboarding window")
        // Once the run loop is up, so activation brings the window forward.
        DispatchQueue.main.async { self.show() }
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        startPolling()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // Activation can be refused (a login-item launch while the user
        // works elsewhere); the window still comes forward.
        window.orderFrontRegardless()
    }

    private func makeWindow() -> NSWindow {
        let model = OnboardingModel(settings: store.current)
        model.onGetStarted = { [weak self, weak model] in
            guard let self, let model else { return }
            store.write(Onboarding.apply(hotkey: model.hotkey, languages: model.languages, preferred: model.preferred, to: store.current))
            Log.info("onboarding done: hold \(model.hotkey.shortName); languages \(model.languages.joined(separator: ", "))")
            self.window?.close()
        }
        model.onAllow = { [weak self] in self?.awaitingReturn = true }
        self.model = model
        let hosting = NSHostingView(rootView: OnboardingView(model: model))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.contentView = hosting
        window.title = "Welcome to Quoth"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = Latte.windowBackground
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        // Comes forward on the Space the user is on, not the one it opened on.
        window.collectionBehavior = .moveToActiveSpace
        window.delegate = self
        window.center()
        return window
    }

    /// Brings the window back after an Allow. Quoth has no Dock icon, so
    /// when macOS's prompt closes, or the user leaves System Settings, focus
    /// goes to the app before, over this window. Checked on each poll rather
    /// than on the grant, which lands while the prompt is still closing, and
    /// which in the App Store edition this launch can't see at all.
    private func returnIfLeft() {
        guard awaitingReturn, let front = NSWorkspace.shared.frontmostApplication else { return }
        if front.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            // Back already, by the user's own click.
            awaitingReturn = false
        } else if front.activationPolicy == .regular, front.bundleIdentifier != "com.apple.systempreferences" {
            awaitingReturn = false
            Log.info("onboarding: back in front of \(front.localizedName ?? "another app")")
            show()
        }
    }

    // MARK: Grants

    /// Polls while the window is open or a grant is missing, so the
    /// checkmarks and Finish Setup follow System Settings.
    private func startPolling() {
        guard poll == nil else { return }
        poll = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private func refresh() {
        returnIfLeft()
        let state = PermissionState.current
        model?.update(state)
        app?.setupNeeded = !state.allGranted
        if state.allGranted, window == nil {
            poll?.invalidate()
            poll = nil
        } else {
            startPolling()
        }
    }

    // MARK: NSWindowDelegate

    /// Only for the close button and ⌘W, not for Get Started's `close()` or
    /// quitting: closing by hand counts as done, without saving the hotkey
    /// and languages shown.
    nonisolated func windowShouldClose(_ sender: NSWindow) -> Bool {
        MainActor.assumeIsolated {
            if !store.current.onboarding.completed { store.update { $0.onboarding.completed = true } }
        }
        return true
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            window = nil
            model = nil
            awaitingReturn = false
            refresh()
        }
    }
}
