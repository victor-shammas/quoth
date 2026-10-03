import Foundation

/// Rewrites a dictionary's `from` variants to their `to` value and its terms to
/// their canonical casing. Pure; built once per loaded dictionary.
///
/// - Matching ignores case and takes whole words only: a match may not touch a
///   letter, digit or underscore in any script (`\p{L}\p{N}_`, plus combining
///   marks), so `api` leaves `rapid` alone and `café` is one word.
/// - Whitespace inside a `from` matches any run of whitespace, a hyphen, or
///   nothing; hyphens inside a word are optional, and apostrophes where
///   that is safe (`pattern(for:)`), so "k8s" also matches "K8's" and
///   "k-8-s", but "ID" never matches "I'd".
/// - Where several rules match at the same place, the longest wins.
/// - One pass over the input: text a rule inserts is never matched again, so
///   rules cannot chain.
/// - Replacement text is inserted literally; `$` and `\` mean nothing special.
/// - A `from` listed in `replacements` takes precedence over the same word in
///   `terms`, and the first rule listed wins among duplicates.
public struct DictionaryReplacer {
    public struct Rule: Equatable {
        public var from: String
        public var to: String
    }

    public let rules: [Rule]
    private let regex: NSRegularExpression?

    public init(_ dictionary: UserDictionary) {
        var candidates: [Rule] = []
        for replacement in dictionary.replacements {
            let to = replacement.to.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !to.isEmpty else { continue }
            candidates += replacement.from.map { Rule(from: $0, to: to) }
        }
        candidates += dictionary.terms.map { Rule(from: $0, to: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        self.init(rules: candidates)
    }

    public init(rules candidates: [Rule]) {
        // Drop empty sources and later duplicates. Duplicates are found with
        // the same case-insensitive comparison the regex uses.
        var kept: [Rule] = []
        for rule in candidates {
            let from = rule.from.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            // A `from` of only apostrophes or hyphens would match everywhere.
            guard !from.isEmpty, !rule.to.isEmpty, !Self.pattern(for: from).isEmpty else { continue }
            if kept.contains(where: { $0.from.compare(from, options: .caseInsensitive) == .orderedSame }) { continue }
            kept.append(Rule(from: from, to: rule.to))
        }
        // Longest first: the regex tries alternatives in order at each
        // position, so the first that fits is the longest that fits.
        let ordered = kept.enumerated()
            .sorted { a, b in
                let (la, lb) = (a.element.from.count, b.element.from.count)
                return la != lb ? la > lb : a.offset < b.offset
            }
            .map(\.element)
        self.rules = ordered
        guard !ordered.isEmpty else {
            self.regex = nil
            return
        }
        // One capture group per rule, so the group that matched names the rule
        // without comparing strings outside the regex engine.
        let alternatives = ordered.map { "(" + Self.pattern(for: $0.from) + ")" }
        // Combining marks count as part of a word, so a decomposed "é" is not
        // a boundary.
        let word = #"[\p{L}\p{M}\p{N}_]"#
        let pattern = "(?<!\(word))(?:" + alternatives.joined(separator: "|") + ")(?!\(word))"
        self.regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    /// Apostrophes and hyphens, which Whisper puts in or leaves out of the
    /// same word from one dictation to the next ("K8's", "k8s", "k-8-s").
    public static let joiners: Set<Character> = ["'", "’", "-", "‐", "‑"]

    /// The pattern for one `from`: its letters in order, with an optional
    /// hyphen between any two, and its words joined by spaces, hyphens or
    /// nothing, so "post hog" also matches "posthog" and "post-hog".
    ///
    /// Apostrophes are optional only where they can't turn a word into
    /// another: where `from` has one ("o'clock" matches "oclock"), and before
    /// a final "s" ("k8s" matches "K8's"). Anywhere else they'd make "ID"
    /// match "I'd" and "Well" match "we'll". Empty for a `from` with no
    /// letters, which `init` drops.
    public static func pattern(for from: String) -> String {
        let hyphen = #"[\-‐‑]?"#
        let either = #"['’\-‐‑]?"#
        let between = #"[\s\-‐‑]*"#
        return from.split(separator: " ")
            .map { word -> String in
                // Letters, each remembering whether an apostrophe preceded it.
                var letters: [(Character, apostropheBefore: Bool)] = []
                var apostrophe = false
                for c in word {
                    if c == "'" || c == "’" {
                        apostrophe = true
                    } else if !joiners.contains(c) {
                        letters.append((c, apostrophe))
                        apostrophe = false
                    }
                }
                var pattern = ""
                for (i, letter) in letters.enumerated() {
                    if i > 0 {
                        let finalS = i == letters.count - 1 && letter.0.lowercased() == "s"
                        pattern += letter.apostropheBefore || finalS ? either : hyphen
                    }
                    pattern += NSRegularExpression.escapedPattern(for: String(letter.0))
                }
                return pattern
            }
            .filter { !$0.isEmpty }
            .joined(separator: between)
    }

    public func apply(to text: String) -> String {
        guard let regex, !text.isEmpty else { return text }
        let source = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty else { return text }

        var out = ""
        var cursor = 0
        for match in matches {
            guard let index = (1...rules.count).first(where: { match.range(at: $0).location != NSNotFound }) else {
                continue
            }
            out += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            out += rules[index - 1].to
            cursor = match.range.location + match.range.length
        }
        out += source.substring(from: cursor)
        return out
    }
}
