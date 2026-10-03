/// The languages Quoth listens for (`Settings.language`).
public struct LanguageSettings: Codable, Equatable {
    /// An ISO 639-1 code such as "pt", or nil for Automatic. Ignored by
    /// English-only models.
    public var code: String?
    /// The languages the user speaks, as ISO 639-1 codes, most used first.
    /// Automatic trusts these at any probability. Nil until the user edits
    /// the list: the Mac's preferred languages stand in for it.
    public var spoken: [String]?

    public init() {}

    /// `spoken`, or the Mac's preferred languages while it is unset.
    public var spokenOrPreferred: [String] {
        spoken ?? SpokenLanguage.preferredCodes()
    }
}
