import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import QuothDomain

/// A listen-only tap on modifier changes, kept alive.
///
/// It sees `flagsChanged` only, never a key-down: wider, every keystroke,
/// password fields included, would pass through Quoth, and the extra work
/// makes macOS more likely to disable the tap for being slow. The hotkey is
/// a modifier, so modifier changes are all it needs.
///
/// macOS disables a tap that answers slowly, or on some user input. This
/// one re-enables itself, backing off when that doesn't stick
/// (`TapRecovery`), checks itself on a watchdog in case a disable was never
/// reported, and says how it's doing through `onHealthChange`.
///
/// Everything runs on the main thread.
final class EventTap {
    /// How often the watchdog checks the tap is still on.
    static let watchdogInterval: TimeInterval = 5

    var onHealthChange: ((HotkeyHealth) -> Void)?
    private(set) var health: HotkeyHealth = .ok {
        didSet { if health != oldValue { onHealthChange?(health) } }
    }

    fileprivate let onModifiers: (CGEvent) -> Void
    /// After the tap comes back on, for catching up on what it missed.
    private let onRecovered: () -> Void
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var watchdog: Timer?
    private var recovery = TapRecovery()
    private var retry: DispatchWorkItem?

    init(onModifiers: @escaping (CGEvent) -> Void, onRecovered: @escaping () -> Void) {
        self.onModifiers = onModifiers
        self.onRecovered = onRecovered
    }

    func start() throws {
        // The caller waits for the grant first; this is a guard, not a request.
        guard HotkeyAccess.isGranted,
              let tap = CGEvent.tapCreate(
                  // The session level, where an app with the grant may tap.
                  tap: .cgSessionEventTap,
                  place: .headInsertEventTap,
                  options: .listenOnly,
                  eventsOfInterest: 1 << CGEventType.flagsChanged.rawValue,
                  callback: tapCallback,
                  userInfo: Unmanaged.passUnretained(self).toOpaque()
              )
        else { throw HotkeyMonitor.HotkeyError.tapCreateFailed }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source

        let watchdog = Timer(timeInterval: Self.watchdogInterval, repeats: true) { [weak self] _ in self?.check() }
        RunLoop.main.add(watchdog, forMode: .common)
        self.watchdog = watchdog
    }

    func stop() {
        watchdog?.invalidate()
        watchdog = nil
        retry?.cancel()
        retry = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    // MARK: Staying on

    fileprivate func disabled(_ type: CGEventType) {
        noteDisabled(type == .tapDisabledByTimeout ? "timeout" : "user input")
    }

    /// The tap is off: re-enable it now, or after a wait if earlier attempts
    /// didn't stick. A retry already waiting covers any further reports.
    private func noteDisabled(_ reason: String) {
        guard tap != nil, retry == nil else { return }
        let delay = recovery.disabled(at: Date())
        if delay == 0 { reenable(reason) } else { scheduleRetry(after: delay, reason) }
    }

    private func reenable(_ reason: String) {
        retry = nil
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        guard CGEvent.tapIsEnabled(tap: tap) else {
            return scheduleRetry(after: recovery.enableFailed(), reason)
        }
        recovery.enabled(at: Date())
        Log.info("hotkey tap disabled (\(reason)); re-enabled")
        health = .ok
        onRecovered()
    }

    private func scheduleRetry(after delay: TimeInterval, _ reason: String) {
        let secureInput = IsSecureEventInputEnabled()
        health = .degraded(secureInput: secureInput)
        Log.warning("hotkey tap disabled (\(reason)\(secureInput ? ", secure input active" : "")); retrying in \(Int(delay))s")
        let retry = DispatchWorkItem { [weak self] in self?.reenable(reason) }
        self.retry = retry
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: retry)
    }

    /// Catches a disable that was never reported.
    private func check() {
        guard let tap, retry == nil, !CGEvent.tapIsEnabled(tap: tap) else { return }
        noteDisabled("watchdog")
    }
}

/// Returns at once and leaves the work for the main run loop's next turn: a
/// slow callback is what gets a tap disabled for timing out.
private func tapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    let unchanged = Unmanaged.passUnretained(event)
    guard let userInfo else { return unchanged }
    let tap = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        DispatchQueue.main.async { tap.disabled(type) }
    case .flagsChanged:
        guard let copy = event.copy() else { break }
        DispatchQueue.main.async { tap.onModifiers(copy) }
    default:
        break
    }
    return unchanged
}
