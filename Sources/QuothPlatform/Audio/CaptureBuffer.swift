import Foundation

/// What one recording has captured so far: the realtime thread appends,
/// live text reads as it goes, and `AudioCapture.finish` takes it at the
/// end. It holds no audio unit, so the rules about what a finish returns are
/// tested without hardware.
public final class CaptureBuffer: @unchecked Sendable {
    /// Counts and timings for one recording. Never audio.
    public struct Stats: Equatable {
        /// Input buffers converted and kept.
        public var buffers = 0
        /// Frames received at the input's own rate.
        public var inputFrames = 0
        /// Buffers the converter failed on.
        public var conversionFailures = 0
        /// Buffers the input failed to render.
        public var inputFailures = 0
        /// Seconds from the press to the first buffer arriving.
        public var firstBufferDelay: TimeInterval?
        /// Seconds from the press to the capture of the first sample, by its
        /// host timestamp: anything said before it is lost.
        public var firstSampleDelay: TimeInterval?
        /// The same to the first sample that isn't exactly zero; some inputs
        /// deliver digital silence while they settle, and that is lost too.
        public var firstSoundDelay: TimeInterval?
    }

    /// Samples whose allocation is kept between recordings: 30 s.
    public static let keptCapacity = 30 * 16_000

    private let lock = NSLock()
    private var samples: [Float] = []
    private var stats = Stats()
    /// The press, in `HostClock` nanoseconds.
    private var startedAt: UInt64 = 0
    private var isOpen = false
    /// How many samples there were when the input route changed, if it did.
    private var routeChangedAt: Int?

    public init() {}

    /// Opens a new recording, pressed at `startedAt`.
    public func reset(startedAt: UInt64) {
        lock.withLock {
            samples.removeAll(keepingCapacity: true)
            stats = Stats()
            routeChangedAt = nil
            self.startedAt = startedAt
            isOpen = true
        }
    }

    /// Whether a recording is open. Input outside one is dropped.
    public var isRecording: Bool { lock.withLock { isOpen } }

    /// Converted 16 kHz samples from one input buffer of `inputFrames`.
    public func append(_ chunk: UnsafeBufferPointer<Float>, inputFrames: Int, at now: UInt64) {
        lock.withLock {
            if stats.firstBufferDelay == nil { stats.firstBufferDelay = HostClock.seconds(from: startedAt, to: now) }
            stats.buffers += 1
            stats.inputFrames += inputFrames
            samples.append(contentsOf: chunk)
        }
    }

    /// What the converter still held when the input stopped. Not a buffer.
    public func appendTail(_ chunk: UnsafeBufferPointer<Float>) {
        lock.withLock { samples.append(contentsOf: chunk) }
    }

    /// When an input buffer's first frame was captured, and its first
    /// non-zero one, if any (host nanoseconds). The first of each counts.
    public func noteInput(firstFrameAt: UInt64, firstSoundAt: UInt64?) {
        lock.withLock {
            if stats.firstSampleDelay == nil { stats.firstSampleDelay = HostClock.seconds(from: startedAt, to: firstFrameAt) }
            if stats.firstSoundDelay == nil, let firstSoundAt {
                stats.firstSoundDelay = HostClock.seconds(from: startedAt, to: firstSoundAt)
            }
        }
    }

    /// Until the first non-zero sample, so the realtime thread looks for one
    /// only while it matters.
    public var awaitingSound: Bool { lock.withLock { stats.firstSoundDelay == nil } }

    public func recordInputFailure() { lock.withLock { stats.inputFailures += 1 } }
    public func recordConversionFailure() { lock.withLock { stats.conversionFailures += 1 } }

    /// The input route changed. Notes where, and nothing else: the unit is
    /// torn down on release, never inside a notification.
    public func markRouteChanged() {
        lock.withLock { if routeChangedAt == nil { routeChangedAt = samples.count } }
    }

    public var hasRouteChanged: Bool { lock.withLock { routeChangedAt != nil } }

    /// The samples from `offset` on, without ending the recording, for live
    /// text. Never past a route change.
    public func samples(from offset: Int) -> [Float] {
        lock.withLock {
            let end = routeChangedAt ?? samples.count
            return offset < end ? Array(samples[offset..<end]) : []
        }
    }

    public var currentStats: Stats { lock.withLock { stats } }

    /// Ends the recording and returns its samples, leaving the buffer empty.
    /// After a route change the partial recording is never returned as if
    /// whole: this throws `CaptureError.routeChanged`, unless
    /// `keepBeforeRouteChange` asks for what came before the change (a
    /// locked recording, where minutes are at stake).
    public func finish(keepBeforeRouteChange: Bool = false) throws -> [Float] {
        let (captured, changed): ([Float], Bool) = lock.withLock {
            let changedAt = routeChangedAt
            let captured = changedAt.map { keepBeforeRouteChange ? Array(samples[..<$0]) : [] } ?? samples
            // Keep the allocation for the next short dictation, but give back
            // what a long locked one took (about 3.8 MB a minute).
            if samples.count > Self.keptCapacity { samples = [] } else { samples.removeAll(keepingCapacity: true) }
            routeChangedAt = nil
            isOpen = false
            return (captured, changedAt != nil)
        }
        if changed && !keepBeforeRouteChange { throw CaptureError.routeChanged }
        return captured
    }
}
