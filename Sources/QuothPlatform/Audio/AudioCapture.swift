import AVFoundation
import Foundation
import QuothDomain

/// The microphone for one recording at a time: what a press starts and a
/// release finishes, as 16 kHz mono Float32 whatever the input's own format.
///
/// The microphone runs only between `start()` and `finish()`, through a
/// `HALInput`. Before it: the permission, and a device that can be
/// recorded. After it: the conversion to 16 kHz and the bookkeeping, in a
/// `CaptureBuffer`.
public final class AudioCapture {
    public static let targetSampleRate: Double = 16_000
    public static let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: targetSampleRate, channels: 1, interleaved: false)!

    /// Each converted buffer's level (RMS, 0 to about 1), for the pill. On
    /// the realtime thread; hop to main to touch UI.
    public var onLevel: ((Float) -> Void)?
    /// The input route changed mid-recording: a headset connected, the
    /// default input moved. On an arbitrary thread.
    public var onRouteChange: (() -> Void)?
    /// Whether to record the Mac's microphone while Bluetooth headphones
    /// play (`MicrophoneSettings.builtInWhileBluetoothPlays`). Read at each
    /// `start()`; set it on the thread that calls `start()`.
    public var builtInWhileBluetoothPlays = true
    /// What the current or last recording records from.
    public private(set) var recordingInput = RecordingInput()

    /// The last finished recording's counts and timings.
    public private(set) var lastStats: CaptureBuffer.Stats?
    /// The recording so far.
    public var currentStats: CaptureBuffer.Stats { buffer.currentStats }
    public var hasRouteChanged: Bool { buffer.hasRouteChanged }
    /// The 16 kHz samples so far from `offset` on, while recording continues
    /// (live text). Safe from any thread.
    public func samples(from offset: Int) -> [Float] { buffer.samples(from: offset) }

    private let input = HALInput()
    private let buffer = CaptureBuffer()
    private let converters = ConverterCache(targetFormat: AudioCapture.targetFormat)
    private var recording = false
    /// For the log line: the input, what the unit delivered, how long it took.
    private var device = InputDevice(sampleRate: 0, channels: 0)
    private var delivered = InputDevice(sampleRate: 0, channels: 0)
    private var startDelay: TimeInterval = 0

    public init() {}

    /// Starts recording. Does nothing if already recording. Throws
    /// `CaptureError`; on a throw nothing is left running.
    public func start() throws {
        guard !recording else { return }
        // The press: press-to-first-sample is measured from here.
        let pressed = HostClock.now()
        if let error = MicrophoneAccess.captureError(for: MicrophoneAccess.status) {
            // A press is when the user is looking: ask, if macOS never has
            // (nothing happens while its prompt is open).
            MicrophoneAccess.requestIfUndetermined()
            throw error
        }
        // A device that can be recorded, before the unit touches it.
        let selection = try InputDevice.select(builtInWhileBluetoothPlays: builtInWhileBluetoothPlays)
        let device = selection.device

        converters.resetAll()
        buffer.reset(startedAt: pressed)
        let buffer = self.buffer
        let sink = InputSink(
            deliver: Self.inputHandler(buffer: buffer, converters: converters, onLevel: onLevel),
            routeChanged: { [onRouteChange] in
                buffer.markRouteChanged()
                onRouteChange?()
            },
            inputFailed: { buffer.recordInputFailure() }
        )
        do {
            delivered = try input.start(device: device, defaultInput: selection.defaultInput, sink: sink)
        } catch {
            _ = try? buffer.finish()
            throw error
        }
        recording = true
        self.device = device
        recordingInput = RecordingInput(
            isBluetooth: InputDevice.isBluetooth(device.id),
            inPlaceOfHeadset: selection.inPlaceOfHeadset
        )
        startDelay = HostClock.seconds(from: pressed, to: HostClock.now())
    }

    /// Stops and throws the recording away, for one the gesture discarded.
    public func stop() {
        do { _ = try finish() } catch { Log.error("capture failed: \(error)") }
    }

    /// Stops and returns the recording. After a route change it throws
    /// `CaptureError.routeChanged` rather than return part of a recording,
    /// unless `keepBeforeRouteChange` asks for what came before the change.
    public func finish(keepBeforeRouteChange: Bool = false) throws -> [Float] {
        guard recording else { return [] }
        recording = false
        input.stop()
        // The input has stopped: flush what the resampler still holds, the
        // end of the last word.
        converters.drain { buffer.appendTail($0) }
        let stats = buffer.currentStats
        lastStats = stats
        log(stats)
        return try buffer.finish(keepBeforeRouteChange: keepBeforeRouteChange)
    }

    /// What the realtime thread does with each input buffer: note when its
    /// first sample, and first non-zero one, were captured, then convert to
    /// 16 kHz and keep it. `firstFrame` and `now` are `HostClock`
    /// nanoseconds. A buffer outside a recording is dropped.
    public static func inputHandler(
        buffer: CaptureBuffer,
        converters: ConverterCache,
        onLevel: ((Float) -> Void)?
    ) -> (_ pcm: AVAudioPCMBuffer, _ firstFrame: UInt64, _ now: UInt64) -> Void {
        { pcm, firstFrame, now in
            guard buffer.isRecording else { return }
            var firstSound: UInt64?
            if buffer.awaitingSound, pcm.format.sampleRate > 0, let frame = firstNonZeroFrame(pcm) {
                firstSound = firstFrame &+ UInt64(Double(frame) / pcm.format.sampleRate * 1_000_000_000)
            }
            buffer.noteInput(firstFrameAt: firstFrame, firstSoundAt: firstSound)
            let converted = converters.convert(pcm) { chunk in
                buffer.append(chunk, inputFrames: Int(pcm.frameLength), at: now)
                onLevel?(computeRMS(chunk))
            }
            if !converted { buffer.recordConversionFailure() }
        }
    }

    /// The first frame in which any channel isn't exactly zero, or nil.
    public static func firstNonZeroFrame(_ pcm: AVAudioPCMBuffer) -> Int? {
        guard let channels = pcm.floatChannelData else { return nil }
        let interleaved = pcm.format.isInterleaved
        var first: Int?
        for c in 0..<Int(pcm.format.channelCount) {
            let data = channels[interleaved ? 0 : c]
            let offset = interleaved ? c : 0
            // Only frames before the earliest found so far can improve on it.
            let limit = first ?? Int(pcm.frameLength)
            if let i = (0..<limit).first(where: { data[$0 * pcm.stride + offset] != 0 }) { first = i }
        }
        return first
    }

    /// One line a recording: counts and timings, never audio. Press to first
    /// sample is the start of the dictation the user loses.
    private func log(_ stats: CaptureBuffer.Stats) {
        func ms(_ delay: TimeInterval?) -> String { delay.map { String(format: "%.0f ms", $0 * 1000) } ?? "none" }
        var line = "  input \(InputDevice.name(of: device.id) ?? "unnamed")"
        if recordingInput.inPlaceOfHeadset { line += " (in place of the playing Bluetooth headphones)" }
        line += String(
            format: " · %.0f Hz × %u · delivered %.0f Hz × %u · hal start %.0f ms",
            device.sampleRate, device.channels, delivered.sampleRate, delivered.channels, startDelay * 1000
        )
        line += " · press→first sample \(ms(stats.firstSampleDelay)) · first sound \(ms(stats.firstSoundDelay))"
        line += " · first buffer \(ms(stats.firstBufferDelay)) · \(stats.buffers) buffers · \(stats.inputFrames) frames"
        if stats.conversionFailures > 0 { line += " · \(stats.conversionFailures) conversion failures" }
        if stats.inputFailures > 0 { line += " · \(stats.inputFailures) input failures" }
        Log.info(line)
        if recordingInput.inPlaceOfHeadset, stats.buffers > 0, stats.firstSoundDelay == nil {
            // A microphone cut off in hardware gives exact zeros: a lid the
            // clamshell check missed.
            Log.warning("the Mac's microphone recorded only silence; is the lid closed?")
        }
    }
}
