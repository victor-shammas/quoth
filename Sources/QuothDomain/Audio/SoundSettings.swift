import Foundation

/// What Quoth does to the Mac's other sound while it dictates
/// (`Settings.sound`).
public struct SoundSettings: Codable, Equatable {
    /// Whether the output volume fades down while the microphone is on and
    /// back up once it closes. With AirPods playing music, opening their
    /// microphone drops the music to call quality; faded out, it isn't
    /// heard. Off by default: it changes the Mac's volume.
    public var fadeWhileDictating = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fadeWhileDictating = try c.value(.fadeWhileDictating, or: fadeWhileDictating)
    }
}
