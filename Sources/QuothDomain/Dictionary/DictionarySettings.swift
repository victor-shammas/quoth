/// Custom dictionary preferences. The words and replacements live in
/// their own file, `Paths.dictionaryFile`, which `DictionaryStore` reads; the
/// example sentences live here, because they cost decoding time on every
/// dictation and don't fit that table.
///
/// The `settings.json` field for this feature; see `Settings`. Give each new
/// field a default and decode it in `init(from:)` with
/// `decodeIfPresent(…) ?? default`, so older files and `{}` still load.
public struct DictionarySettings: Codable, Equatable {
    /// One natural sentence per language code (`en`, `pt-BR`) that uses the
    /// user's words; the engine reads the one for the spoken language before
    /// each dictation. See `UserDictionary.example(for:)`.
    public var examples: [String: String] = [:]

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        examples = try c.decodeIfPresent([String: String].self, forKey: .examples) ?? [:]
    }
}
