import XCTest
@testable import QuothCore
@testable import QuothDomain

final class VoiceCommandsTests: XCTestCase {
    private func run(_ text: String, language: String? = "en") -> Transcript {
        var timings = TranscriberTimings()
        timings.language = language
        return VoiceCommands().process(Transcript(text: text, timings: timings))
    }

    private func process(_ text: String, language: String? = "en") -> String {
        run(text, language: language).text
    }

    func testNewParagraphAndNewLine() {
        XCTAssertEqual(process("It's transcribing the words. New paragraph. No, it works now."),
                       "It's transcribing the words.\n\nNo, it works now.")
        XCTAssertEqual(process("first part new paragraph second part"), "first part\n\nSecond part")
    }

    func testPunctuationWords() {
        XCTAssertEqual(process("Dear Anna comma thanks for the notes exclamation point"), "Dear Anna, thanks for the notes!")
        XCTAssertEqual(process("Is it ready question mark I think so"), "Is it ready? I think so")
        XCTAssertEqual(process("Hello, comma, how are you, question mark."), "Hello, how are you?")
        XCTAssertEqual(process("Three things semicolon then the rest full stop"), "Three things; then the rest.")
    }

    func testPeriodAndColonNeedAPause() {
        // Ordinary words stay words.
        XCTAssertEqual(process("The trial period ended in a colon infection"), "The trial period ended in a colon infection")
        // Where Whisper heard a pause, they are marks.
        XCTAssertEqual(process("That's settled, period. Next item"), "That's settled. Next item")
        XCTAssertEqual(process("Two options, colon, red or blue"), "Two options: red or blue")
        XCTAssertEqual(process("And that's it period"), "And that's it.")
    }

    func testQuoteUnquote() {
        XCTAssertEqual(process("She said quote I'll be there unquote and left"), "She said “I'll be there” and left")
        XCTAssertEqual(process("He wrote, open quote, done, close quote."), "He wrote, “done”")
        // "quote" alone is just a word.
        XCTAssertEqual(process("I liked that quote a lot"), "I liked that quote a lot")
    }

    func testBulletPoints() {
        XCTAssertEqual(process("Bullet point milk bullet point eggs"), "• Milk\n• Eggs")
    }

    func testScratchThat() {
        // Within one dictation: what came before goes.
        XCTAssertEqual(process("Send it on Monday. Scratch that. Send it on Tuesday."), "Send it on Tuesday.")
        let opening = run("Scratch that.")
        XCTAssertTrue(opening.scratchesPrevious)
        XCTAssertEqual(opening.text, "")
        let then = run("Scratch that, send it Tuesday")
        XCTAssertTrue(then.scratchesPrevious)
        XCTAssertEqual(then.text, "Send it Tuesday")
        XCTAssertFalse(run("Send it on Monday. Scratch that.").scratchesPrevious)
    }

    func testOtherTextIsUntouched() {
        XCTAssertEqual(process("A newline character and a paragraph."), "A newline character and a paragraph.")
        XCTAssertEqual(process("Nouveau paragraphe new paragraph", language: "fr"), "Nouveau paragraphe new paragraph")
    }
}
