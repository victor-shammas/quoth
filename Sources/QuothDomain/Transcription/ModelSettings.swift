/// Which model transcribes (`Settings.model`).
public struct ModelSettings: Codable, Equatable {
    /// A `ModelRegistry` id, or nil for the recommended model. An id the
    /// registry doesn't know falls back to the recommended model at startup.
    public var id: String?

    public init() {}
}
