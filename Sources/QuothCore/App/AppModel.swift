import AppKit
import Observation
import QuothDomain
import QuothPlatform

/// What Quoth shows and what the user can ask of it (ADR-007).
///
/// The menu bar and the windows read the state here and call the intents
/// below; nothing else reaches into them. Lasting state lives here. Moments
/// (the pill's messages and level, the Quote Card's status, the latency
/// log) stay `DictationObserver`s of the session, because they are events,
/// not state.
@MainActor
@Observable
final class AppModel {
    /// What the dictation loop is doing, as the menu bar shows it.
    enum Activity: Equatable {
        case idle
        case recording
        case locked
        case transcribing
    }

    private(set) var activity: Activity = .idle
    /// The key the menu tells the user to hold.
    private(set) var hotkey: HotkeyKey
    /// Whether the hotkey works, and if not, why.
    var hotkeyHealth: HotkeyHealth = .modelLoading
    /// A model downloading or loading behind the one in use, or nil.
    var modelLoad: ModelLoad?
    /// The model transcribing now, which differs from the one chosen in
    /// Settings while that one loads. Neither may be deleted.
    var activeModelID: String
    /// A grant the onboarding window asks for is missing.
    var setupNeeded = false
    /// Whether Copy and Fix Last Dictation have something to work on.
    private(set) var hasLastDictation = false

    // MARK: Collaborators, set once by `Assembly`

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let dictionary: DictionaryStore
    @ObservationIgnored let monitor: HotkeyMonitor
    @ObservationIgnored let delivery: TextDelivery
    @ObservationIgnored let overlay: RecordingOverlay
    @ObservationIgnored let card: QuoteCard
    @ObservationIgnored let switcher: ModelSwitcher
    @ObservationIgnored private lazy var settingsWindow = SettingsWindow(store: settings, dictionary: dictionary, app: self)
    @ObservationIgnored lazy var onboarding = OnboardingWindow(store: settings, app: self)
    @ObservationIgnored private let fixWindow: FixDictationWindow
    @ObservationIgnored private let lastDictation = LastDictation()
    /// Set once the session exists, which needs this model for its context.
    @ObservationIgnored weak var session: DictationSession?

    init(
        settings: SettingsStore,
        dictionary: DictionaryStore,
        monitor: HotkeyMonitor,
        delivery: TextDelivery,
        overlay: RecordingOverlay,
        card: QuoteCard,
        switcher: ModelSwitcher
    ) {
        self.settings = settings
        self.dictionary = dictionary
        self.monitor = monitor
        self.delivery = delivery
        self.overlay = overlay
        self.card = card
        self.switcher = switcher
        self.hotkey = monitor.key
        self.activeModelID = switcher.model.id
        self.fixWindow = FixDictationWindow(dictionary: dictionary)
        lastDictation.onChange = { [weak self] available in
            guard let self else { return }
            hasLastDictation = available
            if !available { fixWindow.forget() }
        }
    }

    // MARK: What the menu shows

    /// The menu's first line.
    var statusText: String { Self.statusText(activity, hotkey: hotkey, health: hotkeyHealth) }

    /// The menu's first line for this state. A hotkey that isn't working
    /// replaces the idle line, so the menu never claims fn works when it
    /// doesn't.
    nonisolated static func statusText(_ activity: Activity, hotkey: HotkeyKey, health: HotkeyHealth) -> String {
        switch activity {
        case .idle: return health.statusText ?? "Ready — hold \(hotkey.shortName) to dictate"
        case .recording: return "Recording…"
        case .locked: return "Locked — tap \(hotkey.shortName) to stop"
        case .transcribing: return "Transcribing…"
        }
    }

    /// The menu bar icon.
    var glyph: QuoteGlyph.Style {
        switch activity {
        case .idle: return .idle
        case .recording: return .recording
        case .locked: return .locked
        case .transcribing: return .transcribing
        }
    }

