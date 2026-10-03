import Foundation

/// How a dictation's spoken language is chosen. Pure, so it is tested.
///
/// - A single-language model such as `whisper-base.en` is never told a
///   language and never asked to detect one: it only knows one.
/// - An explicit Language setting is used as given, with detection off.
/// - Automatic chooses among the languages the user speaks (the Languages
///   setting, or the Mac's preferred languages until it is set), and only
///   among them: `LanguageDetector` lets no other language compete. Whisper
///   confuses close languages on short clips (Spanish heard as Italian or
///   Portuguese: Serbian heard as Spanish), and a wrong language comes
///   back as a translation. With one language there is nothing to detect.
public enum SpokenLanguage {
    /// What to do before decoding.
    public enum Plan: Equatable, Sendable {
        /// Pass no language: the model has only one.
        case none
        /// Decode in this language, detection off.
        case fixed(String)
        /// Detect which of these languages is spoken. Empty when none of the
        /// user's languages is one the model knows: then every language
        /// competes, as in WhisperKit's own detection.
        case detect(among: [String])
    }

    /// The plan for `model` with the Language setting `setting` (an ISO 639-1
    /// code, or nil for Automatic) and the languages the user speaks,
    /// `spoken`. A code the model does not support, such as a typo in a hand
    /// edit, counts as Automatic.
    public static func plan(setting: String?, spoken: [String], model: TranscriptionModel) -> Plan {
        guard model.isMultilingual else { return .none }
        let supported = model.supportedLanguages
        if let code = setting.map(whisperCode), supported.contains(code) {
            return .fixed(code)
        }
        var seen = Set<String>()
        let candidates = spoken.map(whisperCode).filter { supported.contains($0) && seen.insert($0).inserted }
        if candidates.count == 1 { return .fixed(candidates[0]) }
        return .detect(among: candidates)
    }

    /// Softmax over `scores` (a logit per language): each language's
    /// probability among these languages only, highest first.
    public static func probabilities(_ scores: [(String, Float)]) -> [(code: String, probability: Float)] {
        guard let top = scores.map(\.1).max() else { return [] }
        let weights = scores.map { ($0.0, exp($0.1 - top)) }
        let total = weights.reduce(0) { $0 + $1.1 }
        return weights
            .map { (code: $0.0, probability: $0.1 / total) }
            .sorted { $0.probability > $1.probability }
    }

    /// `identifiers` (as in `Locale.preferredLanguages`: "en-US", "pt-BR",
    /// "zh-Hans-CN") reduced to ISO 639-1 codes, in order, without repeats.
    public static func preferredCodes(_ identifiers: [String] = Locale.preferredLanguages) -> [String] {
        var seen = Set<String>()
        return identifiers.compactMap { id -> String? in
            let language = Locale.Language(identifier: id)
            let code = language.languageCode?.identifier(.alpha2) ?? language.languageCode?.identifier
            return code.map(whisperCode)
        }
        .filter { seen.insert($0).inserted }
    }

    /// Where Apple's language codes and Whisper's differ for the same
    /// language: Norwegian Bokmål is `nb` to macOS and `no` to Whisper,
    /// Filipino `fil` and `tl`, Javanese `jv` and `jw`, and the old Hebrew
    /// and Indonesian codes. Without this, a Mac's language would be
    /// silently dropped from the ones Automatic chooses among.
    public static let appleToWhisper = ["nb": "no", "fil": "tl", "jv": "jw", "iw": "he", "in": "id"]

    /// `code` as Whisper knows it, lowercased.
    public static func whisperCode(_ code: String) -> String {
        let code = code.lowercased()
        return appleToWhisper[code] ?? code
    }

    /// Every language Whisper's multilingual models know, as codes.
    public static let whisperLanguages: Set<String> = WhisperLanguages.codes

    /// `code`'s name in the user's language, for the Language picker:
    /// "Portuguese", "Português". Falls back to Whisper's English name.
    public static func displayName(_ code: String, locale: Locale = .current) -> String {
        if let name = locale.localizedString(forLanguageCode: code), name != code {
            return name.prefix(1).uppercased() + name.dropFirst()
        }
        // Some codes have several names ("flemish", "dutch"); pick one stably.
        let whisperName = WhisperLanguages.names.filter { $0.value == code }.map(\.key).min() ?? code
        return whisperName.capitalized
    }
}

extension TranscriptionModel {
    /// True if the model hears more than one language. Registry entries say
    /// so with `languages: ["multi"]`.
    public var isMultilingual: Bool {
        languages.contains("multi") || languages.count > 1
    }

    /// The language a model will hear, when that is certain without a
    /// setting: a single-language model such as `whisper-base.en`. Nil for
    /// multilingual models, whose language comes from the Language setting or
    /// detection: an example sentence in the wrong language drags the decoder
    /// into it.
    public var onlyLanguage: String? {
        guard languages.count == 1, let only = languages.first, only != "multi" else { return nil }
        return only
    }

    /// The language codes the model can be told to expect.
    public var supportedLanguages: Set<String> {
        languages.contains("multi") ? SpokenLanguage.whisperLanguages : Set(languages)
    }
}
