import Foundation

/// Turns hotkey edges into dictation actions (ADR-003). Pure, so the rules
/// are tested without an event tap.
///
/// The tap sees modifier changes only, so it cannot see the C in ⌘C. Two
/// rules keep a shortcut typed on the hotkey from producing text:
/// - A hold shorter than `minimumHold` is discarded without transcribing.
/// - A recording is cancelled if another modifier changes while the hotkey
///   is held, and a press while another modifier is already held does not
///   record. Either way the rest of that hold is ignored.
///
/// Recording still starts on key-down, so press latency is unchanged; a
/// discarded hold just throws its audio away.
///
/// Hands-free lock (fork addition): a tap followed within `doubleTapWindow`
/// by a second tap locks the recording on, so a long dictation needs no
/// held key. The next press of the hotkey stops it and transcribes; a press
/// with another modifier held discards it. The first tap is discarded as any
/// short tap is, and the second press records from key-down, so a second
/// press held past `minimumHold` is ordinary push-to-talk and never locks.
struct Gesture {
    /// Holds shorter than this are taps or shortcuts, not dictation.
    static let minimumHold: TimeInterval = 0.3
    /// The longest gap between a tap's release and the next press for the
    /// pair to count as a double tap.
    static let doubleTapWindow: TimeInterval = 0.4

    /// Whether a double tap locks the recording on. When false the gesture
    /// is push-to-talk only, as upstream.
    var lockEnabled: Bool

    enum Input: Equatable {
        /// The hotkey went down. `othersHeld`: another modifier was already
        /// down, so this is a chord.
        case hotkeyDown(othersHeld: Bool)
        /// The hotkey went up.
        case hotkeyUp
        /// Another modifier changed while the hotkey was down.
        case otherModifier
    }

    enum Action: Equatable {
        /// Start recording.
        case start
        /// Stop recording and transcribe.
        case transcribe
        /// Stop recording and discard it.
        case cancel
        /// The recording started by the last `.start` is now locked on: the
        /// hotkey is up and recording continues until the next press.
        case lock
    }

    private enum Phase: Equatable {
        case idle
        /// Recording since this time.
        case recording(since: TimeInterval)
        /// The hotkey is down but this hold is a chord: ignore it until release.
        case ignoring
        /// A short tap was released at this time; a press soon after locks.
        case tapped(at: TimeInterval)
        /// Recording since this time, on the second press of a double tap.
        /// A quick release locks; a long one transcribes as usual.
        case latching(since: TimeInterval)
        /// Locked on: recording with the hotkey up.
        case locked
    }

    private var phase: Phase = .idle

    init(lockEnabled: Bool = true) {
        self.lockEnabled = lockEnabled
    }

    /// Whether the hotkey is down, as far as the edges seen so far say.
    var isHeld: Bool {
        switch phase {
        case .idle, .tapped, .locked: return false
        case .recording, .latching, .ignoring: return true
        }
    }

    /// Whether a recording is locked on.
    var isLocked: Bool { phase == .locked }

    /// Feed one edge at `time` (seconds on a monotonic clock).
    mutating func handle(_ input: Input, at time: TimeInterval) -> Action? {
        switch (phase, input) {
        case (.idle, .hotkeyDown(let othersHeld)), (.tapped, .hotkeyDown(let othersHeld)):
            if othersHeld {
                phase = .ignoring
                return nil
            }
            if case .tapped(let at) = phase, lockEnabled, time - at <= Self.doubleTapWindow {
                phase = .latching(since: time)
            } else {
                phase = .recording(since: time)
            }
            return .start
        case (.recording(let since), .hotkeyUp):
            if time - since < Self.minimumHold {
                phase = .tapped(at: time)
                return .cancel
            }
            phase = .idle
            return .transcribe
        case (.latching(let since), .hotkeyUp):
            if time - since < Self.minimumHold {
                phase = .locked
                return .lock
            }
            phase = .idle
            return .transcribe
        case (.recording, .otherModifier), (.latching, .otherModifier):
            phase = .ignoring
            return .cancel
        case (.locked, .hotkeyDown(let othersHeld)):
            // The press that ends a lock records nothing itself; the rest of
            // its hold is ignored.
            phase = .ignoring
            return othersHeld ? .cancel : .transcribe
        case (.ignoring, .hotkeyUp):
            phase = .idle
            return nil
        default:
            // A repeated down, an up with no down seen, or a modifier change
            // outside a recording.
            return nil
        }
    }

    /// Forget the current hold, for a switch to another key. A recording in
    /// progress, locked or not, is cancelled.
    mutating func reset() -> Action? {
        defer { phase = .idle }
        switch phase {
        case .recording, .latching, .locked: return .cancel
        case .idle, .tapped, .ignoring: return nil
        }
    }

    /// End a lock that ran too long: transcribe what was recorded.
    mutating func expireLock() -> Action? {
        guard phase == .locked else { return nil }
        phase = .idle
        return .transcribe
    }
}
