import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation
import QuothDomain

/// The microphone through a Core Audio AUHAL input unit, without
/// `AVAudioEngine`'s graph on top.
///
/// Each press builds a unit for the input `InputDevice.select` chose
/// (usually the default input), delivering Float32 at
/// the device's own rate (`AudioCapture` converts to 16 kHz), and starts
/// it; the release stops and disposes of it, so the device runs only while
/// the hotkey is held. Every Core Audio call returns a status, and formats
/// that can't be recorded (0 Hz, no channels, not finite) are refused before
/// the unit sees them, so nothing here raises an Objective-C exception.
///
/// During a recording, the default input moving to another device, or the
/// device going away, is reported through the sink, and the recording is
/// discarded rather than returned partial. A new rate or channel count on
/// the same device is followed instead: AUHAL doesn't resample input, so
/// the unit restarts in the new format and the recording carries on,
/// missing the few tens of milliseconds the restart takes.
///
/// `start`, `stop` and every reaction to a device change run on one private
/// queue, so a change arriving during a release can't race it.
public final class HALInput {
    /// What a device notification means for the unit recording an input.
    public enum Change: Equatable {
        /// Nothing the unit depends on changed.
        case none
        /// The same device now runs at this rate or channel count.
        case format(InputDevice)
        /// The default input is another device, the device went away, or it
        /// reports a format that can't be recorded.
        case route
    }

    private let control = DispatchQueue(label: "quoth.capture.hal")
    /// The recording in progress. Only touched on `control`.
    private var running: Running?

    private struct Running {
        let unit: AudioUnit
        let context: RenderContext
        /// The device as the unit is configured for it now.
        var device: InputDevice
        /// The default input when recording started: `device`, or the
        /// Bluetooth input the Mac's microphone was taken in place of.
        let defaultInput: AudioDeviceID
        let watcher: DeviceWatcher
    }

    public init() {}

    deinit {
        // Nothing else holds this now, so nothing runs on `control` for it,
        // and deinit may itself run there, where a sync would deadlock.
        teardown()
    }

    /// Builds a unit for `device` (already validated) and starts recording
    /// into `sink`. `defaultInput` is the default input it was chosen
    /// against, when that isn't `device` itself. Returns the format it
    /// delivers. Throws `CaptureError`; on a throw nothing is left running.
    public func start(device: InputDevice, defaultInput: AudioDeviceID? = nil, sink: InputSink) throws -> InputDevice {
        try control.sync {
            teardown()
            let unit = try AUHAL.makeUnit()
            do {
                let format = try AUHAL.configure(unit, for: device)
                let context = RenderContext(unit: unit, pcm: try AUHAL.renderBuffer(for: unit, format: format))
                try AUHAL.setInputCallback(unit, context: context)
                try AUHAL.check(AudioUnitInitialize(unit), "AudioUnitInitialize")
                let control = self.control
                let watcher = DeviceWatcher(device: device.id) { [weak self] in control.async { self?.inputChanged() } }
                context.begin(sink)
                running = Running(
                    unit: unit, context: context, device: device,
                    defaultInput: defaultInput ?? device.id, watcher: watcher
                )
                try AUHAL.check(AudioOutputUnitStart(unit), "AudioOutputUnitStart")
                return InputDevice(sampleRate: format.sampleRate, channels: format.channelCount, id: device.id)
            } catch {
                if running == nil { AudioComponentInstanceDispose(unit) } else { teardown() }
                throw error
            }
        }
    }

    /// Stops recording and disposes of the unit. Safe when not started.
    public func stop() {
        control.sync { teardown() }
    }

    /// A device notification arrived. On `control`.
    private func inputChanged() {
        guard let running else { return }
        let current = DeviceWatcher.snapshot(of: running.device.id)
        switch Self.classify(built: running.device, defaultInput: running.defaultInput, current: current) {
        case .none: return
        case .route: running.context.routeChanged()
        case .format(let device): reformat(to: device)
        }
    }

    /// Restarts the unit in the device's new format, keeping the recording.
    /// If that fails, the recording is discarded as a route change. On
    /// `control`.
    private func reformat(to device: InputDevice) {
        guard let unit = running?.unit, let context = running?.context else { return }
        AudioOutputUnitStop(unit)
        AudioUnitUninitialize(unit)
        do {
            let format = try AUHAL.configure(unit, for: device)
            context.replace(try AUHAL.renderBuffer(for: unit, format: format))
            try AUHAL.check(AudioUnitInitialize(unit), "AudioUnitInitialize")
            try AUHAL.check(AudioOutputUnitStart(unit), "AudioOutputUnitStart")
            running?.device = device
            Log.info(String(format: "  capture: input changed to %.0f Hz × %u mid-recording; continuing", format.sampleRate, format.channelCount))
        } catch {
            Log.error("capture: could not follow the input's new format: \(error)")
            context.routeChanged()
        }
    }

    /// Stops and disposes of the unit, if there is one. On `control`.
    private func teardown() {
        guard let running else { return }
        self.running = nil
        // Returns once the device's IO has stopped: no callback after it.
        AudioOutputUnitStop(running.unit)
        running.context.end()
        AudioUnitUninitialize(running.unit)
        AudioComponentInstanceDispose(running.unit)
    }

    // MARK: Decisions

    /// Whether a unit configured for `built` records `current` as is.
    public static func sameInput(_ built: InputDevice, _ current: InputDevice) -> Bool {
        built.id == current.id && built.sampleRate == current.sampleRate && built.channels == current.channels
    }

    /// What `current`, a fresh read of the input, means for a unit
    /// configured for `built` when the default input was `defaultInput`
    /// (nil: `built` itself). The default input moving to another device is
    /// a route change, unless it moved to the device being recorded: the
    /// Mac's microphone, recording in place of headphones that went away.
    public static func classify(built: InputDevice, defaultInput: AudioDeviceID? = nil, current: DeviceWatcher.Snapshot) -> Change {
        let unchanged = current.defaultInput == (defaultInput ?? built.id) || current.defaultInput == built.id
        guard unchanged, current.isAlive else { return .route }
        if sameInput(built, current.device) { return .none }
        guard (try? InputDevice.validate(sampleRate: current.device.sampleRate, channels: current.device.channels)) != nil else {
            return .route
        }
        return .format(current.device)
    }
}
