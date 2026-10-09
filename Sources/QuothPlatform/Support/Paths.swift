import Foundation

/// Where Quoth keeps files on disk. User-authored config lives in
/// ~/.config/quoth; everything else lives under ~/Library. Never /tmp or
/// ~/Documents. Directories are owner-only (0700).
public enum Paths {
    /// `$XDG_CONFIG_HOME/quoth`, default `~/.config/quoth` — the files a user
    /// edits and may keep in dotfiles: settings and the dictionary.
    public static var config: URL {
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], xdg.hasPrefix("/") {
            return URL(fileURLWithPath: xdg, isDirectory: true).appendingPathComponent("quoth", isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/quoth", isDirectory: true)
    }

    /// `~/Library/Application Support/quoth` — model weights and tokenizers.
    /// Not Caches: the system purges that under disk pressure, which would
    /// mean a surprise multi-GB download.
    public static var appSupport: URL { library("Application Support/quoth") }

    /// `~/Library/Logs/quoth` — the app's stdout/stderr.
    public static var logs: URL { library("Logs/quoth") }

    /// `~/Library/Caches/quoth` — debug output such as `QUOTH_DUMP_WAV`'s.
    public static var caches: URL { library("Caches/quoth") }

    /// `settings.json` in `config`: preferences, read and written by `SettingsStore`.
    public static var settingsFile: URL { config.appendingPathComponent("settings.json") }

    /// `dictionary` in `config`: the user's words and what each replaces, a
    /// plain-text table. No extension, so it reads as a name, not a format.
    public static var dictionaryFile: URL { config.appendingPathComponent("dictionary") }

    /// The app's stdout.
    public static var outLog: URL { logs.appendingPathComponent("quoth.out.log") }

    /// The app's stderr.
    public static var errLog: URL { logs.appendingPathComponent("quoth.err.log") }

    /// Where `QUOTH_DUMP_WAV=1` writes the most recent capture.
    public static var dumpWav: URL { caches.appendingPathComponent("last-capture.wav") }

    /// The volume `OutputFader` faded from, while it is faded: if Quoth quits
    /// before fading back up, the next launch restores it.
    public static var fadedVolume: URL { appSupport.appendingPathComponent("faded-volume.json") }

    /// Held with `flock` by the running dictation loop, so two copies of
    /// Quoth never both listen to the hotkey. In Application Support, not
    /// Caches, which the system may clear.
    public static var instanceLock: URL { appSupport.appendingPathComponent("quoth.lock") }

    /// `~/Documents`. The model cache must not resolve under it.
    public static var documents: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
    }

    /// Creates `dir` if needed and restricts it to the owner. Refuses a path
    /// that exists but isn't a real directory (e.g. a symlink).
    @discardableResult
    public static func prepareDirectory(_ dir: URL) throws -> URL {
        let fm = FileManager.default
        if let type = fileType(dir.path) {
            guard type == .typeDirectory else { throw PathError.notADirectory(dir.path) }
        } else {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        return dir
    }

    /// Creates `file` empty at 0600 if missing, or tightens an existing one.
    /// Refuses a symlink or anything else that isn't a regular file.
    @discardableResult
    public static func preparePrivateFile(_ file: URL) throws -> URL {
        let fm = FileManager.default
        if let type = fileType(file.path) {
            guard type == .typeRegular else { throw PathError.notARegularFile(file.path) }
        } else {
            // O_EXCL | O_NOFOLLOW: never write through a link planted after the check.
            let fd = open(file.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            guard fd >= 0 else { throw PathError.notARegularFile(file.path) }
            close(fd)
        }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return file
    }

    /// The type of the item at `path` without following symlinks, or nil if
    /// nothing is there.
    public static func fileType(_ path: String) -> FileAttributeType? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        return attrs[.type] as? FileAttributeType
    }

    private static func library(_ sub: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent(sub, isDirectory: true)
    }
}

public enum PathError: Error, CustomStringConvertible {
    case notADirectory(String)
    case notARegularFile(String)

    public var description: String {
        switch self {
        case .notADirectory(let p): return "\(p) exists but is not a directory"
        case .notARegularFile(let p): return "\(p) is a symlink or not a regular file"
        }
    }
}
