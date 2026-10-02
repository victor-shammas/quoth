import Foundation

/// Spoken formatting, in English for now (a transcript in another language
/// is left alone):
///
/// - "new paragraph" and "new line" break the text; "bullet point" starts a
///   bulleted line.
/// - "comma", "semicolon", "question mark", "exclamation mark" (or point)
///   and "full stop" become their marks. "period" and "colon" are ordinary
///   words too ("a trial period"), so they count only where Whisper heard a
///   pause around them, which it writes as punctuation.
/// - "quote … unquote" (or "end quote", "close quote") puts the words
///   between in curly quotes, which suits an app called Quoth.
/// - "scratch that" drops what came before it in the same dictation, or,
///   at the start of one, asks delivery to remove the previous dictation
///   (`Transcript.scratchesPrevious`).
///
/// The punctuation Whisper puts around a command is absorbed, so the mark
/// replaces it cleanly ("…the words. New paragraph. Next…" → "…the
/// words.\n\nNext…").
struct VoiceCommands: TranscriptProcessor {
    /// Marks where a command inserted something, so the clean-up after it
    /// spaces and capitalizes only there. A private-use character no
    /// transcript contains.
    private static let marker: Character = "\u{E000}"

    /// Punctuation Whisper may write around a spoken command.
    private static let around = #"[,.;:!?]*"#

    private struct Command {
        let pattern: NSRegularExpression
        let replacement: String
    }

    /// `keepsSentence`: a line break keeps the period or question mark the
    /// sentence before it ended with, and absorbs only a comma or the like;
    /// a mark absorbs whatever Whisper put there.
    private static func command(_ phrases: [String], _ replacement: String, needsPause: Bool = false, keepsSentence: Bool = false) -> Command {
        let alternatives = phrases
            .map { $0.split(separator: " ").joined(separator: #"\s+"#) }
            .joined(separator: "|")
        // The phrase as whole words, with the spaces and punctuation around
        // it. A word that is also ordinary needs punctuation on one side.
        let core = #"\b(?:"# + alternatives + #")\b"#
        let pattern = needsPause
            ? #"(?:[ \t]*[,.;:!?]+[ \t]*"# + core + around + #"|[ \t]*"# + core + #"[,.;:!?]+|[ \t]*"# + core + #"[ \t]*$)[ \t]*"#
            : #"[ \t]*"# + (keepsSentence ? #"[,;:]*"# : around) + #"[ \t]*"# + core + around + #"[ \t]*"#
        return Command(pattern: try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive]), replacement: replacement)
    }

    private static let commands: [Command] = [
        command(["new paragraph"], "\n\n", keepsSentence: true),
        command(["new line"], "\n", keepsSentence: true),
        command(["bullet point"], "\n• ", keepsSentence: true),
        command(["question mark"], "?\(marker)"),
        command(["exclamation mark", "exclamation point"], "!\(marker)"),
        command(["full stop"], ".\(marker)"),
        command(["semicolon"], ";\(marker)"),
        command(["comma"], ",\(marker)"),
        command(["period"], ".\(marker)", needsPause: true),
        command(["colon"], ":\(marker)", needsPause: true),
    ]

    private static let quoted = try! NSRegularExpression(
        pattern: #"[ \t]*\b(?:open\s+)?quote\b[,.:]?[ \t]*(.+?)[ \t]*[,.]?[ \t]*\b(?:unquote|end\s+quote|close\s+quote)\b[,.]?"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )

    private static let scratch = try! NSRegularExpression(
        pattern: #"\bscratch\s+that\b[,.!]?"#, options: [.caseInsensitive]
    )

    func process(_ transcript: Transcript) -> Transcript {
        if let language = transcript.timings?.language, !language.lowercased().hasPrefix("en") {
            return transcript
        }
        var text = transcript.text
        var scratchesPrevious = transcript.scratchesPrevious

        // "scratch that": keep only what follows the last one.
        let scratches = Self.scratch.matches(in: text, range: NSRange(text.startIndex..., in: text))
        if let last = scratches.last, let range = Range(last.range, in: text) {
            let before = text[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            // At the very start, it is about the dictation before this one.
            if scratches.count == 1, before.isEmpty { scratchesPrevious = true }
            text = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            // What is left starts a fresh sentence.
            if let first = text.first { text = first.uppercased() + text.dropFirst() }
        }

        text = Self.quoted.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text),
            withTemplate: " \(Self.marker)“$1”\(Self.marker)"
        )
        for command in Self.commands {
            text = command.pattern.stringByReplacingMatches(
                in: text, range: NSRange(text.startIndex..., in: text),
                withTemplate: NSRegularExpression.escapedTemplate(for: command.replacement)
            )
        }
        text = Self.tidy(text)
        guard text != transcript.text || scratchesPrevious != transcript.scratchesPrevious else { return transcript }
        var out = Transcript(text: text, timings: transcript.timings)
        out.scratchesPrevious = scratchesPrevious
        return out
    }

    /// Spaces and capitals around what the commands inserted: a space after
    /// a mark when a word follows, none before; a capital after a sentence
    /// ends or a line breaks; no stray spaces at line ends.
    private static func tidy(_ text: String) -> String {
        var out = ""
        var capitalize = false
        var chars = Array(text)
        // A bullet at the very start needs no line break before it.
        while chars.first == "\n", chars.dropFirst().first == "•" { chars.removeFirst() }
        for (i, c) in chars.enumerated() {
            if c == marker {
                // A word straight after an inserted mark gets a space.
                if let next = chars[(i + 1)...].first(where: { $0 != marker }), next.isLetter || next.isNumber || next == "“",
                   let last = out.last, !last.isWhitespace {
                    out.append(" ")
                }
                continue
            }
            if c == " ", out.last == " " || out.last == "\n" || out.isEmpty { continue }
            if c == "\n", out.last == " " { out.removeLast() }
            if capitalize, c.isLetter {
                out += c.uppercased()
                capitalize = false
                continue
            }
            if c == "\n" || c == "•" || ".!?".contains(c), i + 1 < chars.count, chars[i + 1] == marker || chars[i + 1] == "\n" || c == "\n" || c == "•" {
                capitalize = true
            } else if !c.isWhitespace, c != "“" {
                capitalize = false
            }
            out.append(c)
        }
        return out.trimmingCharacters(in: .whitespaces)
    }
}
