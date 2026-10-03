import Foundation

/// The dictionary's replacement pass: each Heard as item becomes its word,
/// and each word gets its own casing. Built once per loaded dictionary.
///
/// - Matching ignores case and takes whole words only. A match may not touch
///   a letter, digit, combining mark or underscore in any script, so `api`
///   leaves `rapid` alone and a decomposed `café` is one word.
/// - Spaces in a `from` match any run of whitespace, a hyphen or nothing;
///   hyphens inside a word are optional, and apostrophes where that is safe
///   (`pattern(for:)`). So "k8s" also matches "K8's" and "k-8-s", but "ID"
///   never matches "I'd".
/// - Where several rules match at the same place, the longest wins.
/// - One pass over the text: what a rule inserts is never matched again, so
///   rules can't chain. Replacement text goes in literally.
/// - A Heard as item outranks the same word as a term, and the first rule
///   listed wins among duplicates.
public struct DictionaryReplacer {
    public struct Rule: Equatable {
        public var from: String
        public var to: String
    }

    /// Longest `from` first, the order the regex tries them in.
    public let rules: [Rule]
    private let regex: NSRegularExpression?

    public init(_ dictionary: UserDictionary) {
        let trimmed = { (s: String) in s.trimmingCharacters(in: .whitespacesAndNewlines) }
        let heard = dictionary.replacements.flatMap { r in r.from.map { Rule(from: $0, to: trimmed(r.to)) } }
        let casing = dictionary.terms.map { Rule(from: $0, to: trimmed($0)) }
        self.init(rules: heard + casing)
    }

    public init(rules candidates: [Rule]) {
        var kept: [Rule] = []
        for candidate in candidates {
            let from = candidate.from.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            // A `from` of only apostrophes or hyphens would match everywhere.
            guard !candidate.to.isEmpty, !Self.pattern(for: from).isEmpty else { continue }
            // Duplicates compare as the regex will: ignoring case.
            guard !kept.contains(where: { $0.from.caseInsensitiveCompare(from) == .orderedSame }) else { continue }
            kept.append(Rule(from: from, to: candidate.to))
        }
        // At each position the regex takes the first alternative that fits,
        // so longest first makes it the longest that fits. Stable among equals.
        rules = kept.enumerated()
            .sorted { ($0.element.from.count, -$0.offset) > ($1.element.from.count, -$1.offset) }
            .map(\.element)
        regex = Self.compile(rules)
    }

    /// One capture group per rule, so the group that matched names its rule.
    private static func compile(_ rules: [Rule]) -> NSRegularExpression? {
        guard !rules.isEmpty else { return nil }
        let wordCharacter = #"[\p{L}\p{M}\p{N}_]"#
        let alternatives = rules.map { "(" + Self.pattern(for: $0.from) + ")" }.joined(separator: "|")
        let whole = "(?<!\(wordCharacter))(?:\(alternatives))(?!\(wordCharacter))"
        return try? NSRegularExpression(pattern: whole, options: [.caseInsensitive])
    }

    // MARK: Patterns

    /// Apostrophes and hyphens, which Whisper puts in or leaves out of the
    /// same word from one dictation to the next ("K8's", "k8s", "k-8-s").
    public static let joiners: Set<Character> = ["'", "’", "-", "‐", "‑"]
    private static let apostrophes: Set<Character> = ["'", "’"]

    private static let optionalHyphen = #"[\-‐‑]?"#
    private static let optionalJoiner = #"['’\-‐‑]?"#
    private static let wordGap = #"[\s\-‐‑]*"#

    /// The regex for one `from`: its words joined by spaces, hyphens or
    /// nothing, so "post hog" also matches "posthog" and "post-hog". Empty
    /// for a `from` with no letters.
    public static func pattern(for from: String) -> String {
        from.split(separator: " ")
            .map { wordPattern(Substring($0)) }
            .filter { !$0.isEmpty }
            .joined(separator: wordGap)
    }

    /// One word's letters in order, with an optional hyphen between any two.
    /// An apostrophe is optional only where it can't turn the word into
    /// another: where the word has one ("o'clock" matches "oclock"), and
    /// before a final "s" ("k8s" matches "K8's"). Anywhere else "ID" would
    /// match "I'd" and "Well" "we'll".
    private static func wordPattern(_ word: Substring) -> String {
        var letters: [(letter: Character, afterApostrophe: Bool)] = []
        var sawApostrophe = false
        for c in word {
            if apostrophes.contains(c) {
                sawApostrophe = true
            } else if !joiners.contains(c) {
                letters.append((c, sawApostrophe))
                sawApostrophe = false
            }
        }
        return letters.enumerated().map { i, entry in
            let escaped = NSRegularExpression.escapedPattern(for: String(entry.letter))
            guard i > 0 else { return escaped }
            let finalS = i == letters.count - 1 && entry.letter.lowercased() == "s"
            return (entry.afterApostrophe || finalS ? optionalJoiner : optionalHyphen) + escaped
        }.joined()
    }

    // MARK: Applying

    public func apply(to text: String) -> String {
        guard let regex, !text.isEmpty else { return text }
        let whole = NSRange(text.startIndex..., in: text)
        var out = ""
        var cursor = text.startIndex
        for match in regex.matches(in: text, range: whole) {
            guard let rule = (1...rules.count).first(where: { match.range(at: $0).location != NSNotFound }),
                  let range = Range(match.range, in: text) else { continue }
            out += text[cursor..<range.lowerBound] + rules[rule - 1].to
            cursor = range.upperBound
        }
        return out + text[cursor...]
    }
}
