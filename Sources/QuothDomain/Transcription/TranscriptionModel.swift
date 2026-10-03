import Foundation

/// A speech model Quoth can download and run.
public struct TranscriptionModel: Equatable, Sendable {
    /// What a model can hear.
    public enum Hearing: Equatable, Sendable {
        /// One language, as an ISO 639-1 code, such as `whisper-base.en`.
        case only(String)
        /// Whisper's 99 languages.
        case multilingual
    }

    /// The id in `settings.json`, such as `whisper-large-v3-turbo`.
    public let id: String
    public let displayName: String
    /// WhisperKit's name for it: a folder of `argmaxinc/whisperkit-coreml`.
    public let variant: String
    /// Megabytes to download.
    public let sizeMB: Int
    public let hears: Hearing

    public var isMultilingual: Bool { hears == .multilingual }

    /// The one language the model hears, or nil for a multilingual model,
    /// whose language comes from the Language setting or detection.
    public var onlyLanguage: String? {
        if case .only(let code) = hears { return code }
        return nil
    }

    /// The language codes the model can be told to expect.
    public var supportedLanguages: Set<String> {
        switch hears {
        case .only(let code): return [code]
        case .multilingual: return WhisperLanguages.codes
        }
    }
}
