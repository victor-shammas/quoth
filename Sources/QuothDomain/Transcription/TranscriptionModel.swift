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
    /// How it trades speed for accuracy, in a few words, measured with
    /// `quoth-bench`: "Fastest", "Most accurate, slowest".
    public let tradeOff: String

    public init(id: String, displayName: String, variant: String, sizeMB: Int, hears: Hearing, tradeOff: String) {
        self.id = id
        self.displayName = displayName
        self.variant = variant
        self.sizeMB = sizeMB
        self.hears = hears
        self.tradeOff = tradeOff
    }

    /// Without "Whisper", which every model is: "Base (English)".
    public var name: String { displayName.replacingOccurrences(of: "Whisper ", with: "") }

    /// Inside a menu group that already says English: "Base".
    public var shortName: String { name.replacingOccurrences(of: " (English)", with: "") }

    /// "Fastest · English only · 145 MB".
    public var summary: String {
        let size = sizeMB >= 1000 ? String(format: "%.1f GB", Double(sizeMB) / 1000) : "\(sizeMB) MB"
        return [tradeOff, isMultilingual ? "Multilingual" : "English only", size].joined(separator: " · ")
    }

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
