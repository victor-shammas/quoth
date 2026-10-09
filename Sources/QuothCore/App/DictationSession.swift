import Foundation
import QuothDomain
import QuothPlatform

/// Runs the dictation loop: gesture → capture → transcribe → process →
/// deliver. `DictationMachine` makes every decision; this performs its
/// effects (the microphone, the transcriber, delivery, the Quote Card,
/// observers) and reports back what happened.
///
/// Features plug in as a `TranscriptProcessor` (after transcription, before
/// delivery) or a `DictationObserver` (reacting to the loop), not as
/// branches here.
@MainActor
final class DictationSession {
    private var machine = DictationMachine()

    var state: DictationMachine.State { machine.state }

    private let capture: Microphone
    /// Replaced by `replaceTranscriber` when the model changes.
    private var transcriber: Transcriber
    private let processors: [TranscriptProcessor]
    private let observers: [DictationObserver]
    private let dumpWav: Bool
    private let delivery: TextSink
    private let focus: FocusProbe
    /// What to tell the transcriber about each dictation, asked once per
    /// release. Features such as the dictionary fill it; the session only
    /// passes it on.
    private let context: @MainActor () -> TranscriptionContext

    /// Whether a locked recording types text at each pause.
    var liveText = true
    /// The Quote Card: while it is open, every dictation goes into it.
    weak var card: DictationTarget?
    /// Whether a lock opens the Quote Card (Settings), read at each lock.
    var lockOpensCard: () -> Bool = { false }
    /// Each finished transcript, for Copy and Fix Last Dictation
    /// (`LastDictation`, memory only). Not called for a password field.
    /// Observers never see text; this is the one place it leaves.
    var onTranscript: ((String) -> Void)?
    /// Ends the lock as a tap of the hotkey would (`HotkeyMonitor.endLock`):
    /// for a microphone change, and Stop Dictation in the menu.
    var onEndLock: ((String) -> Void)?
    /// Makes the gesture ignore the rest of the current hold
    /// (`HotkeyMonitor.abandonPress`), after the microphone failed to start.
    var onAbandonPress: (() -> Void)?

    /// What had focus when the current recording started.
    private var focusAtStart: FocusSnapshot?
    /// When the current recording was released.
    private var releasedAt: CFAbsoluteTime = 0
    /// Live text for the current locked recording, if any.
    private var live: LiveTranscription?

    /// One dictation's facts as its effects are performed: what an effect
    /// needs, and what it found out.
    private struct Step {
        /// The error behind a failure, when there is one.
        var error: Error?
        var samples: [Float] = []
        var focus: FocusSnapshot?
        /// The transcript, after processing.
        var text = ""
        var deliveryError: DeliveryError?
        /// `deliver` chose the cursor; the paste is awaited after the effects.
        var deliverAtCursor = false
        var result: DictationResult?
        /// Live text that stopped delivering and still finishes its segments.
        var stoppedLive: LiveTranscription?
    }

    init(
        capture: Microphone,
        transcriber: Transcriber,
        processors: [TranscriptProcessor] = [],
        observers: [DictationObserver],
        dumpWav: Bool = false,
        delivery: TextSink,
        focus: FocusProbe = SystemFocus(),
        context: @escaping @MainActor () -> TranscriptionContext = { TranscriptionContext() }
    ) {
        self.capture = capture
        self.focus = focus
        self.transcriber = transcriber
        self.processors = processors
        self.observers = observers
        self.dumpWav = dumpWav
        self.delivery = delivery
        self.context = context
    }

    /// Uses `transcriber` from the next release on. A transcription already
    /// running finishes with the one it started with.
    func replaceTranscriber(_ transcriber: Transcriber) {
        self.transcriber = transcriber
    }

    func handle(_ event: HotkeyMonitor.Event) {
        var step = Step()
        switch event {
        case .pressed:
            // Every press tries the microphone, even while an earlier
            // dictation is still transcribing.
            do {
                try capture.start()
            } catch {
                Log.error("capture failed: \(error)")
                step.error = error
            }
            perform(machine.pressed(captureStarted: step.error == nil), &step)
        case .locked:
            let conditions = DictationMachine.LockConditions(
                cardOpen: card?.isOpen == true,
                lockOpensCard: lockOpensCard(),
                canInsert: delivery.canInsert,
                liveText: liveText,
                routeChanged: capture.hasRouteChanged
            )
            perform(machine.locked(conditions), &step)
        case .released:
            releasedAt = CFAbsoluteTimeGetCurrent()
            perform(machine.released(), &step)
        case .cancelled:
            perform(machine.cancelled(), &step)
        }
    }

