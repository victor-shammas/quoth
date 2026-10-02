import Foundation

/// The dictation loop: gesture → capture → transcribe → process → deliver.
///
/// Owns the state machine and nothing else. Features plug in as a
/// `TranscriptProcessor` (after transcription, before delivery) or a
/// `DictationObserver` (reacting to the loop), not as branches here.
///
/// Edge cases, kept exactly as the loop behaved before this type existed:
/// - A press always tries to start capture, even while an earlier capture is
///   still transcribing. That transcription still delivers, and its
///   `dictationFinished` reaches observers while the new recording runs.
/// - A press whose capture fails to start logs and notifies `dictationFailed`
///   with the capture error; the state does not change.
/// - A release always stops capture and notifies `dictationTranscribing`,
///   even with nothing recorded; an empty capture then fails with
///   `DictationError.noAudio`.
/// - A transcript that does not reach the cursor (a secure field, or focus
///   moved since the press) fails with its `DeliveryError`.
@MainActor
final class DictationController {
    enum State: Equatable {
        case idle
        case recording
        case transcribing
    }

    private(set) var state: State = .idle

    private let capture: AudioCapture
    /// Replaced by `replaceTranscriber` when the model changes (#43).
    private var transcriber: Transcriber
    private let processors: [TranscriptProcessor]
    private let observers: [DictationObserver]
    private let dumpWav: Bool
    private let delivery: TextDelivery
    /// What to tell the transcriber about each dictation, asked once per
    /// release. Features such as the dictionary fill it; the controller only
    /// passes it on.
    private let context: @MainActor () -> TranscriptionContext
    /// Transcriptions started and not yet finished or failed.
    private var inFlight = 0
    /// What had focus when the current recording started (#38).
    private var focusAtStart: FocusSnapshot?
    /// Whether a locked recording types text at each pause (fork addition).
    var liveText = true
    /// Live text for the current locked recording, if any.
    private var live: LiveTranscription?
    /// Whether the current recording is locked on.
    private(set) var isLocked = false
    /// Each finished transcript, for Copy and Fix Last Dictation
    /// (`LastDictation`, memory only). Not called for a password field.
    /// Observers never see text; this is the one place it leaves.
    var onTranscript: ((String) -> Void)?

    init(
        capture: AudioCapture,
        transcriber: Transcriber,
        processors: [TranscriptProcessor] = [],
        observers: [DictationObserver],
        dumpWav: Bool = false,
        delivery: TextDelivery,
        context: @escaping @MainActor () -> TranscriptionContext = { TranscriptionContext() }
    ) {
        self.capture = capture
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
        switch event {
        case .pressed: press()
        case .released: release()
        case .cancelled: cancel()
        case .locked: lock()
        }
    }

    /// A double tap locked the recording on; capture carries on unchanged.
    /// With live text on, segments are transcribed and typed at each pause.
    func lock() {
        guard state == .recording else { return }
        isLocked = true
        // Live text types as it goes; a build that can only copy collects
        // the whole lock and copies it once at the end.
        let live = liveText && delivery.canInsert
        Log.info("● locked\(live ? " · live text" : "")")
        if live {
            let capture = self.capture
            let delivery = self.delivery
            let focus = focusAtStart
            let live = LiveTranscription(
                samples: { capture.samples(from: $0) },
                transcriber: transcriber,
                context: context(),
                processors: processors,
                deliver: { try delivery.deliver($0, focusAtStart: focus) },
                copy: { delivery.copyToClipboard($0) },
                notice: { [weak self] error in
                    self?.observers.forEach { $0.dictationNotice(error) }
                }
            )
            live.start()
            self.live = live
        }
        observers.forEach { $0.dictationLocked() }
    }

    func press() {
        do {
            try capture.start()
        } catch {
            Log.error("capture failed: \(error)")
            observers.forEach { $0.dictationFailed(error) }
            return
        }
        focusAtStart = FocusSnapshot.capture()
        Log.info("● recording")
        state = .recording
        observers.forEach { $0.dictationStarted() }
    }