    // MARK: Intents

    func openSettings() {
        settingsWindow.show()
    }

    func finishSetup() {
        onboarding.show()
    }

    func newQuoteCard() {
        card.open()
    }

    func copyLastDictation() {
        lastDictation.copy()
    }

    /// From Settings › Dictionary.
    func fixLastDictation() {
        fixWindow.show(text: lastDictation.text)
    }

    /// Ends a locked recording, for when the hotkey can't (secure input).
    func stopDictation() {
        monitor.endLock(reason: "stopped from the menu")
    }

    func quit() {
        NSApp.terminate(nil)
    }

    /// Keeps a finished dictation for Copy and Fix Last Dictation. The
    /// session never calls this for a password field.
    func remember(_ text: String) {
        lastDictation.remember(text)
    }

    // MARK: Settings

    /// What the transcriber is told about each dictation, read at each
    /// release, so a Language change applies at the next press.
    func transcriptionContext() -> TranscriptionContext {
        let current = settings.current
        var context = DictionaryContext(
            store: dictionary,
            language: DictionaryContext.language(of: switcher.model, setting: current.language.code),
            examples: current.dictionary.examples
        ).context()
        context.spokenLanguages = current.language.spoken ?? []
        return context
    }

    /// Applies a settings change, from the window or a hand edit of
    /// settings.json.
    func apply(from old: Settings, to new: Settings) {
        if old.hotkey.doubleTapLock != new.hotkey.doubleTapLock {
            monitor.setLockEnabled(new.hotkey.doubleTapLock)
            Log.info("double-tap lock: \(new.hotkey.doubleTapLock ? "on" : "off")")
        }
        if old.hotkey.liveText != new.hotkey.liveText {
            session?.liveText = new.hotkey.liveText
            Log.info("live text: \(new.hotkey.liveText ? "on" : "off"); applies from the next lock")
        }
        if old.hotkey.key != new.hotkey.key {
            // The tap stays; it matches the new key from the next event.
            monitor.setKey(new.hotkey.key)
            hotkey = new.hotkey.key
            Log.info("hotkey: \(new.hotkey.key.rawValue); hold \(new.hotkey.key.shortName) to dictate")
        }
        if old.model != new.model {
            switcher.select(new.model.id)
        }
        if old.sound != new.sound {
            // Read at each press by FadingMicrophone; Assembly passes it on.
            Log.info("fade out sound while dictating: \(new.sound.fadeWhileDictating ? "on" : "off"); applies at next press")
        }
        if old.language != new.language {
            // Read per dictation by transcriptionContext.
            Log.info("language: \(new.language.code ?? "automatic"); applies at next press")
        }
    }

    /// Whether Settings sends hands-free dictation to the Quote Card.
    var lockOpensCard: Bool { settings.current.hotkey.lockTarget == .card }
}

// MARK: - The Quote Card's requests

extension AppModel: QuoteCardHost {
    var isDictating: Bool { (session?.state ?? .idle) != .idle }

    func insertFromCard(_ text: String) {
        lastDictation.remember(text)
        Task {
            if await !delivery.insertNow(text) {
                overlay.showMessage(DeliveryError.copied.userMessage)
            }
        }
    }

    func copyFromCard(_ text: String) {
        SystemPasteboard(.general).write(text, markers: PasteboardSession.concealedMarkers)
        overlay.showMessage("Copied")
    }

    func rememberFromCard(_ text: String) {
        lastDictation.remember(text)
    }

    func endLockForCard() {
        monitor.endLock(reason: "the Quote Card")
    }
}

// MARK: - Following the loop

extension AppModel: DictationObserver {
    func dictationStarted() { activity = .recording }
    func dictationLocked() { activity = .locked }
    func dictationTranscribing() { activity = .transcribing }
    func dictationFinished(_ result: DictationResult) { activity = .idle }
    func dictationFailed(_ error: Error) { activity = .idle }
}
