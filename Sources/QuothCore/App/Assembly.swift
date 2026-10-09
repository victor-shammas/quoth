import AppKit
import Foundation
import QuothDomain
import QuothPlatform
import QuothSpeech

/// Builds Quoth's objects, connects them, and runs the AppKit loop
/// (ADR-007). No behaviour of its own: what happens on a press is
/// `DictationSession`'s, what the menu shows and does is `AppModel`'s.
/// Does not return once running.
enum Assembly {
    /// Throws `StartupFailure` if Quoth cannot start.
    @MainActor
    static func run() throws {
        let settings = SettingsStore()
        let model = try Startup.check(modelID: settings.current.model.id)
        let options = DeveloperOptions.current
        NSApplication.shared.setActivationPolicy(.accessory)
        // Before the menu, which offers "Check for Updates" only when running.
        #if !APPSTORE
        if AppBundle.current != nil { Updater.start() }
        #endif

        let transcriber = WhisperKitTranscriber(model: model)
        let capture = AudioCapture()
        capture.builtInWhileBluetoothPlays = settings.current.microphone.builtInWhileBluetoothPlays
        // Fades other sound down while the microphone is on, if Settings
        // asks; first, any volume a Quoth that quit mid-fade left down.
        let fader = OutputFader()
        fader.recoverAfterQuit()
        let microphone = FadingMicrophone(capture, fader: fader)
        microphone.isEnabled = settings.current.sound.fadeWhileDictating
        let overlay = RecordingOverlay()
        capture.onLevel = { level in overlay.pushLevel(level) }
        // The dictionary: created on first run, reloaded when it changes.
        let dictionary = DictionaryStore()
        dictionary.createIfMissing()
        let monitor = HotkeyMonitor(
            key: settings.current.hotkey.key,
            lockEnabled: settings.current.hotkey.doubleTapLock,
            debug: options.debugHotkey
        )
        if SystemDictation.clash(with: monitor.key) == .clashes {
            Log.warning("macOS Dictation's shortcut is a double press of \(monitor.key.shortName) too, so a hands-free lock starts it as well; turn it off in System Settings › Keyboard › Dictation")
        }
        let card = QuoteCard()
        let switcher = ModelSwitcher(model: model, transcriber: transcriber)
        let app = AppModel(
            settings: settings,
            dictionary: dictionary,
            monitor: monitor,
            delivery: TextDelivery(mode: options.injectMode),
            overlay: overlay,
            card: card,
            switcher: switcher
        )
        // The pill first, then the menu: the order the UI updated in before.
        // The Quote Card follows the loop to show what it's doing, and to run
        // Insert or Copy once a dictation still running has finished.
        let session = DictationSession(
            capture: microphone,
            transcriber: transcriber,
            processors: [VoiceCommands(), DictionaryProcessor(store: dictionary)],
            observers: [overlay, app, LatencyLog(), card],
            dumpWav: options.dumpWav,
            delivery: app.delivery,
            context: { [unowned app] in app.transcriptionContext() }
        )
        session.liveText = settings.current.hotkey.liveText
        session.card = card
        session.lockOpensCard = { [unowned app] in app.lockOpensCard }
        session.onTranscript = { [unowned app] in app.remember($0) }
        session.onEndLock = { monitor.endLock(reason: $0) }
        // The microphone failed to start: this press must not go on to
        // lock or transcribe a recording that isn't there.
        session.onAbandonPress = { monitor.abandonPress() }
        app.session = session
        switcher.session = session
        switcher.app = app
        card.host = app

        let menuBar = MenuBarController(model: app)
        // Explains each grant before macOS asks for it.
        app.onboarding.startIfNeeded()

        // A headset connecting mid-lock ends the lock and keeps what was
        // said before it; push-to-talk still discards a changed route.
        capture.onRouteChange = {
            DispatchQueue.main.async {
                MainActor.assumeIsolated { session.routeChanged() }
            }
        }
        // Each setting applies itself when it changes, from the window or a
        // hand edit of settings.json.
        settings.observe { [unowned app] old, new in
            app.apply(from: old, to: new)
            capture.builtInWhileBluetoothPlays = new.microphone.builtInWhileBluetoothPlays
            microphone.isEnabled = new.sound.fadeWhileDictating
        }
        settings.startWatching()
        // Quitting mid-dictation doesn't leave the Mac's sound faded.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil
        ) { _ in fader.restoreNow() }
        // HotkeyMonitor reports health on the main thread.
        monitor.onHealthChange = { [unowned app] health in
            MainActor.assumeIsolated { app.hotkeyHealth = health }
        }

