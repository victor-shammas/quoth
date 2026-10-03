import AppKit
import CoreGraphics
import Foundation
import QuothDomain

/// The dictation key: turns one modifier's presses and releases into
/// dictation events.
///
/// `EventTap` delivers the modifier changes, `HotkeyMatching` says what each
/// means for the key, and `Gesture` decides: short taps and chords are
/// discarded, so a shortcut typed on the hotkey produces no text, and a
/// double tap locks. A lock ends on its own after `lockLimit`.
///
/// Everything runs on the main thread.
public final class HotkeyMonitor {
    public enum Event: Equatable {
        /// Start recording.
        case pressed
        /// Stop recording and transcribe.
        case released
        /// Stop recording and discard it: a short tap, a chord, or a key switch.
        case cancelled
        /// A double tap locked the recording on; it continues with the key up.
        case locked
    }

    public enum HotkeyError: Error { case tapCreateFailed }

    /// The longest a lock runs before it is transcribed on its own, so a
    /// forgotten one doesn't record indefinitely.
    public static let lockLimit: TimeInterval = 10 * 60

    /// The modifier held to dictate; change it with `setKey(_:)`.
    public private(set) var key: HotkeyKey
    /// Called on the main thread when the tap's health changes.
    public var onHealthChange: ((HotkeyHealth) -> Void)? {
        get { tap.onHealthChange }
        set { tap.onHealthChange = newValue }
    }

    private let debug: Bool
    private var gesture: Gesture
    private var onEvent: ((Event) -> Void)?
    private var lockTimer: Timer?
    private lazy var tap = EventTap(
        onModifiers: { [weak self] in self?.modifiersChanged($0) },
        onRecovered: { [weak self] in self?.catchUp() }
    )

    public init(key: HotkeyKey = .fn, lockEnabled: Bool = true, debug: Bool = false) {
        self.key = key
        self.debug = debug
        gesture = Gesture(lockEnabled: lockEnabled)
    }

    public func start(onEvent: @escaping (Event) -> Void) throws {
        self.onEvent = onEvent
        try tap.start()
    }

    public func stop() {
        tap.stop()
        lockTimer?.invalidate()
        lockTimer = nil
        onEvent = nil
    }

    /// Turns the double-tap lock on or off. A recording already locked runs
    /// until the next press.
    public func setLockEnabled(_ enabled: Bool) {
        gesture.lockEnabled = enabled
    }

    /// Switches key without a new tap; the next press of `newKey` records. A
    /// recording held on the old key is discarded, a locked one transcribed.
    public func setKey(_ newKey: HotkeyKey) {
        guard newKey != key else { return }
        let action = gesture.reset()
        key = newKey
        if let action { emit(action) }
    }

    /// Ends a lock now and transcribes it, as a tap of the key would: for the
    /// time limit, a microphone change, Stop Dictation and the Quote Card.
    public func endLock(reason: String) {
        guard let action = gesture.expireLock() else { return }
        Log.info("ending the lock: \(reason)")
        emit(action)
    }

    /// The press just reported started no recording: ignore the rest of its
    /// hold, so it can't lock a recording that isn't running.
    public func abandonPress() {
        gesture.abandonPress()
    }

    // MARK: -

    private func modifiersChanged(_ event: CGEvent) {
        // A modifier's keycode, never a character.
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        if debug {
            Log.info("  [debug] modifier keycode=\(keycode) flags=\(String(event.flags.rawValue, radix: 16))")
        }
        if let input = HotkeyMatching.input(keycode: keycode, flags: event.flags, key: key, held: gesture.isHeld) {
            feed(input)
        }
    }

    /// The tap is back on after an outage: if the key was released while it
    /// was off, catch up on that release.
    private func catchUp() {
        let heldNow = CGEventSource.flagsState(.combinedSessionState).contains(key.flag)
        if HotkeyMatching.missedRelease(wasHeld: gesture.isHeld, heldNow: heldNow) { feed(.hotkeyUp) }
    }

    private func feed(_ input: Gesture.Input) {
        if let action = gesture.handle(input, at: ProcessInfo.processInfo.systemUptime) { emit(action) }
    }

    private func emit(_ action: Gesture.Action) {
        lockTimer?.invalidate()
        lockTimer = nil
        switch action {
        case .start: onEvent?(.pressed)
        case .transcribe: onEvent?(.released)
        case .cancel: onEvent?(.cancelled)
        case .lock:
            startLockTimer()
            onEvent?(.locked)
        }
    }

    private func startLockTimer() {
        let timer = Timer(timeInterval: Self.lockLimit, repeats: false) { [weak self] _ in
            self?.endLock(reason: "reached \(Int(Self.lockLimit / 60)) min")
        }
        RunLoop.main.add(timer, forMode: .common)
        lockTimer = timer
    }
}