    func release() {
        let released = CFAbsoluteTimeGetCurrent()
        // A locked recording keeps what came before a microphone change.
        let wasLocked = isLocked
        isLocked = false
        let samples: [Float]
        do {
            samples = try capture.finish(keepBeforeRouteChange: wasLocked)
        } catch {
            // The route changed mid-recording: no partial capture is delivered.
            Log.error("capture failed: \(error)")
            live?.cancel()
            live = nil
            focusAtStart = nil
            state = inFlight > 0 ? .transcribing : .idle
            observers.forEach { $0.dictationFailed(error) }
            return
        }
        let captureStop = CFAbsoluteTimeGetCurrent() - released
        let pressToFirstSample = capture.lastStats?.firstSampleDelay
        let focus = focusAtStart
        focusAtStart = nil
        state = .transcribing
        observers.forEach { $0.dictationTranscribing() }

        let seconds = Double(samples.count) / AudioCapture.targetSampleRate
        Log.info(String(format: "○ captured %.2fs · rms %.3f", seconds, computeRMS(samples)))
        if dumpWav, !samples.isEmpty {
            writeDump(samples)
        }

        if let live {
            self.live = nil
            finishLive(live, samples: samples, seconds: seconds, captureStop: captureStop, released: released, pressToFirstSample: pressToFirstSample)
            return
        }

        guard !samples.isEmpty else {
            settle()
            observers.forEach { $0.dictationFailed(DictationError.noAudio) }
            return
        }

        inFlight += 1
        let transcriber = self.transcriber
        let context = self.context()
        Task {
            let started = CFAbsoluteTimeGetCurrent()
            do {
                // The transcriber is an actor; this await runs off the main actor.
                let raw = try await transcriber.transcribe(samples, context: context)
                let transcribed = CFAbsoluteTimeGetCurrent()
                let elapsed = transcribed - started
                // Never log the transcript itself: the agent's log is a file on disk.
                Log.info(String(format: "→ %.2fs · %d chars", elapsed, raw.text.count))
                let transcript = processors.reduce(raw) { $1.process($0) }
                let processed = CFAbsoluteTimeGetCurrent()
                let delivered = Result { try delivery.deliver(transcript.text, focusAtStart: focus) }
                if case .failure(DeliveryError.secureField) = delivered {} else {
                    onTranscript?(transcript.text)
                }
                let done = CFAbsoluteTimeGetCurrent()
                inFlight -= 1
                settle()
                if case .failure(let error) = delivered {
                    observers.forEach { $0.dictationFailed(error) }
                    return
                }
                let result = DictationResult(
                    captureDuration: seconds,
                    transcriptionTime: elapsed,
                    charCount: transcript.text.count,
                    captureStop: captureStop,
                    transcriber: raw.timings,
                    processing: processed - transcribed,
                    delivery: done - processed,
                    releaseToText: done - released,
                    pressToFirstSample: pressToFirstSample
                )
                observers.forEach { $0.dictationFinished(result) }
            } catch {
                Log.error("transcription failed: \(error)")
                inFlight -= 1
                settle()
                observers.forEach { $0.dictationFailed(error) }
            }
        }
    }

    /// The gesture discarded this recording (a short tap, a chord, or a
    /// hotkey switch): stop capture and transcribe nothing.
    func cancel() {
        guard state == .recording else { return }
        capture.stop()
        isLocked = false
        live?.cancel()
        live = nil
        focusAtStart = nil
        state = inFlight > 0 ? .transcribing : .idle
        Log.info("○ discarded")
        observers.forEach { $0.dictationFailed(DictationError.cancelled) }
    }

    /// The end of a locked recording with live text: transcribe the tail,
    /// wait for every segment, and report the dictation as one.
    private func finishLive(
        _ live: LiveTranscription,
        samples: [Float],
        seconds: TimeInterval,
        captureStop: TimeInterval,
        released: CFAbsoluteTime,
        pressToFirstSample: TimeInterval?
    ) {
        inFlight += 1
        Task {
            let outcome = await live.finish(capture: samples)
            if (outcome.deliveryError as? DeliveryError) != .secureField {
                onTranscript?(outcome.text)
            }
            inFlight -= 1
            settle()
            Log.info(String(format: "→ live: %d segments · %.1fs audio · %.2fs transcribing · %d chars", outcome.segments, outcome.audio, outcome.transcribing, outcome.chars))
            if let error = outcome.deliveryError {
                observers.forEach { $0.dictationFailed(error) }
                return
            }
            guard outcome.chars > 0 else {
                let error = outcome.transcriptionError ?? DictationError.noAudio
                observers.forEach { $0.dictationFailed(error) }
                return
            }
            let result = DictationResult(
                captureDuration: seconds,
                transcriptionTime: outcome.transcribing,
                charCount: outcome.chars,
                captureStop: captureStop,
                transcriber: outcome.timings,
                releaseToText: CFAbsoluteTimeGetCurrent() - released,
                pressToFirstSample: pressToFirstSample
            )
            observers.forEach { $0.dictationFinished(result) }
        }
    }

    /// After a transcription ends, return to idle unless a newer recording
    /// or transcription is still running.
    private func settle() {
        if state == .transcribing, inFlight == 0 {
            state = .idle
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
