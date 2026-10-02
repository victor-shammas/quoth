import XCTest
@testable import QuothCore

@MainActor
final class ModelLoadStatusTests: XCTestCase {
    func testText() {
        typealias State = ModelLoadStatus.State
        XCTAssertEqual(State(modelID: "whisper-small", phase: .downloading(nil)).text, "Downloading Small…")
        XCTAssertEqual(State(modelID: "whisper-small", phase: .downloading(0.426)).text, "Downloading Small… 42%")
        XCTAssertEqual(State(modelID: "whisper-small", phase: .loading).text, "Getting Small ready…")
        XCTAssertEqual(State(modelID: "whisper-small", phase: .failed).text, "Couldn't load Small. Check your connection and choose it again.")
    }

    func testShowsWholePercentStepsOnly() {
        let status = ModelLoadStatus()
        var changes = 0
        let sink = status.objectWillChange.sink { changes += 1 }
        status.show(.init(modelID: "m", phase: .downloading(0.101)))
        status.show(.init(modelID: "m", phase: .downloading(0.104)))
        status.show(.init(modelID: "m", phase: .downloading(0.111)))
        status.show(nil)
        XCTAssertEqual(changes, 3)
        XCTAssertNil(status.current)
        _ = sink
    }
}
