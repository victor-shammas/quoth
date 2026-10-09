import CoreAudio
import Foundation
import QuothDomain

/// Turns the Mac's other sound down while Quoth records and back up after.
public protocol SoundFading: AnyObject {
    /// Fades the sound down, once the microphone is open.
    /// `recordingBluetooth`: the microphone is a Bluetooth headset's.
    func fadeOut(recordingBluetooth: Bool)
    /// Fades it back up, once the microphone has closed.
    func fadeIn()
}

/// Fades the default output's volume to silence and back
/// (`SoundSettings.fadeWhileDictating`), in the steps `VolumeFade` gives,
/// never as a cut. A device without a volume Quoth can set is left alone,
/// and so is a Bluetooth headset whose microphone is recorded
/// (`VolumeFade.canFade`).
///
/// The fade back up waits `VolumeFade.inDelay`, and leaves a volume someone
/// turned up meanwhile. A press during it turns it round. While faded, the
/// volume to return to is kept in `Paths.fadedVolume`, so if Quoth quits
/// faded the next launch restores it (`recoverAfterQuit`).
///
/// Everything runs on one private queue, so it can be called from any
/// thread.
public final class OutputFader: SoundFading, @unchecked Sendable {
    private struct Fade {
        let device: AudioDeviceID
        let name: String
        /// The volume before the fade, to come back to.
        let original: Float
        /// The last volume Quoth set.
        var lastSet: Float
    }

    /// What `Paths.fadedVolume` holds.
    private struct Saved: Codable {
        var uid: String
        var volume: Float
    }

    private let queue = DispatchQueue(label: "quoth.fader")
    /// From the fade down until the volume is back. Only on `queue`.
    private var fade: Fade?
    /// The steps still to set, and the timer setting them. Only on `queue`.
    private var steps: [Float] = []
    private var timer: DispatchSourceTimer?
    /// Counts cancellations, so a delayed fade back up that was overtaken
    /// does nothing. Only on `queue`.
    private var generation = 0

    public init() {}

    public func fadeOut(recordingBluetooth: Bool) {
        queue.async { [self] in
            if fade == nil {
                // A volume left faded by a Quoth that quit, now reconnected.
                restoreSaved()
                guard let device = OutputVolume.defaultOutputID() else { return }
                let name = InputDevice.name(of: device) ?? "the output"
                guard VolumeFade.canFade(
                    outputIsBluetooth: InputDevice.isBluetooth(device),
                    inputIsBluetooth: recordingBluetooth
                ) else {
                    Log.info("  sound: not faded; \(name) records too, and switches to call quality as it does")
                    return
                }
                guard OutputVolume.isSettable(device), let volume = OutputVolume.volume(of: device) else {
                    Log.info("  sound: \(name) has no volume Quoth can fade; left as it is")
                    return
                }
                guard volume > 0 else { return }
                fade = Fade(device: device, name: name, original: volume, lastSet: volume)
                if let uid = OutputVolume.uid(of: device) { save(Saved(uid: uid, volume: volume)) }
                Log.info("  sound: fading \(name) down from \(Self.percent(volume))")
            }
            ramp(to: 0, over: VolumeFade.outDuration) {}
        }
    }

    public func fadeIn() {
        queue.async { [self] in
            guard fade != nil else { return }
            cancel()
            let generation = self.generation
            queue.asyncAfter(deadline: .now() + VolumeFade.inDelay) { [self] in
                guard generation == self.generation, let fade else { return }
                guard let current = OutputVolume.volume(of: fade.device) else {
                    // Gone, such as AirPods put away. The saved volume stays
                    // for when they're back.
                    Log.info("  sound: \(fade.name) went away while faded; its volume comes back at the next dictation or launch")
                    self.fade = nil
                    return
                }
                guard VolumeFade.shouldRestore(current: current, lastSet: fade.lastSet) else {
                    Log.info("  sound: \(fade.name) was turned up to \(Self.percent(current)) meanwhile; left there")
                    finish()
                    return
                }
                ramp(to: fade.original, over: VolumeFade.inDuration) { [self] in
                    Log.info("  sound: \(fade.name) back to \(Self.percent(fade.original))")
                    finish()
                }
            }
        }
    }

    /// Puts the volume back at once, for Quoth quitting mid-fade.
    public func restoreNow() {
        queue.sync {
            guard let fade else { return }
            cancel()
            if let current = OutputVolume.volume(of: fade.device),
               VolumeFade.shouldRestore(current: current, lastSet: fade.lastSet) {
                OutputVolume.set(fade.original, on: fade.device)
            }
            finish()
        }
    }

    /// At launch: restores a volume a Quoth that quit while faded left behind.
    public func recoverAfterQuit() {
        queue.sync { restoreSaved() }
    }

    // MARK: On `queue`

    /// Sets the volume step by step from where it is to `target`, then calls
    /// `done`. Replaces any fade under way.
    private func ramp(to target: Float, over duration: TimeInterval, then done: @escaping () -> Void) {
        cancel()
        guard let fade else { return }
        steps = VolumeFade.levels(from: fade.lastSet, to: target, over: duration)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: VolumeFade.stepInterval)
        timer.setEventHandler { [weak self] in
            guard let self, var fade = self.fade else { return }
            guard !self.steps.isEmpty else {
                self.cancel()
                done()
                return
            }
            let level = self.steps.removeFirst()
            OutputVolume.set(level, on: fade.device)
            fade.lastSet = level
            self.fade = fade
        }
        self.timer = timer
        timer.resume()
    }

    private func cancel() {
        generation &+= 1
        timer?.cancel()
        timer = nil
        steps = []
    }

    /// The volume is back, or someone else has it: forget the fade.
    private func finish() {
        cancel()
        fade = nil
        try? FileManager.default.removeItem(at: Paths.fadedVolume)
    }

    private func save(_ saved: Saved) {
        do {
            try Paths.prepareDirectory(Paths.appSupport)
            try JSONEncoder().encode(saved).write(to: Paths.fadedVolume, options: .atomic)
        } catch {
            Log.warning("sound: couldn't note the volume to restore: \(error)")
        }
    }

    /// Restores the volume in `Paths.fadedVolume`, if its device is
    /// connected, and forgets it; a device that isn't keeps it for later.
    private func restoreSaved() {
        guard let data = try? Data(contentsOf: Paths.fadedVolume) else { return }
        guard let saved = try? JSONDecoder().decode(Saved.self, from: data) else {
            try? FileManager.default.removeItem(at: Paths.fadedVolume)
            return
        }
        guard let device = OutputVolume.device(withUID: saved.uid) else { return }
        let name = InputDevice.name(of: device) ?? "the output"
        if let current = OutputVolume.volume(of: device), VolumeFade.shouldRestore(current: current, lastSet: 0) {
            OutputVolume.set(saved.volume, on: device)
            Log.info("sound: \(name) back to \(Self.percent(saved.volume)), left faded when Quoth last quit")
        }
        try? FileManager.default.removeItem(at: Paths.fadedVolume)
    }

    private static func percent(_ volume: Float) -> String {
        String(format: "%.0f%%", volume * 100)
    }
}
