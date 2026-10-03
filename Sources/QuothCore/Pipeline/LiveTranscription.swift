import Foundation
import QuothDomain
import QuothPlatform

/// Live text for a locked recording: while recording runs, each segment
/// `PauseSplitter` cuts off is transcribed and delivered, in order, so text
/// appears at every pause instead of all at the end.
///
/// One instance per lock. `DictationSession` starts it when a recording
/// locks and hands it the whole capture when the lock ends; it then
/// transcribes what is left and waits for every segment.
///
/// Each segment is transcribed with the end of the previous one as context,
/// so a sentence cut at a pause carries on. With Language on Automatic each
/// segment's language is detected anew, so a bilingual speaker's next
/// sentence is heard in its own language rather than translated; an unsure
/// detection keeps the previous segment's (`SpokenLanguage.choose`).
///
/// What happens to each segment's text is `LiveTextLedger`'s call. A
/// delivery failure and a segment that fails to transcribe are reported at
/// once through `notice`.
@MainActor
final class LiveTranscription {
    /// How often the recording is checked for a pause.
    static let pollInterval: TimeInterval = 0.25

    struct Outcome {
        /// Everything transcribed, typed or held, for Copy Last Dictation.
        var text = ""
        var chars = 0
        var segments = 0
        /// Seconds of audio transcribed.
        var audio: TimeInterval = 0
        /// Seconds the transcriber took, over all segments.
        var transcribing: TimeInterval = 0
        /// The last segment's breakdown.
        var timings: TranscriberTimings?
        /// The first delivery failure, which stops typing.
        var deliveryError: DeliveryError?
        /// The last transcription failure. Other segments still deliver.
        var transcriptionError: Error?
    }

    /// The capture's samples from an offset on.
    private let samples: (Int) -> [Float]
    private let transcriber: Transcriber
    private var context: TranscriptionContext
    private let processors: [TranscriptProcessor]
    /// Delivers at the cursor; throws `DeliveryError`.
    private let deliver: (String) throws -> Void
    /// Leaves text on the clipboard.
    private let copy: (String) -> Void
    /// Removes the last thing delivered ("scratch that").
    private let scratch: () -> Bool
    /// Reports a problem while recording continues.
    private let notice: (Error) -> Void

    /// Samples already cut into segments.
    private(set) var committed = 0
    private var chain: Task<Void, Never>?
    private var timer: Timer?
    private var ledger = LiveTextLedger()
    private var stats = Outcome()
    private var cancelled = false
    /// When the last segment was delivered. Pastes closer together than
    /// the clipboard's settle time could land out of order.
    private var lastDelivery: CFAbsoluteTime?
    static let minimumGap = TextInjector.settleDelay + 0.05

    init(
        samples: @escaping (Int) -> [Float],
        transcriber: Transcriber,
        context: TranscriptionContext,
        processors: [TranscriptProcessor],
        deliver: @escaping (String) throws -> Void,
        scratch: @escaping () -> Bool = { false },
        copy: @escaping (String) -> Void,
        notice: @escaping (Error) -> Void = { _ in }
    ) {
        self.samples = samples
        self.transcriber = transcriber
        self.context = context
        self.processors = processors
        self.deliver = deliver
        self.scratch = scratch
        self.copy = copy
        self.notice = notice
    }

    func start() {
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Cuts off a segment if the audio since the last one reached a pause.
    func poll() {
        guard !cancelled else { return }
        let pending = samples(committed)
        guard let cut = PauseSplitter.cut(pending) else { return }
        committed += cut.end
        if cut.hasSpeech {
            enqueue(Array(pending[..<cut.end]))
        }
    }

    /// The lock ended: transcribe what is left of `capture` (the whole
    /// recording) and wait for every segment.
    func finish(capture: [Float]) async -> Outcome {
        stopTimer()
        if committed < capture.count {
            let tail = Array(capture[committed...])
            if PauseSplitter.hasSpeech(tail) { enqueue(tail) }
            committed = capture.count
        }
        await chain?.value
        if let held = ledger.heldText {
            copy(held)
        }
        var outcome = stats
        outcome.text = ledger.text
        outcome.chars = ledger.chars
        outcome.deliveryError = ledger.deliveryError
        return outcome
    }

    /// Waits for the segments cut so far.
    func waitForSegments() async {
        await chain?.value
    }

    /// The recording was discarded: deliver nothing more.
    func cancel() {
        cancelled = true
        stopTimer()
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    /// Segments run one after another, so text arrives in order.
    private func enqueue(_ audio: [Float]) {
        let previous = chain
        chain = Task { [weak self] in
            await previous?.value
            await self?.process(audio)
        }
    }

    private func process(_ audio: [Float]) async {
        guard !cancelled else { return }
        let seconds = Double(audio.count) / PauseSplitter.sampleRate
        let started = CFAbsoluteTimeGetCurrent()
        let raw: Transcript
        do {
            raw = try await transcriber.transcribe(audio, context: context)
        } catch {
            Log.error("live segment failed: \(error)")
            stats.transcriptionError = error
            if !cancelled { notice(LiveTextNotice.segmentFailed) }
            return
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - started
        stats.segments += 1
        stats.audio += seconds
        stats.transcribing += elapsed
        stats.timings = raw.timings
        // The next segment continues this one when it is in the same language.
        if !raw.text.isEmpty { context.previousText = raw.text }
        context.previousLanguage = raw.timings?.language
        let processed = processors.reduce(raw) { $1.process($0) }
        let text = processed.text
        // Never log the text itself.
        Log.info(String(format: "→ live segment %.1fs · %.2fs · %d chars", seconds, elapsed, text.count))
        guard !cancelled else { return }
        // "scratch that" removes the segment before this one, typed or held.
        if processed.scratchesPrevious, ledger.scratch(), scratch() {
            ledger.scratched()
        }
        guard ledger.add(text) else { return }

        if let last = lastDelivery {
            let wait = Self.minimumGap - (CFAbsoluteTimeGetCurrent() - last)
            if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
            guard !cancelled else { return }
        }
        lastDelivery = CFAbsoluteTimeGetCurrent()
        do {
            try deliver(text)
            ledger.delivered(text)
        } catch {
            ledger.deliveryFailed(text, error: error as? DeliveryError)
            notice(error)
        }
    }
}
