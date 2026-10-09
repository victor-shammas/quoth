import Foundation

/// Every persistent preference, stored as `Paths.settingsFile` and read and
/// written by `SettingsStore`.
///
/// One field per feature, each a struct beside that feature's code. Every
/// field of every struct has a default and decodes with `value(_:or:)`, so a
/// file from an older Quoth, or `{}`, still loads, and a field added later
/// takes its default.
public struct Settings: Codable, Equatable {
    public var hotkey = HotkeySettings()
    public var dictionary = DictionarySettings()
    public var language = LanguageSettings()
    public var model = ModelSettings()
    public var sound = SoundSettings()
    public var onboarding = OnboardingSettings()

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hotkey = try c.value(.hotkey, or: hotkey)
        dictionary = try c.value(.dictionary, or: dictionary)
        language = try c.value(.language, or: language)
        model = try c.value(.model, or: model)
        sound = try c.value(.sound, or: sound)
        onboarding = try c.value(.onboarding, or: onboarding)
    }

    /// Defaults for every preference, keeping what is the user's own rather
    /// than a preference: the dictionary's example sentences, the languages
    /// they speak, and that onboarding is done (Reset to Defaults…).
    public func reset() -> Settings {
        var fresh = Settings()
        fresh.dictionary = dictionary
        fresh.language.spoken = language.spoken
        fresh.onboarding = onboarding
        return fresh
    }
}

extension KeyedDecodingContainer {
    /// The value for `key`, or `fallback` when the file doesn't have it.
    func value<T: Decodable>(_ key: Key, or fallback: T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? fallback
    }
}
