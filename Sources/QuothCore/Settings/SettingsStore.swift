import Foundation
import QuothDomain
import QuothPlatform

/// `settings.json`: the one writer of it, and the one place its changes
/// come from, whether saved here or edited by hand (ADR-002).
///
/// A file that can't be used, half-way through a hand edit say, keeps the
/// last good settings; the problem is logged once, until it changes. A
/// change made meanwhile applies for the session but isn't saved over the
/// edit.
@MainActor
final class SettingsStore: ObservableObject {
    @Published private(set) var current = Settings()

    private let config: ConfigFile
    private let log: (String) -> Void
    private var observers: [(_ old: Settings, _ new: Settings) -> Void] = []
    private var watcher: ConfigFileWatcher?
    /// The problem last logged, so it isn't logged again.
    private var problem: String?

    var file: URL { config.url }

    init(file: URL = Paths.settingsFile, log: @escaping (String) -> Void = { Log.warning($0) }) {
        config = ConfigFile(file, maxBytes: 1 << 16)
        self.log = log
        if let loaded = load() { current = Self.fitted(loaded) }
    }

    /// Calls `handler` with the old and new settings after every change.
    func observe(_ handler: @escaping (_ old: Settings, _ new: Settings) -> Void) {
        observers.append(handler)
    }

    /// Applies `settings` and saves them.
    func write(_ settings: Settings) {
        guard !config.exists || load() != nil else {
            log("not saving \(file.lastPathComponent): it has a mistake; the change applies until Quoth quits")
            return apply(settings)
        }
        do {
            try save(settings)
        } catch {
            return log("couldn't save \(file.path): \(error.localizedDescription)")
        }
        apply(settings)
    }

    /// Changes some fields and saves.
    func update(_ change: (inout Settings) -> Void) {
        var next = current
        change(&next)
        write(next)
    }

    /// Writes the current settings if there is no file yet, so Open Config
    /// File has something to open.
    func createIfMissing() {
        guard !config.exists else { return }
        try? save(current)
    }

    /// Applies hand edits as they happen.
    func startWatching() {
        guard watcher == nil else { return }
        watcher = ConfigFileWatcher(config) { [weak self] in self?.reload() }
    }

    /// Reads the file again and applies it if it changed.
    func reload() {
        if let loaded = load() { apply(loaded) }
    }

    // MARK: -

    private func apply(_ settings: Settings) {
        let settings = Self.fitted(settings)
        guard settings != current else { return }
        let old = current
        current = settings
        for observer in observers { observer(old, settings) }
    }

    /// `settings` with a hotkey this edition can use: a key combination in
    /// the App Store edition, a modifier key in the direct one. A file from
    /// the other edition, or the default fn, gets this edition's default.
    nonisolated static func fitted(_ settings: Settings, shortcuts: Bool = Edition.hotkeyIsShortcut) -> Settings {
        var fitted = settings
        fitted.hotkey.key = settings.hotkey.key.usable(shortcuts: shortcuts)
        return fitted
    }

    /// The settings on disk, the defaults when there's no file, or nil when
    /// the file can't be used.
    private func load() -> Settings? {
        switch config.read() {
        case .missing:
            problem = nil
            return Settings()
        case .read(let data, _):
            do {
                let settings = try JSONDecoder().decode(Settings.self, from: data)
                problem = nil
                return settings
            } catch let error as DecodingError {
                return refuse("\(file.lastPathComponent) not loaded, \(Self.describe(error))")
            } catch {
                return refuse("couldn't read \(file.path): \(error.localizedDescription)")
            }
        case .refused(let reason):
            return refuse(reason)
        case .unchanged:
            return current
        }
    }

    private func refuse(_ reason: String) -> Settings? {
        if reason != problem {
            problem = reason
            log("\(reason); keeping the last good settings")
        }
        return nil
    }

    private func save(_ settings: Settings) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try config.write(encoder.encode(settings) + [0x0A])
        problem = nil
    }

    /// A decoding error as one line: the key path and what was wrong there.
    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .dataCorrupted(let context), .typeMismatch(_, let context), .valueNotFound(_, let context), .keyNotFound(_, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            let detail = (context.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey] as? String
                ?? context.debugDescription
            return path.isEmpty ? detail : "\(path): \(detail)"
        @unknown default:
            return "\(error)"
        }
    }
}
