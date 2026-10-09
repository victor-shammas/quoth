import AudioToolbox
import CoreAudio
import Foundation

/// The output volume as the menu bar's slider sets it: the device's virtual
/// main volume, 0 to 1, which works for devices with one control or one per
/// channel.
enum OutputVolume {
    static func defaultOutputID() -> AudioDeviceID? {
        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id
        )
        guard status == noErr, id != kAudioObjectUnknown else { return nil }
        return id
    }

    private static var volumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    /// Whether `id` has a volume that can be set. HDMI and some USB devices
    /// don't.
    static func isSettable(_ id: AudioDeviceID) -> Bool {
        var address = volumeAddress
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(id, &address),
              AudioObjectIsPropertySettable(id, &address, &settable) == noErr
        else { return false }
        return settable.boolValue
    }

    static func volume(of id: AudioDeviceID) -> Float? {
        var address = volumeAddress
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &volume) == noErr else { return nil }
        return volume
    }

    @discardableResult
    static func set(_ volume: Float, on id: AudioDeviceID) -> Bool {
        var address = volumeAddress
        var value = Float32(min(max(volume, 0), 1))
        let size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectSetPropertyData(id, &address, 0, nil, size, &value) == noErr
    }

    /// The device's persistent ID, which survives a restart; the
    /// `AudioDeviceID` doesn't.
    static func uid(of id: AudioDeviceID) -> String? {
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &uid) == noErr,
              let value = uid?.takeRetainedValue()
        else { return nil }
        return value as String
    }

    /// The device with `uid`, if it is connected.
    static func device(withUID uid: String) -> AudioDeviceID? {
        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var cfUID = uid as CFString
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = withUnsafePointer(to: &cfUID) { qualifier in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address,
                UInt32(MemoryLayout<CFString>.size), qualifier, &size, &id
            )
        }
        guard status == noErr, id != kAudioObjectUnknown else { return nil }
        return id
    }
}
