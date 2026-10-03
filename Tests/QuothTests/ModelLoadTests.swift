import XCTest
@testable import QuothDomain

final class ModelLoadTests: XCTestCase {
    func testText() {
        XCTAssertEqual(ModelLoad(modelID: "whisper-small", phase: .downloading(nil)).text, "Downloading Small…")
        XCTAssertEqual(ModelLoad(modelID: "whisper-small", phase: .downloading(0.426)).text, "Downloading Small… 42%")
        XCTAssertEqual(ModelLoad(modelID: "whisper-small", phase: .loading).text, "Getting Small ready…")
        XCTAssertEqual(ModelLoad(modelID: "whisper-small", phase: .failed).text, "Couldn't load Small. Check your connection and choose it again.")
    }

    func testOnlyWholePercentStepsReplace() {
        let at10 = ModelLoad(modelID: "m", phase: .downloading(0.101))
        XCTAssertTrue(ModelLoad.replaces(nil, with: at10))
        XCTAssertFalse(ModelLoad.replaces(at10, with: ModelLoad(modelID: "m", phase: .downloading(0.104))))
        XCTAssertTrue(ModelLoad.replaces(at10, with: ModelLoad(modelID: "m", phase: .downloading(0.111))))
    }

    func testALateDownloadReportNeverUndoesLoading() {
        let loading = ModelLoad(modelID: "m", phase: .loading)
        XCTAssertFalse(ModelLoad.replaces(loading, with: ModelLoad(modelID: "m", phase: .downloading(0.99))))
        XCTAssertTrue(ModelLoad.replaces(loading, with: ModelLoad(modelID: "other", phase: .downloading(nil))))
    }
}
