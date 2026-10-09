import Foundation
import QuothDomain

/// Follows the dictation loop: the overlay, the menu bar, and later stats.
///
/// `DictationSession` calls these on the main actor, in the order the
/// observers were registered. Every method has an empty default, so an
/// observer implements only what it needs. New behaviour that reacts to a
/// dictation is an observer, not a branch in the session.
@MainActor
protocol DictationObserver: AnyObject {
    /// Recording started.
    func dictationStarted()
    /// What the recording that just started records from; right after
    /// `dictationStarted`.
    func dictationInput(_ input: RecordingInput)
    /// The recording was locked on with a double tap and continues hands-free.
    func dictationLocked()
    /// A problem worth showing while recording continues, such as a live
    /// segment that failed. The dictation goes on.
    func dictationNotice(_ error: Error)
    /// The hotkey was released; the capture is being transcribed.
    func dictationTranscribing()
    /// The transcript was delivered.
    func dictationFinished(_ result: DictationResult)
    /// Nothing reached the cursor: capture failed (`CaptureError`), no audio
    /// (`DictationError.noAudio`), the transcriber threw, or delivery was
    /// refused (`DeliveryError`).
    func dictationFailed(_ error: Error)
}

extension DictationObserver {
    func dictationStarted() {}
    func dictationInput(_ input: RecordingInput) {}
    func dictationLocked() {}
    func dictationNotice(_ error: Error) {}
    func dictationTranscribing() {}
    func dictationFinished(_ result: DictationResult) {}
    func dictationFailed(_ error: Error) {}
}

