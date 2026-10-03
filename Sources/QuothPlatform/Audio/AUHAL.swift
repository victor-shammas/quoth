import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation

/// Building and configuring an AUHAL input unit. Each step checks its status.
enum AUHAL {
    static func makeUnit() throws -> AudioUnit {
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &description) else {
            throw CaptureError.engineStartFailed(error(-1, "AudioComponentFindNext"))
        }
        var unit: AudioUnit?
        try check(AudioComponentInstanceNew(component, &unit), "AudioComponentInstanceNew")
        guard let unit else { throw CaptureError.engineStartFailed(error(-1, "AudioComponentInstanceNew")) }
        return unit
    }

    /// Input on, output off, bound to `device`, delivering `clientFormat` for
    /// what the device delivers. Returns that format.
    static func configure(_ unit: AudioUnit, for device: InputDevice) throws -> AVAudioFormat {
        try set(unit, kAudioOutputUnitProperty_EnableIO, scope: kAudioUnitScope_Input, element: 1, to: UInt32(1), "EnableIO input")
        try set(unit, kAudioOutputUnitProperty_EnableIO, scope: kAudioUnitScope_Output, element: 0, to: UInt32(0), "EnableIO output")
        try set(unit, kAudioOutputUnitProperty_CurrentDevice, scope: kAudioUnitScope_Global, element: 0, to: device.id, "CurrentDevice")

        var hardware = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &hardware, &size), "input format")
        guard let client = clientFormat(sampleRate: hardware.mSampleRate, channels: hardware.mChannelsPerFrame) else {
            throw CaptureError.invalidInputFormat(sampleRate: hardware.mSampleRate, channels: hardware.mChannelsPerFrame)
        }
        try set(unit, kAudioUnitProperty_StreamFormat, scope: kAudioUnitScope_Output, element: 1, to: client.streamDescription.pointee, "client format")
        return client
    }

    /// What the unit delivers for an input at `sampleRate` with `channels`:
    /// Float32, not interleaved, at the device's own rate (AUHAL doesn't
    /// resample input), with at most two channels. Nil for an input that
    /// can't be recorded.
    static func clientFormat(sampleRate: Double, channels: UInt32) -> AVAudioFormat? {
        guard (try? InputDevice.validate(sampleRate: sampleRate, channels: channels)) != nil else { return nil }
        return AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: min(channels, 2), interleaved: false)
    }

    /// A buffer in `format` big enough for any slice the unit renders.
    static func renderBuffer(for unit: AudioUnit, format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        var maxFrames: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioUnitGetProperty(unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFrames, &size)
        guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(maxFrames, 8192)) else {
            throw CaptureError.invalidInputFormat(sampleRate: format.sampleRate, channels: format.channelCount)
        }
        return pcm
    }

    static func setInputCallback(_ unit: AudioUnit, context: RenderContext) throws {
        let callback = AURenderCallbackStruct(inputProc: renderCallback, inputProcRefCon: Unmanaged.passUnretained(context).toOpaque())
        try set(unit, kAudioOutputUnitProperty_SetInputCallback, scope: kAudioUnitScope_Global, element: 0, to: callback, "SetInputCallback")
    }

    private static func set<T>(
        _ unit: AudioUnit, _ property: AudioUnitPropertyID, scope: AudioUnitScope, element: AudioUnitElement,
        to value: T, _ step: String
    ) throws {
        let status = withUnsafePointer(to: value) {
            AudioUnitSetProperty(unit, property, scope, element, $0, UInt32(MemoryLayout<T>.size))
        }
        try check(status, step)
    }

    static func check(_ status: OSStatus, _ step: String) throws {
        guard status != noErr else { return }
        throw CaptureError.engineStartFailed(error(status, step))
    }

    private static func error(_ status: OSStatus, _ step: String) -> NSError {
        NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: step])
    }
}

private let renderCallback: AURenderCallback = { refCon, flags, timestamp, bus, frames, _ in
    Unmanaged<RenderContext>.fromOpaque(refCon).takeUnretainedValue().render(flags, timestamp, bus, frames)
}
