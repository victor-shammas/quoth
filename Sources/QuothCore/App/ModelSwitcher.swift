import Foundation
import QuothDomain
import QuothPlatform
import QuothSpeech

/// Changes the model while Quoth runs. The new one downloads if needed and
/// loads in the background while the current one keeps transcribing, then
/// swaps in between dictations, never under one.
///
/// Choosing again while a load runs drops that load. A load that fails is
/// reported, the current model stays, and the setting stays as chosen, so
/// the next change or launch tries again. Progress goes to
/// `AppModel.modelLoad`, which the menu and Settings show.
@MainActor
final class ModelSwitcher {
    /// The model transcribing now.
    private(set) var model: TranscriptionModel
    private var transcriber: WhisperKitTranscriber
    /// Set once by `Assembly`.
    weak var session: DictationSession?
    weak var app: AppModel?
    /// Called each time a model swaps in, ready.
    var onReady: (() -> Void)?

    private var load: Task<Void, Never>?
    /// Bumped on every choice, so a superseded load can neither swap nor report.
    private var generation = 0

    init(model: TranscriptionModel, transcriber: WhisperKitTranscriber) {
        self.model = model
        self.transcriber = transcriber
    }

    /// Loads and swaps in the model `id` names (`Startup.model(for:)`).
    func select(_ id: String?) {
        let next = Startup.model(for: id)
        generation += 1
        load?.cancel()
        load = nil
        guard next.id != model.id else {
            // Back to the model in use: nothing to load.
            app?.modelLoad = nil
            return
        }
        Log.info("model: loading \(next.id) behind \(model.id)")
        let generation = self.generation
        report(WhisperKitTranscriber.isCached(next) ? .loading : .downloading(nil), for: next, generation)
        load = Task { await self.load(next, generation) }
    }

    private func load(_ next: TranscriptionModel, _ generation: Int) async {
        let incoming = WhisperKitTranscriber(model: next)
        do {
            try await incoming.warmUp { fraction in
                Task { @MainActor in
                    self.report(fraction < 1 ? .downloading(fraction) : .loading, for: next, generation)
                }
            }
            report(.loading, for: next, generation)
            // Between dictations: never under one recording or transcribing.
            while (session?.state ?? .idle) != .idle {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            try Task.checkCancellation()
            guard generation == self.generation else { return await incoming.unload() }
            swap(to: next, incoming)
        } catch {
            await incoming.unload()
            guard generation == self.generation, !Task.isCancelled else { return }
            Log.error("couldn't load \(next.id): \(error); keeping \(model.id)")
            report(.failed, for: next, generation)
        }
    }

    private func swap(to next: TranscriptionModel, _ incoming: WhisperKitTranscriber) {
        let outgoing = transcriber
        session?.replaceTranscriber(incoming)
        transcriber = incoming
        model = next
        load = nil
        app?.activeModelID = next.id
        app?.modelLoad = nil
        Log.info("model: \(next.id)")
        // Free the old model's memory. Nothing transcribes with it any more:
        // the swap waited for the session to go idle.
        Task { await outgoing.unload() }
        onReady?()
    }

    private func report(_ phase: ModelLoad.Phase, for next: TranscriptionModel, _ generation: Int) {
        // A progress report can land after its load was superseded or done.
        guard generation == self.generation, next.id != model.id, let app else { return }
        let state = ModelLoad(modelID: next.id, phase: phase)
        if ModelLoad.replaces(app.modelLoad, with: state) { app.modelLoad = state }
    }
}
