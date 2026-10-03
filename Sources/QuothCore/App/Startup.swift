import AVFoundation
import Foundation
import QuothDomain
import QuothPlatform
import QuothSpeech

/// What stops Quoth from starting: only the microphone denied, which the
/// user alone can change, in System Settings. Everything else (loading the
/// model, the hotkey's grant) happens behind the menu bar icon and retries.
/// `QuothApp` explains it in a dialog and exits 0, so launch at login
/// doesn't reopen into it.
enum StartupFailure: Error, Equatable {
    case microphoneDenied

    /// For the log.
    var message: String {
        "microphone access denied: enable Quoth in System Settings → Privacy & Security → Microphone, then open Quoth again"
    }
}

/// What runs before anything loads, so a start that can't work costs nothing.
enum Startup {
    /// Returns the model to load, or throws `StartupFailure`.
    static func check(modelID: String?) throws -> TranscriptionModel {
        // Not determined yet is fine: the onboarding window asks, and so
        // does the first press if it's still undecided.
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .denied, .restricted: throw StartupFailure.microphoneDenied
        default: break
        }
        let model = model(for: modelID)
        if !WhisperKitTranscriber.isCached(model) {
            Log.info("\(model.id) not in \(Paths.appSupport.path), downloading")
        }
        return model
    }

    /// The model `id` names, or the recommended one: for no id, and for one
    /// that no longer exists (a model removed in an update, a typo in a hand
    /// edit), which shouldn't stop Quoth.
    static func model(for id: String?) -> TranscriptionModel {
        guard let id else { return ModelRegistry.recommended }
        if let model = ModelRegistry.find(id) { return model }
        Log.warning("settings.json: unknown model \"\(id)\"; using the recommended model")
        return ModelRegistry.recommended
    }
}
