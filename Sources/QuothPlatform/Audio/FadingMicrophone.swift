import Foundation

/// A `Microphone` that, when `isEnabled`, fades the Mac's other sound down
/// for as long as it records (`SoundSettings.fadeWhileDictating`): down
/// from the press, back up once the recording is finished or thrown away,
/// whatever ended it.
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
        // Before the microphone opens: a Bluetooth headset starts switching
        // to its call profile then, and the fade should be ahead of it.
        let fades = isEnabled && !faded
        if fades {
            faded = true
            fader.fadeOut()
        }
        do {
            try microphone.start()
        } catch {
            if fades { restore() }
            throw error
        }
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

    private func restore() {
        guard faded else { return }
        faded = false
        fader.fadeIn()
    }
}
