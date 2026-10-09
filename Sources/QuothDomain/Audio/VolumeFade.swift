import Foundation

/// The shape of the fade `SoundSettings.fadeWhileDictating` asks for: the
/// volumes it steps through, and whether to bring the volume back. Pure;
/// `OutputFader` in QuothPlatform applies it.
public enum VolumeFade {
    /// How long the fade down at the press takes.
    public static let outDuration: TimeInterval = 0.25
    /// How long to wait after the microphone closes before fading back up.
    /// A Bluetooth headset takes a moment to leave the call profile; fading
    /// up sooner would play the music at call quality.
    public static let inDelay: TimeInterval = 0.4
    /// How long the fade back up takes.
    public static let inDuration: TimeInterval = 0.5
    /// Time between steps. Bluetooth headsets take each volume change as a
    /// message, so steps much closer than this may be dropped.
    public static let stepInterval: TimeInterval = 0.02

    /// The volumes a fade from `from` to `to` over `duration` sets, one per
    /// step, ending exactly at `to`. Eased at both ends, so there is no
    /// audible jump where it starts or stops.
    public static func levels(from: Float, to: Float, over duration: TimeInterval, step: TimeInterval = stepInterval) -> [Float] {
        let count = max(1, Int((duration / step).rounded()))
        return (1...count).map { i in
            let t = Float(i) / Float(count)
            let eased = t * t * (3 - 2 * t)
            return i == count ? to : from + (to - from) * eased
        }
    }

    /// Whether a fade can be heard as one. A Bluetooth headset whose
    /// microphone is recorded switches to its call profile within a tenth
    /// of a second of the press, faster than any fade, and its volume then
    /// moves to a separate call volume, so fading it would only leave the
    /// music volume part way down. The input and output halves of one
    /// headset are separate devices, so this goes by both being Bluetooth.
    public static func canFade(outputIsBluetooth: Bool, inputIsBluetooth: Bool) -> Bool {
        !(outputIsBluetooth && inputIsBluetooth)
    }

    /// Whether to fade back up, given the volume now and the last one Quoth
    /// set. Faded out, any change is someone turning it up: then they have
    /// the sound they want, and it stays.
    public static func shouldRestore(current: Float, lastSet: Float) -> Bool {
        current <= lastSet + tolerance
    }

    /// How far a volume read back may be from the one set: devices round to
    /// their own steps.
    static let tolerance: Float = 0.02
}
