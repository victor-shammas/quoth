import XCTest
@testable import QuothDomain

/// Live text's bookkeeping, segment by segment (ADR-007 §3, rule 10).
final class LiveTextLedgerTests: XCTestCase {
    /// Adds and delivers `segments`, as `LiveTranscription` does.
    private func typed(_ segments: [String]) -> LiveTextLedger {
        var ledger = LiveTextLedger()
        for segment in segments where ledger.add(segment) {
            ledger.delivered(segment)
        }
        return ledger
    }

    func testSegmentsAreDeliveredAndJoined() {
        let ledger = typed(["One.", "Two."])
        XCTAssertEqual(ledger.text, "One. Two.")
        XCTAssertEqual(ledger.chars, 8)
        XCTAssertNil(ledger.heldText)
    }

    func testAnEmptySegmentIsNotDelivered() {
        var ledger = LiveTextLedger()
        XCTAssertFalse(ledger.add(""))
        XCTAssertEqual(ledger.chars, 0)
    }

    func testAfterAFocusChangeTheRestIsHeldForTheClipboard() {
        var ledger = typed(["One."])
        XCTAssertTrue(ledger.add("Two."))
        ledger.deliveryFailed("Two.", error: .focusChanged)
        XCTAssertFalse(ledger.add("Three."))
        XCTAssertEqual(ledger.heldText, "Two. Three.")
        XCTAssertEqual(ledger.deliveryError, .focusChanged)
        // Copy Last Dictation still gets all of it.
        XCTAssertEqual(ledger.text, "One. Two. Three.")
    }

    func testAfterAnUnreadPasteTheRestIsHeldForTheClipboard() {
        var ledger = typed(["One."])
        XCTAssertTrue(ledger.add("Two."))
        ledger.deliveryFailed("Two.", error: .notPasted)
        XCTAssertFalse(ledger.add("Three."))
        XCTAssertEqual(ledger.heldText, "Two. Three.")
        XCTAssertEqual(ledger.deliveryError, .notPasted)
    }

    func testAfterAPasswordFieldNothingMoreIsDeliveredOrHeld() {
        var ledger = typed(["One."])
        XCTAssertTrue(ledger.add("Two."))
        ledger.deliveryFailed("Two.", error: .secureField)
        XCTAssertFalse(ledger.add("Three."))
        XCTAssertNil(ledger.heldText)
        XCTAssertEqual(ledger.deliveryError, .secureField)
    }

    func testAnyOtherFailureStopsDeliveryWithoutHolding() {
        var ledger = LiveTextLedger()
        XCTAssertTrue(ledger.add("One."))
        ledger.deliveryFailed("One.", error: nil)
        XCTAssertFalse(ledger.isDelivering)
        XCTAssertNil(ledger.deliveryError)
        XCTAssertFalse(ledger.add("Two."))
        XCTAssertNil(ledger.heldText)
    }

    func testScratchThatRemovesTheLastTypedSegment() {
        var ledger = typed(["One.", "Two."])
        XCTAssertTrue(ledger.scratch())
        ledger.scratched()
        XCTAssertEqual(ledger.text, "One.")
    }

    func testScratchThatAfterAFocusChangeDropsTheLastHeldSegment() {
        var ledger = typed(["One."])
        _ = ledger.add("Two.")
        ledger.deliveryFailed("Two.", error: .focusChanged)
        _ = ledger.add("Three.")
        XCTAssertFalse(ledger.scratch())
        XCTAssertEqual(ledger.heldText, "Two.")
    }

    func testScratchThatWithNothingTypedLeavesTheText() {
        var ledger = LiveTextLedger()
        XCTAssertTrue(ledger.scratch())
        ledger.scratched()
        XCTAssertEqual(ledger.text, "")
    }

    func testJoinSpacesLikeDictations() {
        XCTAssertEqual(LiveTextLedger.join(["One.", "Two."]), "One. Two.")
        XCTAssertEqual(LiveTextLedger.join(["今日は", "晴れです"]), "今日は晴れです")
        XCTAssertEqual(LiveTextLedger.join(["Hi", ", there"]), "Hi, there")
    }
}
