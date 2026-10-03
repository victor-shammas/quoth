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
        if let code = setting.map(WhisperLanguages.code), supported.contains(code) {
            return .fixed(code)
        }
        let candidates = spoken.map(WhisperLanguages.code).filter(supported.contains).uniqued()
        return candidates.count == 1 ? .fixed(candidates[0]) : .detect(among: candidates)
    }

    /// How sure detection must be to switch away from the language the
    /// previous part of a dictation was in.
    public static let switchConfidence: Float = 0.75

    /// The language to decode in, from detection's ranking (highest first)
    /// and the language the previous part of the same dictation was decoded
    /// in, if any. A confident switch is taken, so a bilingual speaker's next
    /// sentence is heard in its own language; an unsure one keeps the
    /// previous language, so a short or ambiguous segment doesn't flip it.
    public static func choose(_ ranked: [(code: String, probability: Float)], previous: String?) -> String? {
        guard let top = ranked.first else { return previous }
        guard let previous, top.code != previous, ranked.contains(where: { $0.code == previous }) else { return top.code }
        return top.probability >= switchConfidence ? top.code : previous
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
        identifiers.compactMap { id -> String? in
            let language = Locale.Language(identifier: id)
            let code = language.languageCode?.identifier(.alpha2) ?? language.languageCode?.identifier
            return code.map(WhisperLanguages.code)
        }
        .uniqued()
    }

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
