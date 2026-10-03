import ArgumentParser
import CoreML
import Foundation
import QuothCore
import QuothDomain
import QuothPlatform
import QuothSpeech
import WhisperKit

/// `quoth-bench <folder>`: runs the model over a folder of recordings, as
/// the app would, and prints each transcription stage's median and p90 per
/// file, the word error rate where a `.txt` says what was said, and which
/// languages were heard. How `WhisperTuning` was chosen. Prints timings,
/// counts and rates, never transcript text. Not part of Quoth.app.
@main
struct Bench: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "quoth-bench",
        abstract: "Time the model over a folder of recordings: median and p90 per stage."
    )

    @Argument(help: "A folder of .wav recordings, each with an optional .txt of what was said.") var folder: String
    @Option(help: "Timed runs per file.") var runs = 10
    @Option(help: "A model id; the recommended model by default.") var model: String?
    @Option(help: "Prompt text instead of the dictionary's example sentence.") var prompt: String?
    @Flag(help: "No prompt at all.") var noPrompt = false
    @Option(help: "The Language setting: a code, or none for Automatic.") var language: String?
    @Option(help: "The languages Automatic chooses among, comma-separated; the Mac's by default.") var spoken: String?
    @Flag(help: "WhisperKit's defaults, as Quoth ran before tuning.") var baseline = false
    @Option(help: "Compute units for the audio encoder: ane, gpu, cpu or all.") var encoder: String?
    @Option(help: "Compute units for the text decoder: ane, gpu, cpu or all.") var decoder: String?
    @Option(help: "Trim silence: true or false.") var trim: Bool?
    @Option(help: "Seconds of silence before the audio, after the trim.") var leadPad: Double?
    @Option(help: "Seconds of silence after the audio, after the trim.") var trailPad: Double?

    func validate() throws {
        guard runs > 0 else { throw ValidationError("--runs must be at least 1") }
        for (flag, name) in [("--encoder", encoder), ("--decoder", decoder)] where name.map(Self.units) == .some(nil) {
            throw ValidationError("\(flag): expected ane, gpu, cpu or all")
        }
    }

    func run() async throws {
        let model = try chosenModel()
        let tuning = tuned()
        let recordings = try Recording.all(in: folder)
        guard !recordings.isEmpty else { throw ValidationError("no .wav files in \(folder)") }
        let (context, promptLabel) = transcriptionContext(for: model)

        let transcriber = WhisperKitTranscriber(model: model, tuning: tuning)
        try await transcriber.warmUp()
        let languageLabel = model.isMultilingual ? (context.language ?? "automatic") : "\(model.onlyLanguage ?? "-") (model)"
        print("model \(model.id) · \(baseline ? "baseline" : "standard") tuning · \(Self.describe(tuning)) · language \(languageLabel) · prompt \(promptLabel)")
        print("\(recordings.count) files · \(runs) runs each · ms, median/p90")

        // The first transcription after a load pays for Core ML's first
        // prediction: reported, and kept out of the medians.
        let first = try await transcriber.transcribe(try Self.audio(recordings[0]), context: context)
        print(String(format: "first transcription after load: %.0f ms\n", (first.timings?.total ?? 0) * 1000))
        print(Self.header)

        var tally = Tally()
        for recording in recordings {
            let audio = try Self.audio(recording)
            var timings: [TranscriberTimings] = []
            var wer: WordErrorRate?
            for _ in 0..<runs {
                let transcript = try await transcriber.transcribe(audio, context: context)
                let t = transcript.timings ?? .zero
                timings.append(t)
                tally.add(t)
                // Accuracy is the same every run; score the first.
                if wer == nil, let said = recording.reference {
                    wer = WordErrorRate(reference: said, hypothesis: transcript.text)
                    tally.add(wer!, firstWord: FirstWord.recalled(reference: said, hypothesis: transcript.text))
                }
            }
            print(Self.row(recording.audio.lastPathComponent, seconds: Double(audio.count) / 16_000, timings, wer))
        }
        print(tally.summary)
    }

    // MARK: Setting up

    private func chosenModel() throws -> TranscriptionModel {
        guard let model = model.map(ModelRegistry.find) ?? ModelRegistry.recommended else {
            throw ValidationError("unknown model: \(model ?? "")")
        }
        guard ModelFiles(model).isDownloaded else {
            throw ValidationError("\(model.id) is not downloaded; choose it in Quoth's Settings › Model to download it")
        }
        return model
    }

    private func tuned() -> WhisperTuning {
        var tuning = baseline ? WhisperTuning.baseline : WhisperTuning.standard
        if let units = encoder.flatMap(Self.units) { tuning.encoderCompute = units }
        if let units = decoder.flatMap(Self.units) { tuning.decoderCompute = units }
        if let trim { tuning.trimSilence = trim }
        if let leadPad { tuning.leadPadding = leadPad }
        if let trailPad { tuning.trailPadding = trailPad }
        return tuning
    }

    /// The context the app would give the model: the dictionary's words and
    /// example sentences, unless --prompt or --no-prompt says otherwise.
    private func transcriptionContext(for model: TranscriptionModel) -> (TranscriptionContext, String) {
        let language = DictionaryContext.language(of: model, setting: language)
        var context = DictionaryContext(store: DictionaryStore(), language: language, examples: DictionaryContext.savedExamples()).context()
        context.spokenLanguages = spoken?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
        // In Automatic the prompt comes from `examples` once the language is
        // detected, so --prompt and --no-prompt set those too.
        if noPrompt {
            context.prompt = nil
            context.examples = [:]
        }
        if let prompt {
            context.prompt = prompt
            context.examples = language == nil ? Dictionary(uniqueKeysWithValues: model.supportedLanguages.map { ($0, prompt) }) : [:]
        }
        let label = context.prompt.map { "\($0.split(separator: " ").count) words" }
            ?? (context.examples.isEmpty ? "none" : "the example for the detected language")
        return (context, label)
    }

    private static func audio(_ recording: Recording) throws -> [Float] {
        try AudioProcessor.loadAudioAsFloatArray(fromPath: recording.audio.path)
    }

    // MARK: Compute units

    private static let unitNames: [(String, MLComputeUnits)] = [
        ("ane", .cpuAndNeuralEngine), ("gpu", .cpuAndGPU), ("cpu", .cpuOnly), ("all", .all),
    ]

    static func units(_ name: String) -> MLComputeUnits? { unitNames.first { $0.0 == name }?.1 }
    static func name(_ units: MLComputeUnits) -> String { unitNames.first { $0.1 == units }?.0 ?? "?" }

    static func describe(_ tuning: WhisperTuning) -> String {
        var parts = ["mel \(name(tuning.melCompute))", "encoder \(name(tuning.encoderCompute))", "decoder \(name(tuning.decoderCompute))"]
        if tuning.withoutTimestamps { parts.append("no timestamps") }
        if tuning.trimSilence { parts.append("trim") }
        if tuning.leadPadding > 0 { parts.append(String(format: "lead pad %.2f s", tuning.leadPadding)) }
        if tuning.trailPadding > 0 { parts.append(String(format: "trail pad %.2f s", tuning.trailPadding)) }
        return parts.joined(separator: " · ")
    }

    // MARK: Report

    static let header = "file                     audio  total      pre      enc      dec        post    tokens  win  fb   WER"

    /// One file's line: each stage's median/p90 over its runs.
    static func row(_ name: String, seconds: Double, _ runs: [TranscriberTimings], _ wer: WordErrorRate?) -> String {
        func stage(_ key: KeyPath<TranscriberTimings, TimeInterval>, width: Int) -> String {
            let ms = runs.map { $0[keyPath: key] * 1000 }
            return String(format: "%.0f/%.0f", Percentile.of(ms, 50), Percentile.of(ms, 90)).padding(toLength: width, withPad: " ", startingAt: 0)
        }
        let tokens = Percentile.of(runs.map { Double($0.tokens) }, 50)
        let windows = Percentile.of(runs.map { Double($0.windows) }, 50)
        return name.padding(toLength: 24, withPad: " ", startingAt: 0)
            + String(format: "%5.1fs  ", seconds)
            + stage(\.total, width: 11) + stage(\.preprocessing, width: 9) + stage(\.encoder, width: 9)
            + stage(\.decoder, width: 11) + stage(\.postprocessing, width: 8)
            + String(format: "%6.0f %4.0f %3d  ", tokens, windows, runs.map(\.fallbacks).reduce(0, +))
            + (wer.map { String(format: "%5.1f%%", $0.rate * 100) } ?? "     -")
    }

    /// What every file adds up to.
    struct Tally {
        var errors = 0
        var words = 0
        var firstWords = (recalled: 0, of: 0)
        var totals: [Double] = []
        var detections: [Double] = []
        var languages: [String: Int] = [:]

        mutating func add(_ t: TranscriberTimings) {
            totals.append(t.total * 1000)
            languages[t.language ?? "-", default: 0] += 1
            if t.languageDetection > 0 { detections.append(t.languageDetection * 1000) }
        }

        mutating func add(_ wer: WordErrorRate, firstWord: Bool) {
            errors += wer.errors
            words += wer.referenceWords
            firstWords.of += 1
            if firstWord { firstWords.recalled += 1 }
        }

        var summary: String {
            var lines = [""]
            if words > 0 { lines.append(String(format: "WER %.1f%% (%d errors / %d words)", 100 * Double(errors) / Double(words), errors, words)) }
            if firstWords.of > 0 {
                lines.append(String(format: "first word %d/%d (%.1f%%)", firstWords.recalled, firstWords.of, 100 * Double(firstWords.recalled) / Double(firstWords.of)))
            }
            lines.append(String(format: "total ms over all files: median %.0f, p90 %.0f", Percentile.of(totals, 50), Percentile.of(totals, 90)))
            if !detections.isEmpty {
                lines.append(String(format: "language detection ms: median %.0f, p90 %.0f", Percentile.of(detections, 50), Percentile.of(detections, 90)))
            }
            lines.append("languages: " + languages.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
            return lines.joined(separator: "\n")
        }
    }
}