    /// The input route changed (a headset connected).
    func routeChanged() {
        var step = Step()
        perform(machine.routeChanged(), &step)
    }

    // MARK: Effects

    private func perform(_ effects: [DictationMachine.Effect], _ step: inout Step) {
        for effect in effects {
            switch effect {
            case .started:
                focusAtStart = focus.current()
                Log.info("● recording")
                observers.forEach { $0.dictationStarted() }
                let input = capture.recordingInput
                observers.forEach { $0.dictationInput(input) }
            case .locked:
                let live = machine.recording?.live
                Log.info("● locked\(live != nil ? " · live text" : "")\(effects.contains(.openCard) ? " · card" : "")")
                observers.forEach { $0.dictationLocked() }
            case .transcribing:
                observers.forEach { $0.dictationTranscribing() }
            case .finished:
                if let result = step.result {
                    observers.forEach { $0.dictationFinished(result) }
                }
            case .failed(let failure):
                fail(failure, step)
            case .abandonPress:
                onAbandonPress?()
            case .endLock(let reason):
                // The monitor answers with a release; let this event finish first.
                DispatchQueue.main.async { [weak self] in self?.onEndLock?(reason) }
            case .finishCapture(let keepBeforeRouteChange):
                finishCapture(keepBeforeRouteChange: keepBeforeRouteChange)
            case .stopCapture:
                capture.stop()
                focusAtStart = nil
            case .openCard:
                card?.open()
            case .startLive(let target):
                startLive(to: target)
            case .finishLive:
                finishLive(step)
            case .cancelLive:
                live?.cancel()
                step.stoppedLive = live
                live = nil
            case .awaitLive:
                let stopped = step.stoppedLive
                Task {
                    await stopped?.waitForSegments()
                    machine.liveCancelled()
                }
            case .transcribe:
                transcribe(step)
            case .scratchLast(let target):
                _ = target == .card ? card?.scratchLast() : delivery.scratchLast()
            case .deliver(let target):
                if target == .card, let card {
                    card.append(step.text)
                } else {
                    step.deliverAtCursor = true
                }
            case .remember:
                onTranscript?(step.text)
            }
        }
    }

    /// Tells observers why nothing reached the cursor.
    private func fail(_ failure: DictationMachine.Failure, _ step: Step) {
        let error: Error
        switch failure {
        case .noSpeech:
            if !step.samples.isEmpty { Log.info("  no speech; nothing transcribed") }
            // Through the Mac's microphone in place of playing headphones,
            // the user may be away from the Mac: say why, and the way out.
            error = capture.recordingInput.inPlaceOfHeadset && !step.samples.isEmpty
                ? MicrophoneNotice.macMicrophoneHeardNothing
                : DictationError.noAudio
        case .cancelled:
            Log.info("○ discarded")
            error = DictationError.cancelled
        case .notDelivered(let refused):
            error = refused
        case .captureFailedToStart, .captureLost, .transcriptionFailed:
            error = step.error ?? DictationError.noAudio
        }
        observers.forEach { $0.dictationFailed(error) }
    }

    private func finishCapture(keepBeforeRouteChange: Bool) {
        var step = Step(focus: focusAtStart)
        focusAtStart = nil
        do {
            step.samples = try capture.finish(keepBeforeRouteChange: keepBeforeRouteChange)
        } catch {
            // The route changed mid-recording: no partial capture is delivered.
            Log.error("capture failed: \(error)")
            step.error = error
            perform(machine.captured(.lost), &step)
            return
        }
        let samples = step.samples
        let seconds = Double(samples.count) / PauseSplitter.sampleRate
        Log.info(String(format: "○ captured %.2fs · rms %.3f", seconds, computeRMS(samples)))
        if dumpWav, !samples.isEmpty {
            writeDump(samples)
        }
        step.result = DictationResult(
            captureDuration: seconds,
            transcriptionTime: 0,
            charCount: 0,
            captureStop: CFAbsoluteTimeGetCurrent() - releasedAt,
            pressToFirstSample: capture.lastFirstSampleDelay
        )
        let hasSpeech = !samples.isEmpty && PauseSplitter.hasSpeech(samples, minRun: PauseSplitter.minPushToTalkRun)
        perform(machine.captured(.audio(hasSpeech: hasSpeech)), &step)
    }

