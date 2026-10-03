import Foundation

/// A file the user may edit by hand, in `~/.config/quoth`: `settings.json`
/// and the dictionary (ADR-002).
///
/// It may live in a dotfiles repository, so the file, or its folder, can be
/// a symlink. Reading follows the link and then requires a regular file
/// owned by the user and no larger than `maxBytes`; writing goes to the
/// link's target, atomically and owner-only, so the link survives a save.
public struct ConfigFile: Sendable {
    public let url: URL
    /// Larger than any hand-written file of this kind; anything bigger is
    /// refused.
    public let maxBytes: Int

    public init(_ url: URL, maxBytes: Int) {
        self.url = url
        self.maxBytes = maxBytes
    }

    /// Which file was read and when it last changed: what tells an edit from
    /// the same file read again.
    public struct Version: Equatable, Sendable {
        let path: String
        let device: Int32
        let inode: UInt64
        let size: Int64
        let modified: timespec

        public static func == (a: Version, b: Version) -> Bool {
            (a.path, a.device, a.inode, a.size, a.modified.tv_sec, a.modified.tv_nsec)
                == (b.path, b.device, b.inode, b.size, b.modified.tv_sec, b.modified.tv_nsec)
        }
    }

    public enum Contents: Equatable {
        /// Nothing at the path, not even a dangling link.
        case missing
        /// The same version as `unless`: not read again.
        case unchanged
        case read(Data, Version)
        /// The file can't be used; the reason names paths, never contents.
        case refused(String)
    }

    /// Whether anything is at the path, a dangling link included.
    public var exists: Bool { Paths.fileType(url.path) != nil }

    /// Reads the file, unless it is still `version`.
    public func read(unless version: Version? = nil) -> Contents {
        guard exists else { return .missing }
        let resolved = url.resolvingSymlinksInPath().path
        var st = stat()
        guard stat(resolved, &st) == 0 else { return .refused("\(url.path) points to \(resolved), which doesn't exist") }
        if let problem = problem(with: st, at: resolved) { return .refused(problem) }
        if let version, version == Self.version(resolved, st) { return .unchanged }

        // Read through a descriptor and check it again, so the file checked
        // is the file read even if the path is swapped in between.
        let fd = open(resolved, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { return .refused("couldn't open \(resolved): \(String(cString: strerror(errno)))") }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        guard fstat(fd, &st) == 0 else { return .refused("couldn't read \(resolved)") }
        if let problem = problem(with: st, at: resolved) { return .refused(problem) }
        do {
            return .read(try handle.readToEnd() ?? Data(), Self.version(resolved, st))
        } catch {
            return .refused("couldn't read \(resolved): \(error.localizedDescription)")
        }
    }

    /// Replaces the file with `data`: atomically, owner-only, at the link's
    /// target. Creates the folder, owner-only, if it is missing; an existing
    /// one is never changed.
    public func write(_ data: Data) throws {
        let target = url.resolvingSymlinksInPath()
        try createFolderIfMissing(target.deletingLastPathComponent())
        try data.write(to: target, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
    }

    /// Writes `data` only if nothing at all is at the path, not even a
    /// dangling link, and never through something that appears after the
    /// check. Returns false if something was there.
    public func create(_ data: Data) throws -> Bool {
        guard !exists else { return false }
        try createFolderIfMissing(url.deletingLastPathComponent())
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else {
            if errno == EEXIST { return false }
            throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))])
        }
        try FileHandle(fileDescriptor: fd, closeOnDealloc: true).write(contentsOf: data)
        return true
    }

    private func createFolderIfMissing(_ folder: URL) throws {
        guard Paths.fileType(folder.path) == nil else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    /// Why the file at `path`, already resolved, can't be used, or nil.
    func problem(with st: stat, at path: String) -> String? {
        if st.st_mode & S_IFMT != S_IFREG { return "\(path) is not a regular file" }
        if st.st_uid != getuid() { return "\(path) is not owned by you" }
        if st.st_size > maxBytes { return "\(path) is larger than \(maxBytes / 1024) KB" }
        return nil
    }

    private static func version(_ path: String, _ st: stat) -> Version {
        Version(path: path, device: st.st_dev, inode: st.st_ino, size: st.st_size, modified: st.st_mtimespec)
    }
}
