import AVFoundation
import Foundation

/// Where an input delivers what it captures. Called on the input's own
/// realtime thread.
public struct InputSink {
    /// One buffer at the input's own format, the host time its first frame
    /// was captured, and the host time of the callback (`HostClock`
    /// nanoseconds).
    public var deliver: (_ pcm: AVAudioPCMBuffer, _ firstFrame: UInt64, _ now: UInt64) -> Void
    /// The input route changed; the recording must be discarded.
    public var routeChanged: () -> Void
    /// The input failed to produce a buffer it was due.
    public var inputFailed: () -> Void
}
