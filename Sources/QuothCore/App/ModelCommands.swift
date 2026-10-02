import Foundation

/// Behind `quoth models list`, `quoth models download <id>` and
/// `quoth models remove <id>`.
public enum ModelCommands {
    public static func list() {
        // Column width follows the longest id: `padding(toLength:)` truncates
        // a longer string, and a truncated id cannot be copied into
        // `quoth models download`.
        let width = max(26, ModelRegistry.shared.map(\.id.count).max() ?? 0)
        for m in ModelRegistry.shared {
            let star = m.recommended ? "★" : " "
            let id = m.id.padding(toLength: width, withPad: " ", startingAt: 0)
            let langs = "[\(m.languages.joined(separator: ","))]"
                .padding(toLength: 9, withPad: " ", startingAt: 0)
            let size = String(format: "%5d MB", m.sizeMB)
            let here = WhisperKitTranscriber.isCached(m) ? "  · on this Mac" : ""
            print("\(star) \(id) \(size)  \(langs)  \(m.displayName)\(here)")
        }
    }

    public static func download(_ id: String) throws {
        guard let m = ModelRegistry.find(id) else {
            print("unknown model: \(id)")
            throw SilentExit(1)
        }
        let t = WhisperKitTranscriber(model: m)

        let sem = DispatchSemaphore(value: 0)
        var capturedError: Error?
        Task.detached {
            do { try await t.warmUp() } catch { capturedError = error }
            sem.signal()
        }
        sem.wait()
        if let e = capturedError { throw e }
    }

    /// Deletes a downloaded model; it downloads again when chosen.
    public static func remove(_ id: String) throws {
        guard let m = ModelRegistry.find(id) else {
            print("unknown model: \(id)")
            throw SilentExit(1)
        }
        guard let bytes = WhisperKitTranscriber.diskBytes(m) else {
            print("\(id) is not downloaded")
            return
        }
        try WhisperKitTranscriber.deleteDownload(m)
        print("✓ deleted \(id) (\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)))")
    }
}
