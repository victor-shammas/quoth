import AudioToolbox
import AVFoundation
import Foundation

/// What the render callback needs, shared between Core Audio's realtime
/// thread and `HALInput`'s queue: the unit, a buffer to render into, and
/// the sink while a recording is open.
final class RenderContext: @unchecked Sendable {
    let unit: AudioUnit
    private let lock = NSLock()
    private var pcm: AVAudioPCMBuffer
    private var sink: InputSink?

    init(unit: AudioUnit, pcm: AVAudioPCMBuffer) {
        self.unit = unit
        self.pcm = pcm
    }

    func begin(_ sink: InputSink) { lock.withLock { self.sink = sink } }
    func end() { lock.withLock { sink = nil } }

    /// A buffer in the unit's new format. Only while the unit is stopped.
    func replace(_ pcm: AVAudioPCMBuffer) { lock.withLock { self.pcm = pcm } }

    /// Discards the recording in progress, if any.
    func routeChanged() { lock.withLock { sink }?.routeChanged() }

    /// One input slice: render it into the buffer and hand it to the sink,
    /// with the host time of its first frame.
    func render(
        _ flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        _ timestamp: UnsafePointer<AudioTimeStamp>,
        _ bus: UInt32,
        _ frames: UInt32
    ) -> OSStatus {
        let now = HostClock.now()
        let (sink, pcm) = lock.withLock { (self.sink, self.pcm) }
        guard let sink else { return noErr }
        guard frames <= pcm.frameCapacity else {
            sink.inputFailed()
            return noErr
        }
        pcm.frameLength = frames
        // Through the list's pointer, by index: `for var` would change copies.
        let buffers = UnsafeMutableAudioBufferListPointer(pcm.mutableAudioBufferList)
        for i in buffers.indices {
            buffers[i].mDataByteSize = frames * UInt32(MemoryLayout<Float>.size)
        }
        let status = AudioUnitRender(unit, flags, timestamp, bus, frames, pcm.mutableAudioBufferList)
        guard status == noErr else {
            sink.inputFailed()
            return status
        }
        let stamp = timestamp.pointee
        let firstFrame = stamp.mFlags.contains(.hostTimeValid)
            ? HostClock.nanoseconds(fromHostTime: stamp.mHostTime)
            : now &- UInt64(Double(frames) / pcm.format.sampleRate * 1_000_000_000)
        sink.deliver(pcm, firstFrame, now)
        return noErr
    }
}