    private func startLive(to target: DictationMachine.Target) {
        let toCard = target == .card ? card : nil
        let capture = self.capture
        let delivery = self.delivery
        let focus = focusAtStart
        let live = LiveTranscription(
            samples: { capture.samples(from: $0) },
            transcriber: transcriber,
            context: context(),
            processors: processors,
            deliver: { text in
                if let toCard { toCard.append(text) } else { try await delivery.deliver(text, focusAtStart: focus) }
            },
            scratch: { toCard?.scratchLast() ?? delivery.scratchLast() },
            copy: { delivery.copyToClipboard($0) },
            notice: { [weak self] error in
                self?.observers.forEach { $0.dictationNotice(error) }
            }
        )
        live.start()
        self.live = live
    }

    /// The end of a locked recording with live text: transcribe the tail,
    /// wait for every segment, and report the dictation as one.
    private func finishLive(_ step: Step) {
        guard let live else { return }
        self.live = nil
        let released = releasedAt
        Task {
            let outcome = await live.finish(capture: step.samples)
            Log.info(String(format: "→ live: %d segments · %.1fs audio · %.2fs transcribing · %d chars", outcome.segments, outcome.audio, outcome.transcribing, outcome.chars))
            var step = step
            step.text = outcome.text
            step.error = outcome.transcriptionError
            step.result?.transcriptionTime = outcome.transcribing
            step.result?.charCount = outcome.chars
            step.result?.transcriber = outcome.timings
            step.result?.releaseToText = CFAbsoluteTimeGetCurrent() - released
            let ending = DictationMachine.LiveEnding(
                chars: outcome.chars,
                deliveryError: outcome.deliveryError,
                transcriptionFailed: outcome.transcriptionError != nil
            )
            perform(machine.liveFinished(ending), &step)
        }
    }

    /// A push-to-talk recording: transcribe, process, deliver.
    private func transcribe(_ step: Step) {
        let transcriber = self.transcriber
        let context = self.context()
        let released = releasedAt
        Task {
            var step = step
            let started = CFAbsoluteTimeGetCurrent()
            let raw: Transcript
            do {
                // The transcriber is an actor; this await runs off the main actor.
                raw = try await transcriber.transcribe(step.samples, context: context)
            } catch {
                Log.error("transcription failed: \(error)")
                step.error = error
                perform(machine.transcriptionFailed(), &step)
                return
            }
            let transcribed = CFAbsoluteTimeGetCurrent()
            // Never log the transcript itself: the log is a file on disk.
            Log.info(String(format: "→ %.2fs · %d chars", transcribed - started, raw.text.count))
            let transcript = processors.reduce(raw) { $1.process($0) }
            let processed = CFAbsoluteTimeGetCurrent()
            step.text = transcript.text
            perform(machine.transcribed(scratchesPrevious: transcript.scratchesPrevious, cardOpen: card?.isOpen == true), &step)
            if step.deliverAtCursor {
                do {
                    try await delivery.deliver(step.text, focusAtStart: step.focus)
                } catch {
                    step.deliveryError = error as? DeliveryError
                }
            }
            let done = CFAbsoluteTimeGetCurrent()
            step.result?.transcriptionTime = transcribed - started
            step.result?.charCount = transcript.text.count
            step.result?.transcriber = raw.timings
            step.result?.processing = processed - transcribed
            step.result?.delivery = done - processed
            step.result?.releaseToText = done - released
            perform(machine.delivered(step.deliveryError), &step)
        }
    }

    private func writeDump(_ samples: [Float]) {
        do {
            try Paths.prepareDirectory(Paths.caches)
            let path = try Paths.preparePrivateFile(Paths.dumpWav).path
            try WAVWriter.write(samples: samples, sampleRate: 16_000, to: path)
            Log.info("  wrote \(path)")
        } catch {
            Log.error("  wav write failed: \(error)")
        }
    }
}
