import XCTest
@testable import QuothDomain

final class TextBeforeCursorTests: XCTestCase {
    private func read(_ location: Int, length: Int? = nil, before: String? = nil, value: String? = nil) -> TextBeforeCursor {
        .reading(location: location, fieldLength: length, before: before, value: { value })
    }

    func testTheStartOfAnEmptyField() {
        XCTAssertEqual(read(0, length: 0), .start)
    }

    func testZeroInAFieldWithTextIsUnknownAsInGhostty() {
        XCTAssertEqual(read(0, length: 12), .unknown)
        XCTAssertEqual(read(0), .unknown)
    }

    func testTheCharacterTheAppGivesForTheRange() {
        XCTAssertEqual(read(5, before: "o!"), .character("!"))
    }

    func testAnEmojiIsReadWholeFromTwoUnits() {
        XCTAssertEqual(read(2, before: "👍"), .character("👍"))
        // "Great " is six UTF-16 units and the emoji two.
        XCTAssertEqual(read(8, value: "Great 👍 thanks"), .character("👍"))
    }

    func testHalfAnEmojiIsUnknownRatherThanAGuess() {
        XCTAssertEqual(read(7, value: "Great 👍 thanks"), .unknown)
    }

    func testTheWholeValueWhenTheAppDoesntAnswerForARange() {
        XCTAssertEqual(read(5, value: "Hello world"), .character("o"))
        XCTAssertEqual(read(1, value: "H"), .character("H"))
    }

    func testAPositionPastTheTextIsUnknown() {
        XCTAssertEqual(read(20, value: "short"), .unknown)
        XCTAssertEqual(read(3), .unknown)
    }
}
