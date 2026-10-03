import CoreML
import Foundation
import QuothDomain
import QuothPlatform
import WhisperKit

/// Whisper through WhisperKit, on the Neural Engine. Loads its model once
/// (downloading it first if needed) and transcribes in the language
/// `SpokenLanguage` plans, splitting a recording whose language detection
/// is unsure.
public actor WhisperKitTranscriber: Transcriber {
    public let modelID: String
    private let model: TranscriptionModel
    public let tuning: WhisperTuning
    private var pipeline: WhisperKit?
    /// Set by `unload`: this transcriber was replaced and loads nothing more.
    private var retired = false

    public init(model: TranscriptionModel, tuning: WhisperTuning = .standard) {
        self.modelID = model.id
        self.model = model
        self.tuning = tuning
    }

    /// Loads the model into memory; downloads first if not already on disk.
    /// Call once at startup so the first hotkey press isn't blocked on model
    /// download/load. `progress` gets the download's fraction done, 0 to 1,
    /// when there is anything to download.
    public func warmUp(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        if pipeline != nil || retired { return }
        Log.info("loading \(model.id)...")
        // Explicit downloadBase: the HubApi default is ~/Documents/huggingface,
        // which a login item can't always read and iCloud may evict. The
        // tokenizer folder follows downloadBase.
        let base = try Paths.prepareDirectory(Paths.appSupport)
        let files = ModelFiles(model, base: base)
        let loaded: WhisperKit
        // A model already on disk loads from there, with no network: the
        // download step lists the repository's files on Hugging Face even
        // when nothing needs fetching, so offline it would fail. If the local
        // copy doesn't load (an interrupted download), download and retry.
        if files.isComplete {
            do {
                loaded = try await Self.load(model.variant, from: files.weights, base: base, tuning: tuning)
            } catch {
                try Task.checkCancellation()
                Log.warning("\(model.id) on disk didn't load (\(error)); downloading it again")
                loaded = try await Self.downloadAndLoad(model.variant, base: base, tuning: tuning, progress: progress)
            }
        } else {
            loaded = try await Self.downloadAndLoad(model.variant, base: base, tuning: tuning, progress: progress)
        }
        // Replaced while loading (a model change during startup): drop it.
        if retired {
            await loaded.unloadModels()
            return
        }
        pipeline = loaded
        Log.info("✓ \(model.id) ready")
    }

    /// The same download WhisperKit's init would run, called here to see its
    /// progress, then the load. Files already on disk are not fetched again.
    private static func downloadAndLoad(
        _ variant: String, base: URL, tuning: WhisperTuning, progress: (@Sendable (Double) -> Void)?
    ) async throws -> WhisperKit {
        let folder = try await WhisperKit.download(variant: variant, downloadBase: base) { p in
            progress?(p.fractionCompleted)
        }
        try Task.checkCancellation()
        return try await load(variant, from: folder, base: base, tuning: tuning)
    }

    private static func load(_ variant: String, from folder: URL, base: URL, tuning: WhisperTuning) async throws -> WhisperKit {
        let config = WhisperKitConfig(
            model: variant,
            downloadBase: base,
            modelFolder: folder.path,
            computeOptions: ModelComputeOptions(
                melCompute: tuning.melCompute,
                audioEncoderCompute: tuning.encoderCompute,
                textDecoderCompute: tuning.decoderCompute
            ),
            verbose: false,
            prewarm: true,
            load: true,
            download: false
        )
        return try await WhisperKit(config)
    }

    /// Frees the model after a swap to another one. A load still running
    /// finishes and is dropped, and a later `warmUp` returns at once.
    public func unload() async {
        retired = true
        guard let pipeline else { return }
        self.pipeline = nil
        await pipeline.unloadModels()
    }

    /// Below this, detection over a whole recording suggests more than one
    /// language in it: one language decodes at about 1.00, and an English
    /// sentence followed by a Norwegian one at 0.77.
    public static let mixedConfidence: Float = 0.9

    /// Uses `context.language` and `context.prompt`, or with no language
    /// (Automatic) detects one and takes its sentence from `context.examples`;
    /// see `SpokenLanguage`. `context.vocabulary` is ignored: Whisper takes no
    /// word list, and a list given as a prompt scores no better than nothing.
    ///
    /// Whisper decodes in one language, and told the wrong one it translates.
    /// So when detection is unsure and the recording has pauses, each part
    /// between them is transcribed in its own language.
    public func transcribe(_ audio: [Float], context: TranscriptionContext) async throws -> Transcript {
        try await transcribe(audio, context: context, splitIfMixed: true)
    }

    private func transcribe(_ audio: [Float], context: TranscriptionContext, splitIfMixed: Bool) async throws -> Transcript {
        if pipeline == nil { try await warmUp() }
        guard let pipeline else { throw TranscriberError.notLoaded }

        let started = CFAbsoluteTimeGetCurrent()
        let input = tuning.prepare(audio)
        let trimTime = CFAbsoluteTimeGetCurrent() - started

        let detectStarted = CFAbsoluteTimeGetCurrent()
        let (language, prompt, confidence) = await chooseLanguage(input, context: context, pipeline: pipeline)
        let detectTime = confidence != nil ? CFAbsoluteTimeGetCurrent() - detectStarted : 0

        if splitIfMixed, let confidence, confidence < Self.mixedConfidence {
            let parts = PauseSplitter.parts(audio)
            if parts.count > 1 {
                Log.info("language unsure; transcribing \(parts.count) parts on their own")
                return try await transcribe(parts: parts, context: context)
            }
        }

        // The previous segment's text helps only in its own language.
        let continuing = context.previousLanguage == nil || context.previousLanguage == language ? context.previousText : nil
        let options = tuning.decodingOptions(
            language: language,
            promptTokens: WhisperText.tokens(for: WhisperText.prompt(prompt, continuing: continuing), tokenizer: pipeline.tokenizer),
            audioSeconds: Double(input.count) / Double(WhisperKit.sampleRate)
        )
        let results = try await pipeline.transcribe(audioArray: input, decodeOptions: options)
        let raw = results.map(\.text).joined(separator: " ")
        let text = WhisperText.clean(raw)
        var timings = TranscriberTimings(
            whisperKit: results.map(\.timings),
            audioSeconds: Double(input.count) / Double(WhisperKit.sampleRate),
            preprocessing: trimTime,
            languageDetection: detectTime,
            total: CFAbsoluteTimeGetCurrent() - started
        )
        timings.language = language ?? model.onlyLanguage
        return Transcript(text: text, timings: timings)
    }

    /// The parts of one recording, each in its own language and continuing
    /// the one before when the language matches, joined as live text joins
    /// its segments.
    private func transcribe(parts: [[Float]], context: TranscriptionContext) async throws -> Transcript {
        let started = CFAbsoluteTimeGetCurrent()
        var context = context
        var texts: [String] = []
        var last: Transcript?
        for part in parts {
            let transcript = try await transcribe(part, context: context, splitIfMixed: false)
            if !transcript.text.isEmpty {
                texts.append(transcript.text)
                context.previousText = transcript.text
            }
            context.previousLanguage = transcript.timings?.language
            last = transcript
        }
        var timings = last?.timings ?? TranscriberTimings()
        timings.total = CFAbsoluteTimeGetCurrent() - started
        return Transcript(text: LiveTextLedger.join(texts), timings: timings)
    }

    /// The language to decode `input` in, or nil for none; the prompt to go
    /// with it; and, when detection ran, how sure it was of its top language.
    /// Logs what detection heard and what was chosen, as codes, never text.
    private func chooseLanguage(
        _ input: [Float],
        context: TranscriptionContext,
        pipeline: WhisperKit
    ) async -> (language: String?, prompt: String?, confidence: Float?) {
        let spoken = context.spokenLanguages.isEmpty ? SpokenLanguage.preferredCodes() : context.spokenLanguages
        switch SpokenLanguage.plan(setting: context.language, spoken: spoken, model: model) {
        case .none:
            return (nil, context.prompt, nil)
        case .fixed(let code):
            // An explicit Language setting fills the prompt already; a single
            // spoken language comes here with it still unset.
            return (code, context.prompt ?? WhisperText.example(in: context.examples, for: code), nil)
        case .detect(let candidates):
            let among = candidates.isEmpty ? Array(model.supportedLanguages) : candidates
            let fallback = context.previousLanguage ?? candidates.first
            guard !input.isEmpty else { return (fallback, WhisperText.example(in: context.examples, for: fallback), nil) }
            do {
                let ranked = try await LanguageDetector.detect(input, among: among, pipeline: pipeline)
                let chosen = SpokenLanguage.choose(ranked, previous: context.previousLanguage) ?? ranked[0].code
                Log.info("language: \(chosen) (" + ranked.prefix(3).map {
                    String(format: "%@ %.2f", $0.code, $0.probability)
                }.joined(separator: " · ") + ")")
                return (chosen, WhisperText.example(in: context.examples, for: chosen), ranked[0].probability)
            } catch {
                Log.warning("language detection failed: \(error); using \(fallback ?? "the model's default")")
                return (fallback, WhisperText.example(in: context.examples, for: fallback), nil)
            }
        }
    }
}

public enum TranscriberError: Error {
    case notLoaded
}
