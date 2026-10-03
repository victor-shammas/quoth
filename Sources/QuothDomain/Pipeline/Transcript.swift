/// The value that flows from the transcriber through each
/// `TranscriptProcessor` to delivery.
///
/// Holds the user's words. Never log it, write it to disk, or keep it after
/// delivery; observers get counts and timings (`DictationResult`) instead.
public struct Transcript: Equatable, Sendable {
    public var text: String
    /// Where the transcriber spent its time, when the engine reports it.
    /// Processors need not carry it on: the controller reads it from the
    /// transcriber's output.
    public var timings: TranscriberTimings?
    /// "scratch that" opened this dictation: delivery removes the previous
    /// one before inserting this (`VoiceCommands`).
    public var scratchesPrevious = false

    public init(text: String, timings: TranscriberTimings? = nil) {
        self.text = text
        self.timings = timings
    }
}
