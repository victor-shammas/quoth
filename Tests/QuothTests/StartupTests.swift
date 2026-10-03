import XCTest
@testable import QuothCore
@testable import QuothDomain

final class StartupTests: XCTestCase {
    func testTheModelIsTheOneNamed() {
        XCTAssertEqual(Startup.model(for: "whisper-small.en").id, "whisper-small.en")
    }

    func testNoModelNamedIsTheRecommendedOne() {
        XCTAssertEqual(Startup.model(for: nil), ModelRegistry.recommended)
    }

    func testAModelThatNoLongerExistsFallsBackRatherThanStoppingQuoth() {
        XCTAssertEqual(Startup.model(for: "no-such-model"), ModelRegistry.recommended)
    }

    func testTheMicrophoneMessageNamesTheFix() {
        XCTAssertTrue(StartupFailure.microphoneDenied.message.contains("Privacy & Security → Microphone"))
    }
}
