import Foundation

/// Whether the onboarding window has been through.
///
/// The `settings.json` field for this feature; see `Settings`. Give each new
/// field a default and decode it in `init(from:)` with
/// `decodeIfPresent(…) ?? default`, so older files and `{}` still load.
public struct OnboardingSettings: Codable, Equatable {
    /// Set by Get Started or by closing the window. Missing in files from
    /// before v0.2.0, so upgraders see the window once too.
    public var completed = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        completed = try c.decodeIfPresent(Bool.self, forKey: .completed) ?? false
    }
}
