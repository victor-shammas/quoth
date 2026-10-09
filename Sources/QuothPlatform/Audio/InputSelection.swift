import CoreAudio
import Foundation
import IOKit
import QuothDomain

/// Which device a press records: the default input, or the Mac's own
/// microphone in place of Bluetooth headphones that are playing
/// (`MicrophoneSettings`). The decision is `InputChoice`'s; this reads what
/// it needs from Core Audio.
extension InputDevice {
    /// The device a press records, validated, and the default input it was
    /// chosen against.
    public struct Selection {
        public var device: InputDevice
        public var defaultInput: AudioDeviceID
        public var inPlaceOfHeadset: Bool
    }

    /// What a press records now. Throws `CaptureError.noInputDevice` with no
    /// default input, or `.invalidInputFormat` if the device can't be
    /// recorded.
    public static func select(builtInWhileBluetoothPlays: Bool) throws -> Selection {
        guard let defaultInput = defaultInputID() else { throw CaptureError.noInputDevice }
        let defaultIsBluetooth = isBluetooth(defaultInput)
        // The rest is only worth reading when it could change the answer.
        let considered = builtInWhileBluetoothPlays && defaultIsBluetooth
        let output = considered ? OutputVolume.defaultOutputID() : nil
        let choice = InputChoice.choose(
            defaultInput: defaultInput,
            defaultIsBluetooth: defaultIsBluetooth,
            bluetoothPlaying: output.map { isBluetooth($0) && isRunningSomewhere($0) } ?? false,
            macMicrophone: considered ? macMicrophoneID() : nil,
            enabled: builtInWhileBluetoothPlays,
            lidClosed: considered && Clamshell.isClosed
        ) ?? ChosenInput(id: defaultInput)
        let id = choice.id
        let device = InputDevice(sampleRate: nominalSampleRate(id), channels: inputChannels(id), id: id)
        try validate(sampleRate: device.sampleRate, channels: device.channels)
        return Selection(device: device, defaultInput: defaultInput, inPlaceOfHeadset: choice.inPlaceOfHeadset)
    }

    /// Whether `id` connects over Bluetooth (Classic or LE). The input and
    /// output halves of one headset are separate devices; both say so.
    public static func isBluetooth(_ id: AudioDeviceID) -> Bool {
        let type = transportType(id)
        return type == kAudioDeviceTransportTypeBluetooth || type == kAudioDeviceTransportTypeBluetoothLE
    }

    /// Whether some app has `id`'s audio running: for an output, that it is
    /// playing. An app may keep it running for a few seconds after a pause.
    static func isRunningSomewhere(_ id: AudioDeviceID) -> Bool {
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }

    /// The Mac's own microphone: a built-in input whose source is the
    /// internal microphone (`'imic'`), not the headset jack or a line in.
    /// Nil on a Mac without one, such as a Mac mini.
    static func macMicrophoneID() -> AudioDeviceID? {
        allDeviceIDs().first { id in
            guard transportType(id) == kAudioDeviceTransportTypeBuiltIn, inputChannels(id) > 0 else { return false }
            return inputDataSource(id) == internalMicrophone
        }
    }

    /// `kAudioDevicePropertyDataSource` for the internal microphone.
    private static let internalMicrophone: UInt32 = 0x696D_6963 // 'imic'

    private static func transportType(_ id: AudioDeviceID) -> UInt32? {
        var type: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &type) == noErr else { return nil }
        return type
    }

    private static func inputDataSource(_ id: AudioDeviceID) -> UInt32? {
        var source: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDataSource,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &source) == noErr else { return nil }
        return source
    }

    /// Every audio device Core Audio knows, input or not.
    private static func allDeviceIDs() -> [AudioDeviceID] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: kAudioObjectUnknown, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioDeviceID>.size))
    }
}

/// Whether a MacBook's lid is closed. Closed, its microphone is cut off in
/// hardware, though Core Audio still lists it.
enum Clamshell {
    /// False when it can't be read, and on Macs without a lid.
    static var isClosed: Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        return (value as? Bool) ?? false
    }
}
