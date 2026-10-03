import Foundation
import QuothDomain
import WhisperKit

/// What goes into Whisper besides the audio, and what comes out besides
/// the words.
public enum WhisperText {
    /// The prompt for a segment of a dictation: the dictionary's sentence,
    /// then the end of the previous segment, which Whisper conditions on to
    /// carry a sentence on. Whisper reads at most 224 prompt tokens; about
    /// 200 characters of context is plenty.
    public static func prompt(_ prompt: String?, continuing previous: String?) -> String? {
        guard let previous = previous?.trimmingCharacters(in: .whitespacesAndNewlines), !previous.isEmpty else {
            return prompt
        }
        let tail = String(previous.suffix(200))
        guard let prompt, !prompt.isEmpty else { return tail }
        return prompt + " " + tail
    }

    /// `prompt` as Whisper prompt tokens, or nil for none. Whisper reads them
    /// as the text spoken just before the audio. Special tokens are dropped:
    /// the decoder builds its own control sequence around the prompt, and a
    /// stray one there throws it out of step.
    public static func tokens(for prompt: String?, tokenizer: WhisperTokenizer?) -> [Int]? {
        guard let tokenizer,
              let text = prompt?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
        else { return nil }
        // With a leading space, as the text would appear mid-transcript.
        let tokens = tokenizer.encode(text: " " + text).filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        return tokens.isEmpty ? nil : tokens
    }

    /// The example sentence in `examples` for `language`, matched as the
    /// dictionary matches it.
    public static func example(in examples: [String: String], for language: String?) -> String? {
        examples.isEmpty ? nil : UserDictionary(examples: examples).example(for: language)
    }

    /// What Whisper writes for sounds rather than speech: [BLANK_AUDIO],
    /// [MUSIC], (silence), <|nospeech|>, *background noise*.
    private static let nonSpeech = [#"\[[^\]]*\]"#, #"\([^)]*\)"#, #"<\|[^|]*\|>"#, #"\*[^*]*\*"#]

    /// `text` without its non-speech markers, with runs of whitespace as one
    /// space. Whisper writes the markers literally for silence and noise,
    /// and they shouldn't be typed.
    public static func clean(_ text: String) -> String {
        let spoken = nonSpeech.reduce(text) { $0.replacingOccurrences(of: $1, with: " ", options: .regularExpression) }
        return spoken.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension TranscriberTimings {
    /// WhisperKit's per-stage timings for one transcription, folded into
    /// Quoth's stages. Whatever WhisperKit doesn't attribute to
    /// preprocessing, the encoder or the decoder is postprocessing, so the
    /// stages add up to `total`.
    public init(
        whisperKit results: [TranscriptionTimings],
        audioSeconds: TimeInterval,
        preprocessing ownPreprocessing: TimeInterval,
        languageDetection: TimeInterval = 0,
        total: TimeInterval
    ) {
        self.init(audioSeconds: audioSeconds, preprocessing: ownPreprocessing, languageDetection: languageDetection, total: total)
        for t in results {
            let stagePreprocessing = t.audioProcessing + t.logmels
            preprocessing += stagePreprocessing
            encoder += t.encoding
            decoder += max(0, t.fullPipeline - stagePreprocessing - t.encoding - t.decodingWindowing)
            windows += Int(t.totalEncodingRuns)
            tokens += Int(t.totalDecodingLoops)
            // WhisperKit records the index of the last failed attempt, so one
            // fallback reads 0; any fallback time means at least one happened.
            if t.decodingFallback > 0 { fallbacks += Int(t.totalDecodingFallbacks) + 1 }
        }
        postprocessing = max(0, total - preprocessing - self.languageDetection - encoder - decoder)
    }
}
