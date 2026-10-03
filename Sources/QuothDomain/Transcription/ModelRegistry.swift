import Foundation

/// The models Settings › Model offers, smallest English one first.
public enum ModelRegistry {
    public static let all: [TranscriptionModel] = [
        TranscriptionModel(
            id: "whisper-base.en", displayName: "Whisper Base (English)",
            variant: "openai_whisper-base.en", sizeMB: 145, hears: .only("en")
        ),
        TranscriptionModel(
            id: "whisper-large-v3-turbo", displayName: "Whisper Large v3 Turbo",
            variant: "openai_whisper-large-v3-v20240930_turbo", sizeMB: 1620, hears: .multilingual
        ),
        // The model above, compressed to about 40% of the size for very
        // little accuracy.
        TranscriptionModel(
            id: "whisper-large-v3-turbo-compressed", displayName: "Whisper Large v3 Turbo (compressed)",
            variant: "openai_whisper-large-v3-v20240930_turbo_632MB", sizeMB: 646, hears: .multilingual
        ),
        TranscriptionModel(
            id: "whisper-small.en", displayName: "Whisper Small (English)",
            variant: "openai_whisper-small.en", sizeMB: 488, hears: .only("en")
        ),
        TranscriptionModel(
            id: "whisper-small", displayName: "Whisper Small",
            variant: "openai_whisper-small", sizeMB: 490, hears: .multilingual
        ),
    ]

    /// What a new install uses: small, quick on any Apple silicon Mac, and
    /// English, which most people dictate in.
    public static let recommended = all[0]

    public static func find(_ id: String) -> TranscriptionModel? {
        all.first { $0.id == id }
    }
}
