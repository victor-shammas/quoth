import XCTest
@testable import QuothCore
@testable import QuothDomain

final class AppModelTests: XCTestCase {
    func testIdleTellsTheUserWhichKeyToHold() {
        XCTAssertEqual(AppModel.statusText(.idle, hotkey: .fn, health: .ok), "Ready — hold fn to dictate")
        XCTAssertEqual(AppModel.statusText(.idle, hotkey: .rightOption, health: .ok), "Ready — hold \(HotkeyKey.rightOption.shortName) to dictate")
    }

    func testABrokenHotkeyReplacesTheIdleLine() {
        for health in [HotkeyHealth.secureInputActive, .tapDisabled, .accessibilityMissing, .modelLoading, .modelFailed] {
            XCTAssertEqual(AppModel.statusText(.idle, hotkey: .fn, health: health), health.statusText)
        }
    }

    func testADictationShowsWhatItIsDoing() {
        XCTAssertEqual(AppModel.statusText(.recording, hotkey: .fn, health: .ok), "Recording…")
        XCTAssertEqual(AppModel.statusText(.locked, hotkey: .fn, health: .ok), "Locked — tap fn to stop")
        XCTAssertEqual(AppModel.statusText(.transcribing, hotkey: .fn, health: .ok), "Transcribing…")
    }

    func testADictationOutranksTheHotkeyHealth() {
        XCTAssertEqual(AppModel.statusText(.recording, hotkey: .fn, health: .secureInputActive), "Recording…")
    }
}
