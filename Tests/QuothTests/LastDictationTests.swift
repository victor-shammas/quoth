import XCTest
@testable import QuothCore

@MainActor
final class LastDictationTests: XCTestCase {
    func testRemembersTrimmedTextAndForgets() {
        let last = LastDictation()
        var changes: [Bool] = []
        last.onChange = { changes.append($0) }
        last.remember("  ")
        XCTAssertNil(last.text)
        last.remember(" Hello there. ")
        XCTAssertEqual(last.text, "Hello there.")
        last.forget()
        XCTAssertNil(last.text)
        last.forget()
        XCTAssertEqual(changes, [true, false])
    }
}
