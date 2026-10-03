import Foundation

public enum Engine: String, Codable {
    case whisperKit
    case parakeet
}

public struct TranscriptionModel: Codable {
    public let id: String
    public let displayName: String
    public let engine: Engine
    /// Engine-specific identifier (e.g. "openai_whisper-base.en" for WhisperKit).
    public let whisperKitID: String?
    public let sizeMB: Int
    public let languages: [String]
    public let recommended: Bool
}

public struct ModelsManifest: Codable {
    public let models: [TranscriptionModel]
}
