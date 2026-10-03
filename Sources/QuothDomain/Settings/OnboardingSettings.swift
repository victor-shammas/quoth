import Foundation

/// Whether the onboarding window has been through (`Settings.onboarding`).
public struct OnboardingSettings: Codable, Equatable {
    /// Set by Get Started or by closing the window. Missing in files from
    /// before v0.2.0, so upgraders see the window once too.
    public var completed = false

    public init() {}

    public init(from decoder: Decoder) throws {
        completed = try decoder.container(keyedBy: CodingKeys.self).value(.completed, or: completed)
    }
}
