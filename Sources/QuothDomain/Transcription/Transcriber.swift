import Foundation

/// A speech-to-text engine. Called from the main actor; implementations do
/// their work elsewhere (WhisperKitTranscriber is an actor).
///
/// Each engine takes what it can from `TranscriptionContext` and ignores the
/// rest: Whisper conditions on `prompt`; engines with a vocabulary input (for
/// example contextual strings in Apple Speech) take `vocabulary`. Every engine
/// gets the dictionary's replacement pass afterwards regardless.
public protocol Transcriber: Sendable {
    var modelID: String { get }
    func transcribe(_ audio: [Float], context: TranscriptionContext) async throws -> Transcript
}

/// What the transcriber is told about the dictation beyond the audio.
/// Features fill these fields; engines use what they support.
public struct TranscriptionContext: Equatable, Sendable {
    /// Spoken language as an ISO 639-1 code, or nil to let the engine decide
    /// (the Language setting's Automatic).
    public var language: String?
    /// Natural text in `language` that biases the model toward expected
    /// words, such as the dictionary's example sentence, or nil for none.
    /// Never a bare list of terms: Whisper ignores a list.
    public var prompt: String?
    /// Canonical spellings the user expects, for engines that take a word
    /// list. Empty for none. Whisper ignores it and uses `prompt`.
    public var vocabulary: [String]
    /// Example sentences by language code, for an engine that learns the
    /// language only when it hears it: with `language` nil it takes the
    /// sentence for the language it settled on, never one in another
    /// language. Empty for none.
    public var examples: [String: String]
    /// The languages the user speaks, most used first, which Automatic
    /// trusts at any probability. Empty for the Mac's preferred languages.
    public var spokenLanguages: [String]
    /// The text just before this audio in the same dictation (live text's
    /// previous segment), so a segment cut mid-sentence continues it rather
    /// than starting a new one. Nil for a dictation on its own.
    public var previousText: String?
    /// The language `previousText` was decoded in. A segment in another
    /// language doesn't continue it: Whisper reads a prompt in the wrong
    /// language as a cue to translate.
    public var previousLanguage: String?

    public init(
        language: String? = nil,
        prompt: String? = nil,
        vocabulary: [String] = [],
        examples: [String: String] = [:],
        spokenLanguages: [String] = []
    ) {
        self.language = language
        self.prompt = prompt
        self.vocabulary = vocabulary
        self.examples = examples
        self.spokenLanguages = spokenLanguages
    }
}
