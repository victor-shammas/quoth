import CoreAudio
import Foundation

/// Listens for the changes that matter to a built unit: the default input
/// switching, the device's rate or input channels changing, or the device
/// disappearing, and calls `changed`, which re-reads and decides. Listeners
/// are removed when this is released.
public final class DeviceWatcher {
    /// A fresh read of the input a unit was built for.
    public struct Snapshot: Equatable {
        public var defaultInput: AudioDeviceID?
        public var isAlive: Bool
        public var device: InputDevice
    }

    private let queue = DispatchQueue(label: "quoth.capture.device-watcher")
    private var registrations: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    public init(device: AudioDeviceID, changed: @escaping () -> Void) {
        let block: AudioObjectPropertyListenerBlock = { _, _ in changed() }
        let system = AudioObjectID(kAudioObjectSystemObject)
        add(system, kAudioHardwarePropertyDefaultInputDevice, kAudioObjectPropertyScopeGlobal, block)
        add(device, kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal, block)
        add(device, kAudioDevicePropertyStreamConfiguration, kAudioDevicePropertyScopeInput, block)
        add(device, kAudioDevicePropertyDeviceIsAlive, kAudioObjectPropertyScopeGlobal, block)
    }

    deinit {
        for (object, address, block) in registrations {
            var address = address
            AudioObjectRemovePropertyListenerBlock(object, &address, queue, block)
        }
    }

    private func add(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        _ scope: AudioObjectPropertyScope,
        _ block: @escaping AudioObjectPropertyListenerBlock
    ) {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        if AudioObjectAddPropertyListenerBlock(object, &address, queue, block) == noErr {
            registrations.append((object, address, block))
        }
    }

    /// Reads the default input and `id`'s presence, rate and channels now.
    public static func snapshot(of id: AudioDeviceID) -> Snapshot {
        Snapshot(
            defaultInput: InputDevice.defaultInputID(),
            isAlive: isAlive(id),
            device: InputDevice(
                sampleRate: InputDevice.nominalSampleRate(id),
                channels: InputDevice.inputChannels(id),
                id: id
            )
        )
    }

    private static func isAlive(_ id: AudioDeviceID) -> Bool {
        var alive: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &alive) == noErr else { return false }
        return alive != 0
    }
}
