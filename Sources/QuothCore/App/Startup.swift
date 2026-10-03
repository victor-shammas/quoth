import ApplicationServices
import AVFoundation
import Foundation
import QuothDomain

/// Why Quoth could not start.
///
/// A permanent failure needs the user to act and a relaunch cannot fix it,
/// so `QuothApp` shows it once and exits 0. Anything else (warmup errors, a
/// crash) exits nonzero. The login item (`SMAppService.mainApp`) starts
/// Quoth once per login and does not relaunch it.
public enum StartupFailure: Error {
    case microphoneDenied
    case unknownModel(String)
    case noModelsRegistered
    case warmupFailed(Error)
    case hotkeyUnavailable(Error)

    public var isPermanent: Bool {
        switch self {
        case .microphoneDenied, .unknownModel, .noModelsRegistered:
            return true
        case .warmupFailed, .hotkeyUnavailable:
            return false
        }
    }

    /// The one message to log. Permanent failures name the exact fix.
    public var message: String {
        switch self {
        case .microphoneDenied:
            return Self.permanent(
                "microphone access denied",
                fix: "enable Quoth in System Settings → Privacy & Security → Microphone"
            )
        case .unknownModel(let id):
            return Self.permanent("unknown model: \(id)", fix: "choose a model in Settings › Model")
        case .noModelsRegistered:
            return Self.permanent("no models registered", fix: "reinstall Quoth")
        case .warmupFailed(let error):
            return "warmup failed: \(error)"
        case .hotkeyUnavailable(let error):
            return "failed to register hotkey tap: \(error)"
        }
    }

    private static func permanent(_ problem: String, fix: String) -> String {
        "\(problem)\n"
            + "  fix: \(fix), then restart Quoth "
            + "(`open -a Quoth`, or log in again)."
    }
}

/// Checks that run before any model loads, so a failing start costs nothing.
enum Startup {
    /// Runs the startup checks and returns the model to load.
    /// Throws `StartupFailure`.
    static func check(modelID: String?) throws -> TranscriptionModel {
        let model = try resolveModel(modelID)

        // The hotkey's grant is not checked here. A missing grant is not a
        // startup failure: Quoth waits for it (Assembly.startHotkey).

        // .notDetermined is left to the onboarding window, and to the first
        // press if still undecided.
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .denied, .restricted:
            throw StartupFailure.microphoneDenied
        default:
            break
        }

        if !WhisperKitTranscriber.isCached(model) {
            Log.info("\(model.id) not in \(Paths.appSupport.path), downloading")
        }

        return model
    }

    /// The model for `id`, or the recommended one when `id` is nil.
    static func resolveModel(_ id: String?) throws -> TranscriptionModel {
        if let id {
            guard let m = ModelRegistry.find(id) else { throw StartupFailure.unknownModel(id) }
            return m
        }
        guard let m = ModelRegistry.recommended() else { throw StartupFailure.noModelsRegistered }
        return m
    }
}
