import XCTest
@testable import QuothCore
@testable import QuothDomain
@testable import QuothPlatform
@testable import QuothSpeech

final class SanitizeTests: XCTestCase {
    func testStripsNonSpeechTokens() {
        XCTAssertEqual(WhisperText.clean("[BLANK_AUDIO]"), "")
        XCTAssertEqual(WhisperText.clean("(silence)"), "")
        XCTAssertEqual(WhisperText.clean("<|nospeech|>"), "")
        XCTAssertEqual(WhisperText.clean("*background noise*"), "")
    }

    func testKeepsSpeechAndCollapsesWhitespace() {
        XCTAssertEqual(
            WhisperText.clean("  Hello [MUSIC]  there (music playing)\n world <|endoftext|> "),
            "Hello there world"
        )
    }

    func testLeavesPlainTextAlone() {
        XCTAssertEqual(WhisperText.clean("Ship it on Friday."), "Ship it on Friday.")
    }
}
