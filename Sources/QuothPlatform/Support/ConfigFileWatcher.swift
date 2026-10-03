import Foundation

/// Calls back when a `ConfigFile` changes on disk, so a hand edit applies
/// without a restart. Watches the folder, which sees atomic saves (they
/// replace the file), and the file, which sees editors that write in place.
/// A burst of events, as one save produces, becomes one call.
@MainActor
public final class ConfigFileWatcher {
    private let file: ConfigFile
    private let onChange: @MainActor () -> Void
    private var folderSource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var pending = false

    /// Starts watching. `onChange` runs on the main actor.
    public init(_ file: ConfigFile, onChange: @escaping @MainActor () -> Void) {
        self.file = file
        self.onChange = onChange
        let folder = file.url.deletingLastPathComponent().resolvingSymlinksInPath()
        if Paths.fileType(folder.path) == nil {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        folderSource = source(folder.path, events: .write)
        rearm()
    }

    /// Watches the file again: after an atomic save the watched file is gone
    /// and a new one is in its place.
    public func rearm() {
        fileSource?.cancel()
        fileSource = source(file.url.resolvingSymlinksInPath().path, events: [.write, .delete, .rename, .extend])
    }

    private func source(_ path: String, events: DispatchSource.FileSystemEvent) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: events, queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.changed() } }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    private func changed() {
        guard !pending else { return }
        pending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pending = false
                self.rearm()
                self.onChange()
            }
        }
    }
}
