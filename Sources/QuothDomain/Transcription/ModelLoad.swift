import Foundation

/// A model being downloaded or made ready behind the one in use, as the menu
/// and Settings › Model show it.
public struct ModelLoad: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        /// Fraction done, 0 to 1, once the download reports one.
        case downloading(Double?)
        case loading
        case failed
    }

    public var modelID: String
    public var phase: Phase

    public init(modelID: String, phase: Phase) {
        self.modelID = modelID
        self.phase = phase
    }

    /// For example "Downloading Large v3 Turbo… 42%".
    public var text: String {
        let name = ModelRegistry.find(modelID)?.name ?? modelID
        switch phase {
        case .downloading(let fraction?): return "Downloading \(name)… \(Int((fraction * 100).rounded(.down)))%"
        case .downloading(nil): return "Downloading \(name)…"
        case .loading: return "Getting \(name) ready…"
        case .failed: return "Couldn't load \(name). Check your connection and choose it again."
        }
    }

    /// Whether `next` should replace `current`: not when it reads the same
    /// (the menu needs whole percents only), and not a download's late
    /// progress report once the same model is already loading.
    public static func replaces(_ current: ModelLoad?, with next: ModelLoad) -> Bool {
        guard let current else { return true }
        if case .downloading = next.phase, current.modelID == next.modelID, current.phase == .loading { return false }
        return current.text != next.text
    }
}
