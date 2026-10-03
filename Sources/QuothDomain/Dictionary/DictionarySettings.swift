/// The dictionary's preferences (`Settings.dictionary`). The words live in
/// their own file, `Paths.dictionaryFile`, which `DictionaryStore` reads; the
/// example sentences live here, because they cost decoding time on every
/// dictation and don't fit that table.
public struct DictionarySettings: Codable, Equatable {
    /// One natural sentence per language code (`en`, `pt-BR`) that uses the
    /// user's words; the engine reads the one for the spoken language before
    /// each dictation. See `UserDictionary.example(for:)`.
    public var examples: [String: String] = [:]

    public init() {}

    public init(from decoder: Decoder) throws {
        examples = try decoder.container(keyedBy: CodingKeys.self).value(.examples, or: examples)
    }
}
