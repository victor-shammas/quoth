import Foundation

/// Turns the hotkey's edges into dictation actions (ADR-003).
///
/// The tap sees modifier changes only, so it can't see the C in ⌘C. Two
/// rules keep a shortcut typed on the hotkey from producing text:
/// - A hold shorter than `minimumHold` is a tap, and is discarded.
/// - Another modifier pressed during the hold, or held at its start, makes
///   it a chord: the recording is discarded and the rest of the hold ignored.
///
/// Recording starts on key-down regardless, so pressing costs no latency; a
/// discarded hold just throws its audio away.
///
/// The hands-free lock: a tap, then a second press within
/// `doubleTapWindow`, released before `minimumHold`, locks the recording
/// on. The next press stops it and transcribes, with or without another
/// modifier, so a shortcut typed mid-dictation never throws minutes away.
/// A lock shorter than `minimumLock` was a triple tap and is discarded. A
/// second press held past `minimumHold` is ordinary push-to-talk.
public struct Gesture {
    /// Holds shorter than this are taps or shortcuts, not dictation.
    public static let minimumHold: TimeInterval = 0.3
    /// The longest gap from a tap's release to the next press for the pair
    /// to count as a double tap.
    public static let doubleTapWindow: TimeInterval = 0.4
    /// A lock shorter than this is an accidental triple tap.
    public static let minimumLock: TimeInterval = 1.0

    /// Whether a double tap locks. Off, the gesture is push-to-talk only.
    public var lockEnabled: Bool

    public enum Input: Equatable {
        /// The hotkey went down; `othersHeld` if another modifier already was.
        case hotkeyDown(othersHeld: Bool)
        case hotkeyUp
        /// Another modifier changed while the hotkey was down.
        case otherModifier
    }

    public enum Action: Equatable {
        /// Start recording.
        case start
        /// Stop and transcribe.
        case transcribe
        /// Stop and discard.
        case cancel
        /// The recording just started is locked on: it continues with the
        /// hotkey up until the next press.
        case lock
    }

    private enum Phase: Equatable {
        case idle
        /// Held and recording since this time.
        case holding(since: TimeInterval)
        /// Held and recording since this time, as the second press of a
        /// possible double tap: a quick release locks.
        case secondPress(since: TimeInterval)
        /// Locked on since this time, with the hotkey up.
        case locked(since: TimeInterval)
        /// A tap ended at this time; a press soon after may lock.
        case tapped(at: TimeInterval)
        /// Held, but not dictating (a chord, or a lock's ending press):
        /// wait for the release.
        case ignoring
    }

    private var phase: Phase = .idle

    public init(lockEnabled: Bool = true) {
        self.lockEnabled = lockEnabled
    }

    /// Whether the hotkey is down, as far as the edges so far say.
    public var isHeld: Bool {
        switch phase {
        case .holding, .secondPress, .ignoring: return true
        case .idle, .tapped, .locked: return false
        }
    }

    public var isLocked: Bool {
        if case .locked = phase { return true }
        return false
    }

    /// Feeds one edge, at `time` on a monotonic clock in seconds.
    public mutating func handle(_ input: Input, at time: TimeInterval) -> Action? {
        switch input {
        case .hotkeyDown(let othersHeld): return pressed(at: time, othersHeld: othersHeld)
        case .hotkeyUp: return released(at: time)
        case .otherModifier: return chorded()
        }
    }

    private mutating func pressed(at time: TimeInterval, othersHeld: Bool) -> Action? {
        switch phase {
        case .idle, .tapped:
            if othersHeld {
                phase = .ignoring
                return nil
            }
            if case .tapped(let at) = phase, lockEnabled, time - at <= Self.doubleTapWindow {
                phase = .secondPress(since: time)
            } else {
                phase = .holding(since: time)
            }
            return .start
        case .locked(let since):
            // This press ends the lock and records nothing itself.
            phase = .ignoring
            return time - since < Self.minimumLock ? .cancel : .transcribe
        case .holding, .secondPress, .ignoring:
            // A repeated down edge.
            return nil
        }
    }

    private mutating func released(at time: TimeInterval) -> Action? {
        switch phase {
        case .holding(let since):
            if time - since < Self.minimumHold {
                phase = .tapped(at: time)
                return .cancel
            }
            phase = .idle
            return .transcribe
        case .secondPress(let since):
            if time - since < Self.minimumHold {
                phase = .locked(since: since)
                return .lock
            }
            phase = .idle
            return .transcribe
        case .ignoring:
            phase = .idle
            return nil
        case .idle, .tapped, .locked:
            // An up edge with no down seen.
            return nil
        }
    }

    private mutating func chorded() -> Action? {
        switch phase {
        case .holding, .secondPress:
            phase = .ignoring
            return .cancel
        default:
            return nil
        }
    }

    /// Forgets the current hold, for a switch to another key. A held
    /// recording is discarded, since its key is no longer the hotkey; a
    /// locked one is transcribed, so a settings change never loses one.
    public mutating func reset() -> Action? {
        defer { phase = .idle }
        switch phase {
        case .holding, .secondPress: return .cancel
        case .locked: return .transcribe
        case .idle, .tapped, .ignoring: return nil
        }
    }

    /// Ends a lock early (it ran too long, or the microphone changed),
    /// transcribing what was recorded.
    public mutating func expireLock() -> Action? {
        guard isLocked else { return nil }
        phase = .idle
        return .transcribe
    }

    /// The press just seen started no recording (the microphone failed):
    /// ignore the rest of the hold, so it can't lock or transcribe.
    public mutating func abandonPress() {
        if case .holding = phase { phase = .ignoring }
        if case .secondPress = phase { phase = .ignoring }
    }
}
