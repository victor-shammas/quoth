import Foundation
import QuothDomain

/// A `Microphone` that, when `isEnabled`, fades the Mac's other sound down
/// for as long as it records (`SoundSettings.fadeWhileDictating`): down
/// once the microphone is open, back up once the recording is finished or
/// thrown away, whatever ended it.
public final class FadingMicrophone: Microphone {
    private let microphone: Microphone
    private let fader: SoundFading
    /// Read at each press; a change mid-recording applies from the next.
    public var isEnabled = false
    /// Whether this recording faded the sound, so it comes back once.
    private var faded = false

    public init(_ microphone: Microphone, fader: SoundFading) {
        self.microphone = microphone
        self.fader = fader
    }

    public func start() throws {
        try microphone.start()
        // After the microphone opens, which settles what it records: the
        // fader leaves a Bluetooth headset recording through its own
        // microphone alone.
        guard isEnabled, !faded else { return }
        faded = true
        fader.fadeOut(recordingBluetooth: microphone.recordingInput.isBluetooth)
    }

    public func finish(keepBeforeRouteChange: Bool) throws -> [Float] {
        defer { restore() }
        return try microphone.finish(keepBeforeRouteChange: keepBeforeRouteChange)
    }

    public func stop() {
        microphone.stop()
        restore()
    }

    public func samples(from offset: Int) -> [Float] { microphone.samples(from: offset) }
    public var hasRouteChanged: Bool { microphone.hasRouteChanged }
    public var lastFirstSampleDelay: TimeInterval? { microphone.lastFirstSampleDelay }
    public var recordingInput: RecordingInput { microphone.recordingInput }

    private func restore() {
        guard faded else { return }
        faded = false
        fader.fadeIn()
    }
}
