import Foundation
import QuothDomain

/// The one-copy rule: whoever holds the lock file is the Quoth listening to
/// the hotkey. Held with `flock` for the life of the process, so it goes
/// when the process does, however it ends.
public final class InstanceLock {
    private let fd: Int32

    private init(fd: Int32) { self.fd = fd }

    deinit { close(fd) }

    public enum Claim {
        /// This process holds the lock; keep the value alive.
        case held(InstanceLock)
        /// Another copy of Quoth holds it.
        case heldElsewhere
        /// It couldn't be tried (the folder can't be written): carry on,
        /// since one extra copy beats none.
        case unavailable
    }

    public static func claim(_ file: URL) -> Claim {
        do {
            try Paths.prepareDirectory(file.deletingLastPathComponent())
        } catch {
            Log.warning("couldn't prepare \(file.deletingLastPathComponent().path): \(error)")
            return .unavailable
        }
        let fd = open(file.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else {
            Log.warning("couldn't open \(file.path)")
            return .unavailable
        }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            return .heldElsewhere
        }
        return .held(InstanceLock(fd: fd))
    }
}

/// The app's log, when no terminal is reading it: stdout and stderr go to
/// owner-only files in `Paths.logs`. Best effort; Quoth runs without.
public enum LogFiles {
    public static func redirectOutput() {
        do {
            try Paths.prepareDirectory(Paths.logs)
            for (file, fd) in [(Paths.outLog, STDOUT_FILENO), (Paths.errLog, STDERR_FILENO)] {
                try Paths.preparePrivateFile(file)
                let out = open(file.path, O_WRONLY | O_APPEND | O_NOFOLLOW | O_CLOEXEC)
                guard out >= 0 else { continue }
                dup2(out, fd)
                close(out)
            }
            setvbuf(stdout, nil, _IOLBF, 0)
        } catch {}
    }
}
