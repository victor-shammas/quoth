import Foundation

/// Where one transcription spent its time, as the engine reports it. Seconds,
/// counts, and the language code; never text.
///
/// The stages add up to `total`: whatever the engine does not attribute to
/// preprocessing, language detection, the encoder or the decoder is
/// `postprocessing`.
public struct TranscriberTimings: Equatable, Sendable {
    /// No time spent, for a transcription the engine did not time.
    public static let zero = TranscriberTimings()

    /// Seconds of audio handed to the model, after any trimming.
    public var audioSeconds: TimeInterval = 0
    /// Silence trimming, padding the window, and the log-mel spectrogram.
    public var preprocessing: TimeInterval = 0
    /// Detecting the spoken language before decoding (Automatic): its
    /// own mel spectrogram and encoder pass, and one decoder step.
    public var languageDetection: TimeInterval = 0
    /// The audio encoder, over every 30 s window.
    public var encoder: TimeInterval = 0
    /// Decoder setup, the prompt, the token loop, and any temperature fallbacks.
    public var decoder: TimeInterval = 0
    /// Segmenting, detokenizing and cleaning up the text.
    public var postprocessing: TimeInterval = 0
    /// The whole `transcribe` call, wall clock.
    public var total: TimeInterval = 0
    /// The language decoded in, as a code, or nil when unknown.
    public var language: String?
    /// 30 s windows encoded.
    public var windows = 0
    /// Decoder steps, prompt included.
    public var tokens = 0
    /// Temperature fallbacks: decodes thrown away and retried.
    public var fallbacks = 0

    public init(
        audioSeconds: TimeInterval = 0,
        preprocessing: TimeInterval = 0,
        languageDetection: TimeInterval = 0,
        encoder: TimeInterval = 0,
        decoder: TimeInterval = 0,
        postprocessing: TimeInterval = 0,
        total: TimeInterval = 0,
        language: String? = nil,
        windows: Int = 0,
        tokens: Int = 0,
        fallbacks: Int = 0
    ) {
        self.audioSeconds = audioSeconds
        self.preprocessing = preprocessing
        self.languageDetection = languageDetection
        self.encoder = encoder
        self.decoder = decoder
        self.postprocessing = postprocessing
        self.total = total
        self.language = language
        self.windows = windows
        self.tokens = tokens
        self.fallbacks = fallbacks
    }
}
