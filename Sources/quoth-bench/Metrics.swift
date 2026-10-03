import Foundation

/// How far a transcript is from what was said: the word-level edit distance
/// over the number of words said, after lowercasing and dropping
/// punctuation.
struct WordErrorRate: Equatable {
    /// Substitutions, deletions and insertions.
    var errors: Int
    var referenceWords: Int

    var rate: Double {
        referenceWords > 0 ? Double(errors) / Double(referenceWords) : (errors == 0 ? 0 : 1)
    }

    init(reference: String, hypothesis: String) {
        let said = Self.words(reference)
        errors = Self.editDistance(said, Self.words(hypothesis))
        referenceWords = said.count
    }

    /// Lowercased words without punctuation. Apostrophes inside a word stay
    /// ("don't"); hyphens split words.
    static func words(_ text: String) -> [String] {
        let letters = text.lowercased().replacingOccurrences(of: "’", with: "'")
            .map { $0.isLetter || $0.isNumber || $0 == "'" ? $0 : " " }
        return String(letters).split(separator: " ")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'")) }
            .filter { !$0.isEmpty }
    }

    /// Levenshtein distance over words, one row at a time.
    static func editDistance(_ a: [String], _ b: [String]) -> Int {
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var row = Array(0...b.count)
        for (i, x) in a.enumerated() {
            var next = [i + 1]
            for (j, y) in b.enumerated() {
                next.append(min(row[j + 1] + 1, next[j] + 1, row[j] + (x == y ? 0 : 1)))
            }
            row = next
        }
        return row[b.count]
    }
}

/// Whether the transcript starts with the word that was said first: the
/// word a slow microphone start loses. "ok" and "okay" are the same word.
enum FirstWord {
    static func recalled(reference: String, hypothesis: String) -> Bool {
        guard let said = WordErrorRate.words(reference).first else { return true }
        guard let heard = WordErrorRate.words(hypothesis).first else { return false }
        return canonical(said) == canonical(heard)
    }

    private static func canonical(_ word: String) -> String { word == "ok" ? "okay" : word }
}

/// Nearest-rank percentiles.
enum Percentile {
    /// The `p`th percentile of `values` (0 < p ≤ 100), or 0 when empty.
    static func of(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let rank = Int((p / 100 * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank, 1), sorted.count) - 1]
    }
}

/// A recording to transcribe: a `.wav`, and what was said in it when a
/// `.txt` of the same name sits beside it.
struct Recording {
    var audio: URL
    var reference: String?

    /// The folder's recordings, by name.
    static func all(in folder: String) throws -> [Recording] {
        let dir = URL(fileURLWithPath: (folder as NSString).expandingTildeInPath, isDirectory: true)
        return try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.lowercased().hasSuffix(".wav") }
            .sorted()
            .map { name in
                let audio = dir.appendingPathComponent(name)
                let text = audio.deletingPathExtension().appendingPathExtension("txt")
                return Recording(audio: audio, reference: try? String(contentsOf: text, encoding: .utf8))
            }
    }
}
