import AppKit
import Foundation

/// What the dictation loop needs from the Mac, as `DictationSession` sees it
/// (ADR-007). The real ones are `AudioCapture`, `TextDelivery` and
/// `SystemFocus`; tests pass fakes, so the session runs without a
/// microphone, other apps or Accessibility.

/// The microphone, one recording at a time.
public protocol Microphone: AnyObject {
    /// Starts a recording. Throws when the microphone can't start.
    func start() throws
    /// Stops the recording and returns it at 16 kHz. Throws when the input
    /// route changed during it, unless `keepBeforeRouteChange`, which keeps
    /// what came before the change.
    func finish(keepBeforeRouteChange: Bool) throws -> [Float]
    /// Stops the recording and throws it away.
    func stop()
    /// The recording so far, from `offset` on, for live text.
    func samples(from offset: Int) -> [Float]
    /// The input route changed since the recording started.
    var hasRouteChanged: Bool { get }
    /// For the last finished recording: seconds from the press to its first
    /// sample. Nil when unknown.
    var lastFirstSampleDelay: TimeInterval? { get }
}

extension AudioCapture: Microphone {
    public var lastFirstSampleDelay: TimeInterval? { lastStats?.firstSampleDelay }
}

/// Where transcripts go: the cursor of the app the user is in, or the
/// clipboard.
@MainActor
public protocol TextSink: AnyObject {
    /// Whether text can be inserted at the cursor, rather than only copied.
    var canInsert: Bool { get }
    /// Inserts `text`, checking focus against `focusAtStart`. Throws
    /// `DeliveryError` when it didn't reach the cursor.
    func deliver(_ text: String, focusAtStart: FocusSnapshot?) async throws
    /// Removes the last insertion ("scratch that"). Returns whether it did.
    func scratchLast() -> Bool
    /// Leaves `text` on the clipboard.
    func copyToClipboard(_ text: String)
}

extension TextDelivery: TextSink {}

/// What has keyboard focus.
@MainActor
public protocol FocusProbe {
    func current() -> FocusSnapshot
}

/// The real focus, over `NSWorkspace` and, in the direct edition,
/// Accessibility.
public struct SystemFocus: FocusProbe {
    nonisolated public init() {}

    public func current() -> FocusSnapshot {
        FocusSnapshot.capture()
    }
}
