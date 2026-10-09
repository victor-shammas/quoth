import Foundation

/// Which microphone a dictation records (`Settings.microphone`).
public struct MicrophoneSettings: Codable, Equatable {
    /// Whether, while Bluetooth headphones play sound and their microphone
    /// is the default input, Quoth records the Mac's own microphone instead.
    /// Opening the headphones' microphone switches them to their call
    /// profile: the music drops to call quality, and only comes back some
    /// seconds after the dictation. With nothing playing, the headphones'
    /// microphone is used, so dictating away from the Mac still works.
    public var builtInWhileBluetoothPlays = true

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        builtInWhileBluetoothPlays = try c.value(.builtInWhileBluetoothPlays, or: builtInWhileBluetoothPlays)
    }
}

/// The input a press records.
public struct ChosenInput: Equatable, Sendable {
    public var id: UInt32
    /// The Mac's microphone, taken in place of a Bluetooth default input
    /// whose headphones were playing.
    public var inPlaceOfHeadset: Bool

    public init(id: UInt32, inPlaceOfHeadset: Bool = false) {
        self.id = id
        self.inPlaceOfHeadset = inPlaceOfHeadset
    }
}

/// Which input a press records (`MicrophoneSettings`). Pure; QuothPlatform
/// reads the devices.
public enum InputChoice {
    /// The default input, or the Mac's microphone in its place when all of
    /// these hold: the setting is on, the default input is Bluetooth,
    /// Bluetooth headphones are playing, the Mac has its own microphone, and
    /// the lid is open (closed, a MacBook's microphone is cut off in
    /// hardware and records silence). Nil without a default input.
    public static func choose(
        defaultInput: UInt32?,
        defaultIsBluetooth: Bool,
        bluetoothPlaying: Bool,
        macMicrophone: UInt32?,
        enabled: Bool,
        lidClosed: Bool
    ) -> ChosenInput? {
        guard let defaultInput else { return nil }
        guard enabled, defaultIsBluetooth, bluetoothPlaying, !lidClosed, let macMicrophone, macMicrophone != defaultInput else {
            return ChosenInput(id: defaultInput)
        }
        return ChosenInput(id: macMicrophone, inPlaceOfHeadset: true)
    }
}

/// What the microphone is recording, or last recorded.
public struct RecordingInput: Equatable, Sendable {
    /// A Bluetooth microphone: its headphones are in their call profile.
    public var isBluetooth: Bool
    /// The Mac's microphone in place of Bluetooth headphones that were
    /// playing (`InputChoice`).
    public var inPlaceOfHeadset: Bool

    public init(isBluetooth: Bool = false, inPlaceOfHeadset: Bool = false) {
        self.isBluetooth = isBluetooth
        self.inPlaceOfHeadset = inPlaceOfHeadset
    }
}

/// Why a dictation through the Mac's microphone, taken in place of playing
/// headphones, gave nothing: the user may be away from the Mac.
public enum MicrophoneNotice: UserFacingError, Equatable {
    case macMicrophoneHeardNothing

    public var userMessage: String {
        "Nothing heard on the Mac's microphone. Pause the music to dictate through your headphones."
    }
}