        startWhenModelReady(app: app, transcriber: transcriber, switcher: switcher)
        quitOnInterrupt(monitor)
        Log.info("model: \(model.id) · inject: \(options.injectMode.rawValue) · ^C to quit")
        // Everything else hangs off these two for the app's lifetime.
        withExtendedLifetime((menuBar, session)) {
            NSApplication.shared.run()
        }
    }

    /// Loads the model behind the menu bar icon, so a first launch that
    /// downloads it shows "Loading model…" instead of nothing, then starts
    /// the hotkey, so a press never reaches an unloaded transcriber. A
    /// failed load (an offline first run) retries with backoff rather than
    /// exiting: the login item doesn't relaunch. Choosing another model that
    /// loads ends the wait at once.
    @MainActor
    private static func startWhenModelReady(app: AppModel, transcriber: WhisperKitTranscriber, switcher: ModelSwitcher) {
        app.hotkeyHealth = .modelLoading
        var switchedIn = false
        switcher.onReady = { switchedIn = true }
        Task { @MainActor in
            var retryDelay = 30
            retrying: while true {
                do {
                    try await transcriber.warmUp()
                    break
                } catch {
                    Log.error("couldn't load the model: \(error); retrying in \(retryDelay)s")
                    app.hotkeyHealth = .modelFailed
                    for _ in 0..<retryDelay {
                        if switchedIn { break retrying }
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                    if switchedIn { break }
                    retryDelay = min(retryDelay * 2, 600)
                    app.hotkeyHealth = .modelLoading
                }
            }
            switcher.onReady = nil
            startHotkey(app: app)
        }
    }

    /// Starts the hotkey tap, or, without its grant, waits for one. The
    /// onboarding window asks for it; polling picks it up, so no restart is
    /// needed.
    @MainActor
    private static func startHotkey(app: AppModel) {
        let monitor = app.monitor
        func start() {
            do {
                // HotkeyMonitor delivers events on the main queue.
                try monitor.start { event in
                    MainActor.assumeIsolated { app.session?.handle(event) }
                }
                app.hotkeyHealth = .ok
                Log.info("listening on \(monitor.key.shortName) hold")
            } catch HotkeyMonitor.HotkeyError.shortcutTaken {
                Log.error("couldn't register \(monitor.key.shortName): another app uses it; choose another in Settings")
                app.hotkeyHealth = .shortcutTaken
            } catch {
                Log.error("couldn't start the hotkey tap: \(error)")
                app.hotkeyHealth = .tapDisabled
            }
        }

        if HotkeyAccess.isGranted {
            start()
            return
        }
        Log.info("\(HotkeyAccess.name) not granted; waiting (System Settings → Privacy & Security → \(HotkeyAccess.name) → Quoth)")
        app.hotkeyHealth = .accessibilityMissing
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { timer in
            MainActor.assumeIsolated {
                guard HotkeyAccess.isGranted else { return }
                timer.invalidate()
                Log.info("\(HotkeyAccess.name) granted")
                start()
            }
        }
    }

    /// ^C quits a copy started from a terminal.
    @MainActor
    private static func quitOnInterrupt(_ monitor: HotkeyMonitor) {
        let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigint.setEventHandler {
            Log.info("\nshutting down")
            monitor.stop()
            NSApp.terminate(nil)
        }
        sigint.resume()
        signal(SIGINT, SIG_IGN)
        Self.sigint = sigint
    }

    /// Kept for the app's lifetime; a released source stops delivering.
    @MainActor private static var sigint: DispatchSourceSignal?
}
