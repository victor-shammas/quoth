import Foundation

/// What one recording has captured so far. The audio thread appends to it;
/// `AudioCapture.stop()` reads it once. It holds no engine, so the rules
/// about what a stop returns are testable without hardware.
public final class CaptureBuffer: @unchecked Sendable {
    /// Counts and timings for one recording. Never audio.
    public struct Stats: Equatable {
        /// Tap callbacks that delivered converted audio.
        public var buffers = 0
        /// Frames received at the input's own sample rate.
        public var inputFrames = 0
        /// Buffers the converter failed on.
        public var conversionFailures = 0
        /// Seconds from `start()` to the first buffer, or nil if none arrived.
        public var firstBufferDelay: TimeInterval?
        /// Seconds from `start()` (the press) to the moment the first sample
        /// of the recording was captured, by the buffer's host timestamp:
        /// anything said before it is lost. Nil if no buffer arrived.
        public var firstSampleDelay: TimeInterval?
        /// The same to the first sample that is not exactly zero. Some inputs
        /// deliver digital silence while they settle; that is lost too.
        public var firstSoundDelay: TimeInterval?
        /// Buffers the input failed to deliver (a render error).
        public var inputFailures = 0
    }

    private let lock = NSLock()
    private var samples: [Float] = []
    private var stats = Stats()
    private var routeChanged = false
    /// Samples recorded before the route changed, for a locked recording
    /// that keeps what came before the change.
    private var routeChangedAt: Int?
    private var startedAt: UInt64 = 0
    private var isOpen = false
    private var closedBuffers = 0

    /// Clears everything for a new recording that started at `startedAt`
    /// (`HostClock` nanoseconds).
    public func reset(startedAt: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        samples.removeAll(keepingCapacity: true)
        stats = Stats()
        routeChanged = false
        routeChangedAt = nil
        self.startedAt = startedAt
        isOpen = true
    }

    /// True while a recording is open. A buffer arriving outside one is
    /// counted and must be dropped: it means the input ran between presses.
    public func admit() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if !isOpen { closedBuffers += 1 }
        return isOpen
    }

    /// Buffers that arrived while no recording was open, over this buffer's
    /// lifetime. Zero unless an input ran between presses.
    public var buffersWhileClosed: Int {
        lock.lock()
        defer { lock.unlock() }
        return closedBuffers
    }

    public func recordInputFailure() {
        lock.lock()
        defer { lock.unlock() }
        stats.inputFailures += 1
    }

    /// Appends converted 16 kHz samples from one tap callback.
    public func append(_ chunk: UnsafeBufferPointer<Float>, inputFrames: Int, at now: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        if stats.firstBufferDelay == nil {
            stats.firstBufferDelay = HostClock.seconds(from: startedAt, to: now)
        }
        stats.buffers += 1
        stats.inputFrames += inputFrames
        samples.append(contentsOf: chunk)
    }

    /// Records when the first frame of an input buffer was captured, and
    /// the first non-zero frame if it has one (host nanoseconds). Only the
    /// first of each counts.
    public func noteInput(firstFrameAt: UInt64, firstSoundAt: UInt64?) {
        lock.lock()
        defer { lock.unlock() }
        if stats.firstSampleDelay == nil {
            stats.firstSampleDelay = HostClock.seconds(from: startedAt, to: firstFrameAt)
        }
        if stats.firstSoundDelay == nil, let firstSoundAt {
            stats.firstSoundDelay = HostClock.seconds(from: startedAt, to: firstSoundAt)
        }
    }

    /// True until a non-zero sample has been noted, so the audio thread
    /// scans for one only while it matters.
    public var awaitingSound: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stats.firstSoundDelay == nil
    }

    /// Appends the converter's tail after the last callback. Not counted as
    /// a buffer.
    public func appendTail(_ chunk: UnsafeBufferPointer<Float>) {
        lock.lock()
        defer { lock.unlock() }
        samples.append(contentsOf: chunk)
    }

    public func recordConversionFailure() {
        lock.lock()
        defer { lock.unlock() }
        stats.conversionFailures += 1
    }

    /// Called from the configuration-change notification. Only sets a flag;
    /// the engine is torn down in `stop()`, never inside the notification.
    public func markRouteChanged() {
        lock.lock()
        defer { lock.unlock() }
        routeChanged = true
        if routeChangedAt == nil { routeChangedAt = samples.count }
    }

    /// Whether the route changed during this recording.
    public var hasRouteChanged: Bool {
        lock.lock()
        defer { lock.unlock() }
        return routeChanged
    }

    /// A copy of the samples recorded so far from `offset` on, without
    /// ending the recording; for live text (fork addition).
    public func samples(from offset: Int) -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        let end = routeChangedAt ?? samples.count
        guard offset < end else { return [] }
        return Array(samples[offset..<end])
    }

    public var currentStats: Stats {
        lock.lock()
        defer { lock.unlock() }
        return stats
    }

    /// Ends the recording and returns its samples. If the route changed at
    /// any point, the partial capture is discarded and this throws
    /// `CaptureError.routeChanged`, so it is never delivered as a success,
    /// unless `keepBeforeRouteChange` asks for the samples recorded before
    /// the change (a locked recording, where minutes are at stake). Either
    /// way the buffer is empty afterwards.
    public func finish(keepBeforeRouteChange: Bool = false) throws -> [Float] {
        lock.lock()
        let changed = routeChanged
        let captured = changed && keepBeforeRouteChange
            ? Array(samples[..<(routeChangedAt ?? samples.count)])
            : samples
        // Keep the allocation for the next short dictation, but give back
        // the memory a long locked one took (about 3.8 MB a minute).
        if samples.count > Self.keptCapacity {
            samples = []
        } else {
            samples.removeAll(keepingCapacity: true)
        }
        routeChanged = false
        routeChangedAt = nil
        isOpen = false
        lock.unlock()
        if changed && !keepBeforeRouteChange { throw CaptureError.routeChanged }
        return captured
    }

    /// Samples whose allocation is kept between recordings: 30 s.
    public static let keptCapacity = 30 * 16_000
}
