import Foundation

/// The user's dictionary: words Quoth should spell their way, each with what
/// the model writes instead ("Kubernetes", heard as "Cooper Netties").
///
/// It lives in `Paths.dictionaryFile`, a plain-text table (`parse(_:)`,
/// `text`), and the Settings editor shows the same entries as rows. A word
/// is rewritten to its own casing wherever it's heard ("posthog" becomes
/// "PostHog"), and each Heard as item is rewritten to the word
/// (`DictionaryReplacer`).
///
/// `examples` are one natural sentence per language for Whisper to read as
/// the speech before a dictation. They live in `settings.json`
/// (`DictionarySettings`), because they cost decoding time and don't fit
/// the table.
///
/// This is the only user-authored text Quoth stores. It never holds
/// transcript text.
public struct UserDictionary: Equatable, Sendable {
    /// A word and what the model writes instead of it: one line of the file,
    /// one row of the editor.
    public struct Entry: Equatable, Sendable {
        public var word: String
        public var heardAs: [String]

        public init(word: String, heardAs: [String] = []) {
            self.word = word
            self.heardAs = heardAs
        }
    }

    /// The words, each once, in the order they were first listed, with runs
    /// of whitespace as one space (the replacement pass treats them alike).
    public private(set) var entries: [Entry] = []
    /// One sentence per language code (`en`, `pt-BR`).
    public var examples: [String: String]

    public static let empty = UserDictionary()

    /// A dictionary of `entries`, tidied: blank words and items dropped,
    /// a word listed twice merged into its first entry, and what the file
    /// can't hold left out (a word with a comma or starting with `#`, a
    /// Heard as item with a comma).
    public init(entries: [Entry] = [], examples: [String: String] = [:]) {
        self.examples = examples
        var index: [String: Int] = [:]
        for entry in entries {
            let word = Self.tidy(entry.word)
            guard !word.isEmpty, !word.contains(","), !word.hasPrefix("#") else { continue }
            let items = entry.heardAs.map(Self.tidy).filter { !$0.isEmpty && !$0.contains(",") }
            if let i = index[word] {
                self.entries[i].heardAs += items.filter { !self.entries[i].heardAs.contains($0) }
            } else {
                index[word] = self.entries.count
                self.entries.append(Entry(word: word, heardAs: items.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }))
            }
        }
    }

    private static func tidy(_ s: String) -> String {
        s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // MARK: What the replacement pass and engines read

    /// Every word, to be written in its own casing.
    public var terms: [String] { entries.map(\.word) }

    /// What the model writes, rewritten to a word.
    public struct Replacement: Equatable, Sendable {
        /// Matched as whole words, ignoring case.
        public var from: [String]
        /// Inserted exactly as given.
        public var to: String
    }

    public var replacements: [Replacement] {
        entries.filter { !$0.heardAs.isEmpty }.map { Replacement(from: $0.heardAs, to: $0.word) }
    }

    /// Canonical spellings, for engines that take a word list.
    public var vocabulary: [String] { terms }

    /// The example sentence for `language`, or nil when there is none: the
    /// exact code first, then its primary subtag, ignoring case, so `pt-BR`
    /// and `pt` share a sentence. Never one in another language: a prompt in
    /// the wrong language pulls the decoder into it.
    public func example(for language: String?) -> String? {
        guard let language, !language.isEmpty else { return nil }
        let code = language.lowercased()
        let primary = Self.primarySubtag(code)
        // Sorted, so the choice among several matches is stable.
        let sentences = examples
            .map { (code: $0.key.lowercased(), text: $0.value.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.text.isEmpty }
            .sorted { $0.code < $1.code }
        let match = sentences.first { $0.code == code }
            ?? sentences.first { $0.code == primary }
            // `en` spoken, only `en-US` written: the same language.
            ?? sentences.first { Self.primarySubtag($0.code) == primary }
        return match?.text
    }

    private static func primarySubtag(_ code: String) -> String {
        String(code.split { $0 == "-" || $0 == "_" }.first ?? Substring(code))
    }
}

// MARK: - The text file

extension UserDictionary {
    /// Reads the dictionary file, or throws a `DictionaryParseError` that
    /// names the line and never quotes the file.
    ///
    /// ```
    /// # Comment
    /// Word          Replaces
    /// Vercel        Versailles, Vercell, ver cell
    /// Parakeet
    /// ```
    ///
    /// Blank lines, `#` comments and the header line are skipped. A tab or
    /// two or more spaces end the word, which may contain single spaces
    /// ("Claude Code"); the rest is Replaces, a comma-separated list. A comma
    /// in the word means the separator is missing, so the file is refused
    /// rather than guessed at.
    public static func parse(_ data: Data) throws -> UserDictionary {
        guard var text = String(data: data, encoding: .utf8) else { throw DictionaryParseError.notText }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        var entries: [Entry] = []
        // "\r\n" is one Character, so CRLF files number their lines right.
        for (number, raw) in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let (word, replaces) = columns(line)
            if word.caseInsensitiveCompare("Word") == .orderedSame,
               replaces.caseInsensitiveCompare("Replaces") == .orderedSame { continue }
            guard !word.contains(",") else { throw DictionaryParseError.missingSeparator(line: number + 1) }
            entries.append(Entry(word: word, heardAs: replaces.split(separator: ",").map(String.init)))
        }
        return UserDictionary(entries: entries)
    }

    /// A line's word and Replaces columns, split at the first tab or run of
    /// two or more spaces.
    private static func columns(_ line: String) -> (word: String, replaces: String) {
        guard let gap = line.range(of: "\t| {2,}", options: .regularExpression) else { return (line, "") }
        return (
            line[..<gap.lowerBound].trimmingCharacters(in: .whitespaces),
            line[gap.upperBound...].trimmingCharacters(in: .whitespaces)
        )
    }

    /// The comment lines at the top of every file Quoth writes.
    public static let preamble = """
        # Words Quoth should spell your way. Replaces lists what it writes instead.
        # Separate the columns with two spaces or a tab.


        """

    /// The dictionary as its file: the preamble, the header, and one aligned
    /// line per word. `examples` aren't part of it.
    public var text: String {
        let width = max(entries.map(\.word.count).max() ?? 0, "Word".count) + 4
        func line(_ word: String, _ replaces: String) -> String {
            replaces.isEmpty ? word : word.padding(toLength: width, withPad: " ", startingAt: 0) + replaces
        }
        let lines = [line("Word", "Replaces")] + entries.map { line($0.word, $0.heardAs.joined(separator: ", ")) }
        return Self.preamble + lines.joined(separator: "\n") + "\n"
    }

    /// Written on first run so the file shows its shape. It only names
    /// Quoth's own speech library, so it changes nothing a new user is likely
    /// to say, and it has no example sentence: those add decoding time to
    /// every dictation, so they should be the user's own.
    public static let template = UserDictionary(entries: [Entry(word: "WhisperKit", heardAs: ["whisper kit"])]).text
}

/// Why the dictionary file didn't load. Descriptions give a line number and
/// never quote the file.
public enum DictionaryParseError: Error, Equatable, CustomStringConvertible {
    case notText
    case missingSeparator(line: Int)

    public var description: String {
        switch self {
        case .notText:
            return "not UTF-8 text"
        case .missingSeparator(let line):
            return "line \(line): separate the word from Replaces with two spaces or a tab"
        }
    }
}
