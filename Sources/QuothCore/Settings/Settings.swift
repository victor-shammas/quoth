import Foundation

/// Every persistent preference, stored as `Paths.settingsFile`.
///
/// One field per feature, each a struct declared in that feature's folder.
/// A missing key decodes to its default, so a file written by an older
/// version, or `{}`, still loads. `SettingsStore` reads and writes it.
///
/// Feature structs follow the same rule: give every field a default and
/// decode it with `decodeIfPresent(…) ?? default` in `init(from:)`.
struct Settings: Codable, Equatable {
    var hotkey = HotkeySettings()
    var dictionary = DictionarySettings()
    var language = LanguageSettings()
    var model = ModelSettings()
    var onboarding = OnboardingSettings()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hotkey = try c.decodeIfPresent(HotkeySettings.self, forKey: .hotkey) ?? HotkeySettings()
        dictionary = try c.decodeIfPresent(DictionarySettings.self, forKey: .dictionary) ?? DictionarySettings()
        language = try c.decodeIfPresent(LanguageSettings.self, forKey: .language) ?? LanguageSettings()
        model = try c.decodeIfPresent(ModelSettings.self, forKey: .model) ?? ModelSettings()
        onboarding = try c.decodeIfPresent(OnboardingSettings.self, forKey: .onboarding) ?? OnboardingSettings()
    }
}

extension Settings {
    /// Defaults for every preference, keeping what is the user's own rather
    /// than a preference: the dictionary's example sentences, the languages
    /// they speak, and that onboarding is done (Reset to Defaults…).
    func reset() -> Settings {
        var fresh = Settings()
        fresh.dictionary = dictionary
        fresh.language.spoken = language.spoken
        fresh.onboarding = onboarding
        return fresh
    }
}
