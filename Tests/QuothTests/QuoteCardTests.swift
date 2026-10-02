import AppKit
import XCTest
@testable import QuothCore

@MainActor
final class QuoteCardTests: XCTestCase {
    private func model() -> QuoteCardModel {
        let model = QuoteCardModel()
        let view = NSTextView()
        view.typingAttributes = [.font: NSFont.systemFont(ofSize: 15)]
        model.textView = view
        return model
    }

    func testAppendSpacesLikeDictationsAndScratchRemovesTheLast() {
        let card = model()
        card.append("First thought.")
        card.append("Second thought.")
        XCTAssertEqual(card.text, "First thought. Second thought.")
        XCTAssertFalse(card.isEmpty)
        XCTAssertTrue(card.removeLastAppended())
        XCTAssertEqual(card.text, "First thought.")
        XCTAssertTrue(card.removeLastAppended())
        XCTAssertFalse(card.removeLastAppended())
        XCTAssertTrue(card.isEmpty)
    }

    func testAHandEditIsKeptAndScratchStaysInBounds() {
        let card = model()
        card.append("One two three.")
        // The user deletes most of it by hand.
        card.textView?.string = "One"
        card.textDidChange()
        XCTAssertFalse(card.removeLastAppended())
        XCTAssertEqual(card.text, "One")
    }

    func testLockTargetDecodes() throws {
        let decode = { (json: String) in try JSONDecoder().decode(Settings.self, from: Data(json.utf8)) }
        XCTAssertEqual(try decode("{}").hotkey.lockTarget, .cursor)
        XCTAssertEqual(try decode(#"{"hotkey": {"lockTarget": "card"}}"#).hotkey.lockTarget, .card)
        XCTAssertEqual(try decode(#"{"hotkey": {"lockTarget": "nowhere"}}"#).hotkey.lockTarget, .cursor)
    }
}
