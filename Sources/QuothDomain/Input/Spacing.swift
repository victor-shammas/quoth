import Foundation

/// The character just before the insertion point in the focused field, read
/// over Accessibility at delivery.
public enum TextBeforeCursor: Equatable {
    /// The app didn't say: no element, no selection, or no text.
    case unknown
    /// The cursor is at the start of the field.
    case start
    /// The character before the cursor, or before the selection a paste
    /// replaces.
    case character(Character)

    /// What kind of character it is, for the log, which never carries text.
    public var kind: String {
        switch self {
        case .unknown: return "unknown"
        case .start: return "start"
        case .character(let c) where c.isNewline: return "newline"
        case .character(let c) where c.isWhitespace: return "space"
        case .character(let c) where c.isLetter || c.isNumber: return "letter"
        case .character: return "punctuation"
        }
    }
}

/// How a character behaves next to a space.
enum SpacingClass: Equatable {
    case newline
    case whitespace
    /// Opens something a word follows without a space: brackets and quotes,
    /// `¿`, `¡`, and the `/`, `@` and `#` of paths, handles and tags.
    case opener
    /// Closes or follows a word without a space: punctuation, closing
    /// brackets and quotes, `%`.
    case closer
    /// Written without spaces between words: Chinese, Japanese, Thai.
    case spaceless
    /// Letters, digits and everything else.
    case word

    private static let openers = Set("([{<\"'“‘«‹¿¡/@#")
    private static let closers = Set(".,;:!?)]}…%”’»›")

    init(_ c: Character) {
        if c.isNewline { self = .newline }
        else if c.isWhitespace { self = .whitespace }
        else if Self.openers.contains(c) { self = .opener }
        else if Self.closers.contains(c) { self = .closer }
        else if Self.isSpaceless(c) { self = .spaceless }
        else { self = .word }
    }

    private static func isSpaceless(_ c: Character) -> Bool {
        guard let scalar = c.unicodeScalars.first?.value else { return false }
        return spacelessRanges.contains { $0.contains(scalar) }
    }

    private static let spacelessRanges: [ClosedRange<UInt32>] = [
        0x0E00...0x0E7F, // Thai
        0x3000...0x303F, // CJK symbols and punctuation
        0x3040...0x30FF, // Hiragana and Katakana
        0x3400...0x4DBF, // CJK Extension A
        0x4E00...0x9FFF, // CJK Unified Ideographs
        0xFF00...0xFFEF, // Fullwidth forms
        0x20000...0x2FA1F, // CJK Extensions B and later
    ]
}

/// The spaces around a transcript, so consecutive dictations don't run
/// together ("works well.The only thing"). Whisper never starts or ends a
/// transcript with a space.
public enum Spacing {
    /// The text to insert: with a trailing space, so the next dictation or
    /// word follows on, and with a leading one only when the character
    /// before the cursor needs it, as after a word typed by hand. Unknown
    /// adds none: after a dictation, its trailing space is already there.
    public static func spaced(_ text: String, before: TextBeforeCursor) -> String {
        let leading = if case .character(let c) = before, needsSpace(after: c, text: text) { " " } else { "" }
        let trailing = text.last.map { [.word, .opener, .closer].contains(SpacingClass($0)) } == true ? " " : ""
        return leading + text + trailing
    }

    /// Whether `text` needs a space to follow `preceding`.
    public static func needsSpace(after preceding: Character, text: String) -> Bool {
        guard let first = text.first else { return false }
        switch (SpacingClass(preceding), SpacingClass(first)) {
        case (.newline, _), (.whitespace, _), (_, .newline), (_, .whitespace): return false
        case (.opener, _), (_, .closer): return false
        case (.spaceless, _), (_, .spaceless): return false
        default: return true
        }
    }
}
