import Foundation

/// The languages Whisper's multilingual models know: each name Whisper
/// accepts, with its code. Several names share a code ("castilian", "spanish").
/// Fixed by the model's tokenizer; `SpokenLanguageTests` checks it against
/// WhisperKit's copy.
public enum WhisperLanguages {
    public static let names: [String: String] = [
        "english": "en",
        "chinese": "zh",
        "german": "de",
        "spanish": "es",
        "russian": "ru",
        "korean": "ko",
        "french": "fr",
        "japanese": "ja",
        "portuguese": "pt",
        "turkish": "tr",
        "polish": "pl",
        "catalan": "ca",
        "dutch": "nl",
        "arabic": "ar",
        "swedish": "sv",
        "italian": "it",
        "indonesian": "id",
        "hindi": "hi",
        "finnish": "fi",
        "vietnamese": "vi",
        "hebrew": "he",
        "ukrainian": "uk",
        "greek": "el",
        "malay": "ms",
        "czech": "cs",
        "romanian": "ro",
        "danish": "da",
        "hungarian": "hu",
        "tamil": "ta",
        "norwegian": "no",
        "thai": "th",
        "urdu": "ur",
        "croatian": "hr",
        "bulgarian": "bg",
        "lithuanian": "lt",
        "latin": "la",
        "maori": "mi",
        "malayalam": "ml",
        "welsh": "cy",
        "slovak": "sk",
        "telugu": "te",
        "persian": "fa",
        "latvian": "lv",
        "bengali": "bn",
        "serbian": "sr",
        "azerbaijani": "az",
        "slovenian": "sl",
        "kannada": "kn",
        "estonian": "et",
        "macedonian": "mk",
        "breton": "br",
        "basque": "eu",
        "icelandic": "is",
        "armenian": "hy",
        "nepali": "ne",
        "mongolian": "mn",
        "bosnian": "bs",
        "kazakh": "kk",
        "albanian": "sq",
        "swahili": "sw",
        "galician": "gl",
        "marathi": "mr",
        "punjabi": "pa",
        "sinhala": "si",
        "khmer": "km",
        "shona": "sn",
        "yoruba": "yo",
        "somali": "so",
        "afrikaans": "af",
        "occitan": "oc",
        "georgian": "ka",
        "belarusian": "be",
        "tajik": "tg",
        "sindhi": "sd",
        "gujarati": "gu",
        "amharic": "am",
        "yiddish": "yi",
        "lao": "lo",
        "uzbek": "uz",
        "faroese": "fo",
        "haitian creole": "ht",
        "pashto": "ps",
        "turkmen": "tk",
        "nynorsk": "nn",
        "maltese": "mt",
        "sanskrit": "sa",
        "luxembourgish": "lb",
        "myanmar": "my",
        "tibetan": "bo",
        "tagalog": "tl",
        "malagasy": "mg",
        "assamese": "as",
        "tatar": "tt",
        "hawaiian": "haw",
        "lingala": "ln",
        "hausa": "ha",
        "bashkir": "ba",
        "javanese": "jw",
        "sundanese": "su",
        "cantonese": "yue",
        "burmese": "my",
        "valencian": "ca",
        "flemish": "nl",
        "haitian": "ht",
        "letzeburgesch": "lb",
        "pushto": "ps",
        "panjabi": "pa",
        "moldavian": "ro",
        "moldovan": "ro",
        "sinhalese": "si",
        "castilian": "es",
        "mandarin": "zh",
    ]

    public static let codes: Set<String> = Set(names.values)

    /// `code` as Whisper knows it, lowercased. Apple and Whisper differ for
    /// a few languages: Norwegian Bokmål is `nb` to macOS and `no` to
    /// Whisper, Filipino `fil` and `tl`, Javanese `jv` and `jw`, and the old
    /// Hebrew and Indonesian codes. Without this, a Mac's language would drop
    /// silently out of the ones Automatic chooses among.
    public static func code(_ code: String) -> String {
        let code = code.lowercased()
        return fromApple[code] ?? code
    }

    static let fromApple = ["nb": "no", "fil": "tl", "jv": "jw", "iw": "he", "in": "id"]
}

extension Array where Element: Hashable {
    /// The elements in order, each once.
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
