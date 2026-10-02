import XCTest
@testable import QuothCore

final class VoiceCommandsTests: XCTestCase {
    private func process(_ text: String, language: String? = "en") -> String {
        var timings = TranscriberTimings()
        timings.language = language
        return VoiceCommands().process(Transcript(text: text, timings: timings)).text
    }

    func testNewParagraphAndNewLine() {
        XCTAssertEqual(process("It's transcribing the words. New paragraph. No, it works now."),
                       "It's transcribing the words.\n\nNo, it works now.")
        XCTAssertEqual(process("Milk, new line, eggs, new line, bread."), "Milk\nEggs\nBread.")
        XCTAssertEqual(process("first part new paragraph second part"), "first part\n\nSecond part")
    }

    func testOtherTextIsUntouched() {
        XCTAssertEqual(process("A newline character and a paragraph."), "A newline character and a paragraph.")
        XCTAssertEqual(process("Nouveau paragraphe new paragraph", language: "fr"), "Nouveau paragraphe new paragraph")
    }
}
