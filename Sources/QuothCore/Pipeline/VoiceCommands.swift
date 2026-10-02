import Foundation

/// Spoken formatting: "new paragraph" becomes a blank line and "new line" a
/// line break, with the punctuation Whisper puts around them ("…the words.
/// New paragraph. Next…" → "…the words.\n\nNext…"). English only for now:
/// the phrases are matched in English, and a transcript in another language
/// is left alone.
struct VoiceCommands: TranscriptProcessor {
    private static let commands: [(pattern: NSRegularExpression, replacement: String)] = [
        ("new paragraph", "\n\n"),
        ("new line", "\n"),
    ].map { phrase, replacement in
        let words = phrase.split(separator: " ").joined(separator: #"\s+"#)
        // Eat a comma or semicolon before, and the period or comma Whisper
        // ends the phrase with, so the break replaces them cleanly.
        let pattern = #"[ \t]*[,;:]?[ \t]*\b"# + words + #"\b[.,;:!]?[ \t]*"#
        return (try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive]), replacement)
    }

    func process(_ transcript: Transcript) -> Transcript {
        if let language = transcript.timings?.language, !language.lowercased().hasPrefix("en") {
            return transcript
        }
        var text = transcript.text
        for (pattern, replacement) in Self.commands {
            let range = NSRange(text.startIndex..., in: text)
            text = pattern.stringByReplacingMatches(in: text, range: range, withTemplate: NSRegularExpression.escapedTemplate(for: replacement))
        }
        guard text != transcript.text else { return transcript }
        return Transcript(text: Self.capitalizingAfterBreaks(text), timings: transcript.timings)
    }

    /// The first letter after a break starts a sentence.
    private static func capitalizingAfterBreaks(_ text: String) -> String {
        var out = ""
        var capitalizeNext = false
        for c in text {
            if c == "\n" {
                capitalizeNext = true
                out.append(c)
            } else if capitalizeNext, c.isLetter {
                out += c.uppercased()
                capitalizeNext = false
            } else {
                out.append(c)
            }
        }
        return out
    }
}
