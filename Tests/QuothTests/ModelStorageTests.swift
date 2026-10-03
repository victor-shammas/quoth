import XCTest
@testable import QuothCore
@testable import QuothDomain
@testable import QuothPlatform
@testable import QuothSpeech

/// Measuring and deleting a downloaded model, in a temporary folder that
/// stands in for Application Support.
final class ModelStorageTests: XCTestCase {
    private var base: URL!
    private let model = ModelRegistry.find("whisper-large-v3-turbo-compressed")!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let repo = "models/argmaxinc/whisperkit-coreml"
        let variant = try XCTUnwrap(model.variant)
        try write(100_000, to: "\(repo)/\(variant)/AudioEncoder.mlmodelc/weights.bin")
        try write(2_000, to: "\(repo)/.cache/huggingface/download/\(variant)/meta")
        try write(500, to: "models/openai/whisper-large-v3/tokenizer.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    private func write(_ bytes: Int, to path: String) throws {
        let url = base.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: bytes).write(to: url)
    }

    func testSizeCountsWeightsAndMetadata() throws {
        let bytes = try XCTUnwrap(WhisperKitTranscriber.diskBytes(model, base: base))
        XCTAssertGreaterThanOrEqual(bytes, 102_000)
        XCTAssertNil(WhisperKitTranscriber.diskBytes(ModelRegistry.find("whisper-small")!, base: base))
    }

    func testDeleteRemovesTheModelButKeepsTheSharedTokenizer() throws {
        try WhisperKitTranscriber.deleteDownload(model, base: base)
        XCTAssertNil(WhisperKitTranscriber.diskBytes(model, base: base))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: base.appendingPathComponent("models/openai/whisper-large-v3/tokenizer.json").path))
        // Deleting what isn't there is fine.
        XCTAssertNoThrow(try WhisperKitTranscriber.deleteDownload(model, base: base))
    }
}
