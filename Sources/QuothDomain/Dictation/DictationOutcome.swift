import Foundation

/// Counts and timings for one delivered dictation. Never the text.
public struct DictationResult: Equatable, Sendable {
    /// Seconds of audio captured.
    public var captureDuration: TimeInterval
    /// Seconds the transcriber took.
    public var transcriptionTime: TimeInterval
    /// Characters delivered, after every `TranscriptProcessor`.
    public var charCount: Int
    /// Seconds to stop the capture engine and collect its samples.
    public var captureStop: TimeInterval = 0
    /// The transcriber's own breakdown, when the engine reports one.
    public var transcriber: TranscriberTimings?
    /// Seconds in the `TranscriptProcessor`s.
    public var processing: TimeInterval = 0
    /// Seconds to deliver the text to the cursor.
    public var delivery: TimeInterval = 0
    /// Seconds from the hotkey release to the text being delivered.
    public var releaseToText: TimeInterval = 0
    /// Seconds from the hotkey press to the capture time of the first
    /// recorded sample: speech in that gap is lost. Nil if unknown.
    public var pressToFirstSample: TimeInterval?

    public init(
        captureDuration: TimeInterval,
        transcriptionTime: TimeInterval,
        charCount: Int,
        captureStop: TimeInterval = 0,
        transcriber: TranscriberTimings? = nil,
        processing: TimeInterval = 0,
        delivery: TimeInterval = 0,
        releaseToText: TimeInterval = 0,
        pressToFirstSample: TimeInterval? = nil
    ) {
        self.captureDuration = captureDuration
        self.transcriptionTime = transcriptionTime
        self.charCount = charCount
        self.captureStop = captureStop
        self.transcriber = transcriber
        self.processing = processing
        self.delivery = delivery
        self.releaseToText = releaseToText
        self.pressToFirstSample = pressToFirstSample
    }
}

public enum DictationError: Error {
    /// The hotkey was released with no audio captured.
    case noAudio
    /// The recording was discarded: a short tap, a chord, or a hotkey switch.
    case cancelled
}

/// An error with a short message the user should see, for example in the
/// overlay. Anything else reaching `dictationFailed` is only logged.
public protocol UserFacingError: Error {
    /// One line, actionable, never containing transcript text.
    var userMessage: String { get }
}

/// A transcript that was not inserted at the cursor, with the line the
/// overlay shows.
public enum DeliveryError: UserFacingError, Equatable {
    /// A password field had focus at start or at delivery. Nothing was typed
    /// or copied.
    case secureField
    /// Focus moved during the dictation. The transcript is on the clipboard.
    case focusChanged
    /// This build can't paste at the cursor (the App Store build without its
    /// grant). The transcript is on the clipboard.
    case copied
    /// The paste went unread: the app in front had nowhere to put it. The
    /// transcript is on the clipboard.
    case notPasted

    /// Whether the refused text is left on the clipboard, so a locked
    /// recording holds its later segments for it too.
    public var holdsText: Bool { self == .focusChanged || self == .notPasted }

    public var userMessage: String {
        switch self {
        case .secureField: return "password field, transcript discarded"
        case .focusChanged: return "focus changed, transcript copied"
        case .copied: return "Copied — press ⌘V to paste"
        case .notPasted: return "couldn't paste here, transcript copied"
        }
    }
}

/// A live-text problem shown while the lock keeps recording.
public enum LiveTextNotice: UserFacingError, Equatable {
    case segmentFailed

    public var userMessage: String {
        switch self {
        case .segmentFailed: return "Part of this dictation couldn't be transcribed"
        }
    }
}
