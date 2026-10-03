import Foundation

/// The pill's bars: microphone levels, arriving about every 12 ms, turned
/// into six bar heights about every 100 ms, which is as fast as the bars
/// look calm at.
public struct LevelMeter {
    public static let barCount = 6
    /// How much of the level each bar shows: the middle ones peak highest.
    static let envelope: [Float] = [0.55, 0.85, 1.0, 1.0, 0.85, 0.55]
    /// RMS over one refresh above which the recording counts as speech.
    /// Silence measures about 0.001; speech averages 0.007 to 0.018 and
    /// peaks well above.
    public static let voiceThreshold: Float = 0.01
    public static let refreshInterval: TimeInterval = 0.1

    /// Whether this recording has been louder than silence, so one with
    /// nothing said gets no settling animation.
    public private(set) var heardVoice = false
    private var power: Float = 0
    private var count = 0
    private var lastRefresh: TimeInterval = 0
    /// A little per-bar randomness, so the bars don't move in lockstep.
    private let jitter: () -> Float

    public init(jitter: @escaping () -> Float = { Float.random(in: 0.78...1.0) }) {
        self.jitter = jitter
    }

    /// Adds one buffer's level at `time` (seconds, monotonic). Returns the
    /// bar heights, 0 to 1, when a refresh is due: the RMS since the last
    /// one, shaped and spread over the bars.
    public mutating func add(_ level: Float, at time: TimeInterval) -> [Float]? {
        power += level * level
        count += 1
        guard time - lastRefresh >= Self.refreshInterval else { return nil }
        let rms = (power / Float(count)).squareRoot()
        power = 0
        count = 0
        lastRefresh = time
        if rms > Self.voiceThreshold { heardVoice = true }
        // Quiet speech still moves the bars: square root, then gain.
        let shaped = min(1, max(0, rms).squareRoot() * 3.4)
        return Self.envelope.map { shaped * $0 * jitter() }
    }

    /// For a new recording.
    public mutating func reset() {
        power = 0
        count = 0
        heardVoice = false
    }
}
