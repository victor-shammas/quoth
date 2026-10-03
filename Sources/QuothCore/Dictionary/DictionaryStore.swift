import Foundation
import QuothDomain
import QuothPlatform

/// The dictionary file (`Paths.dictionaryFile`): read before each dictation
/// when it has changed, and saved by the Settings editor and Fix Last
/// Dictation.
///
/// `current()` costs a `stat` when nothing changed. A file that can't be
/// used keeps the last good dictionary, logs the problem once, and is never
/// saved over, so a hand edit in progress is never lost.
package final class DictionaryStore: @unchecked Sendable {
    /// A dictionary with its compiled replacement pass.
    struct Loaded {
        let dictionary: UserDictionary
        let replacer: DictionaryReplacer

        init(_ dictionary: UserDictionary) {
            self.dictionary = dictionary
            self.replacer = DictionaryReplacer(dictionary)
        }
    }

    static let maxBytes = 1 << 20
    /// Posted after a save, so an open editor can reload.
    static let didSave = Notification.Name("QuothDictionaryDidSave")

    private let config: ConfigFile
    private let log: (String) -> Void
    private let lock = NSLock()
    private var loaded = Loaded(.empty)
    /// What the file was when last looked at.
    private var state: State = .unread
    /// Why the file on disk isn't what `current()` uses, or nil when it is.
    private var problem: String?

    private enum State: Equatable {
        case unread
        case missing
        case read(ConfigFile.Version)
        case refused(String)
    }

    var file: URL { config.url }

    package init(file: URL = Paths.dictionaryFile, log: @escaping (String) -> Void = { Log.warning($0) }) {
        config = ConfigFile(file, maxBytes: Self.maxBytes)
        self.log = log
    }

    /// The dictionary for this dictation, read again first if the file changed.
    func current() -> Loaded {
        lock.withLock {
            refresh()
            return loaded
        }
    }

    /// Why the file isn't what `current()` uses, or nil when it is: a mistake
    /// in it, or a file that can't be read. The Settings editor won't save
    /// over it.
    func loadProblem() -> String? {
        lock.withLock {
            refresh()
            return problem
        }
    }

    /// Writes the first-run template when nothing at all is at the path, not
    /// even a dangling link. Returns whether it did.
    @discardableResult
    func createIfMissing() -> Bool {
        do {
            guard try config.create(Data(UserDictionary.template.utf8)) else { return false }
        } catch {
            log("couldn't create \(file.path): \(error.localizedDescription)")
            return false
        }
        Log.info("created \(file.path) with an example row")
        return true
    }

    /// Saves `dictionary` as the file (comments other than the preamble go).
    /// Never over a file with a mistake in it, and with `basedOn`, never over
    /// one that changed since the caller read it, in another window or a text
    /// editor. Returns false, and logs, when it didn't save.
    @discardableResult
    func save(_ dictionary: UserDictionary, basedOn base: UserDictionary? = nil) -> Bool {
        lock.withLock {
            refresh()
            if let problem {
                log("not saving the dictionary: the file has a mistake (\(problem))")
                return false
            }
            if let base, base.entries != loaded.dictionary.entries {
                log("not saving the dictionary: it changed since it was read")
                return false
            }
            do {
                try config.write(Data(dictionary.text.utf8))
            } catch {
                log("couldn't save \(file.path): \(error.localizedDescription)")
                return false
            }
            // In use at once, without waiting for the next look at the file.
            loaded = Loaded(dictionary)
            state = .unread
            DispatchQueue.main.async { NotificationCenter.default.post(name: Self.didSave, object: self) }
            return true
        }
    }

    /// Adds `heardAs` (a comma-separated list) as what the model writes
    /// instead of `word`: to that word's entry if it has one, in any casing,
    /// or as a new one.
    @discardableResult
    func add(word: String, heardAs: String) -> Bool {
        let word = word.trimmingCharacters(in: .whitespacesAndNewlines)
        // The file can't hold a word with a comma or starting with #.
        guard !word.isEmpty, !word.contains(","), !word.hasPrefix("#") else { return false }
        let heard = heardAs.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let base = current().dictionary
        var entries = base.entries
        if let i = entries.firstIndex(where: { $0.word.caseInsensitiveCompare(word) == .orderedSame }) {
            entries[i].word = word
            entries[i].heardAs += heard.filter { item in
                !entries[i].heardAs.contains { $0.caseInsensitiveCompare(item) == .orderedSame }
            }
        } else {
            entries.append(UserDictionary.Entry(word: word, heardAs: heard))
        }
        return save(UserDictionary(entries: entries, examples: base.examples), basedOn: base)
    }

    // MARK: -

    private func refresh() {
        let version: ConfigFile.Version? = if case .read(let v) = state { v } else { nil }
        switch config.read(unless: version) {
        case .unchanged:
            return
        case .missing:
            // The user removed their dictionary, so use none.
            guard state != .missing else { return }
            if state != .unread { log("\(file.path) was removed; dictionary is empty") }
            loaded = Loaded(.empty)
            state = .missing
            problem = nil
        case .refused(let reason):
            problem = reason
            guard state != .refused(reason) else { return }
            state = .refused(reason)
            log("\(reason); keeping the last good dictionary")
        case .read(let data, let version):
            state = .read(version)
            do {
                let dictionary = try UserDictionary.parse(data)
                loaded = Loaded(dictionary)
                problem = nil
                Log.info("dictionary: \(dictionary.terms.count) words · \(dictionary.replacements.count) with replacements")
            } catch {
                problem = "\(error)"
                log("\(file.lastPathComponent) not loaded, \(error); keeping the last good version")
            }
        }
    }
}
