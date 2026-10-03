import Foundation
import QuothDomain
import QuothPlatform

/// One model's files under `base` (`Paths.appSupport`), where WhisperKit
/// downloads them: the weights, their download metadata, and the tokenizer.
/// The tokenizer is shared (every large-v3 build uses one), so deleting a
/// model leaves it.
public struct ModelFiles {
    public let model: TranscriptionModel
    public let base: URL

    public init(_ model: TranscriptionModel, base: URL = Paths.appSupport) {
        self.model = model
        self.base = base
    }

    private static let repository = "models/argmaxinc/whisperkit-coreml"

    var weights: URL { base.appendingPathComponent("\(Self.repository)/\(model.variant)") }
    var metadata: URL { base.appendingPathComponent("\(Self.repository)/.cache/huggingface/download/\(model.variant)") }
    var tokenizer: URL { base.appendingPathComponent("models/openai/\(tokenizerName)") }

    /// WhisperKit's tokenizer for the variant: "openai_whisper-base.en" uses
    /// "whisper-base.en", and every large-v3 build, turbo included,
    /// "whisper-large-v3".
    private var tokenizerName: String {
        let name = model.variant.replacingOccurrences(of: "openai_", with: "")
        return name.hasPrefix("whisper-large-v3") ? "whisper-large-v3" : name
    }

    /// Whether the weights have been downloaded, whole or not.
    public var isDownloaded: Bool { FileManager.default.fileExists(atPath: weights.path) }

    /// Whether everything a load needs is here, so it can load with no
    /// network: the three Core ML models and the tokenizer.
    public var isComplete: Bool {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: weights.path) else { return false }
        let models = ["AudioEncoder.mlmodelc", "TextDecoder.mlmodelc", "MelSpectrogram.mlmodelc"]
        return models.allSatisfy(contents.contains)
            && FileManager.default.fileExists(atPath: tokenizer.appendingPathComponent("tokenizer.json").path)
    }

    /// The space the weights and their metadata take, as Finder counts it,
    /// or nil when the model isn't downloaded.
    public var bytes: Int64? {
        guard isDownloaded else { return nil }
        return Self.allocatedBytes(under: weights) + Self.allocatedBytes(under: metadata)
    }

    /// Deletes the weights and their metadata, so the model downloads again
    /// when chosen.
    public func delete() throws {
        for folder in [weights, metadata] where FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
        Log.info("deleted \(model.id)")
    }

    private static func allocatedBytes(under url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in files {
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
