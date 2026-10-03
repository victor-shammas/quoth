import AVFoundation
import XCTest
@testable import QuothCore
@testable import QuothDomain
@testable import QuothPlatform

final class PermissionsTests: XCTestCase {
    private func state(_ hotkey: Bool, _ microphone: MicrophonePermission) -> PermissionState {
        PermissionState(hotkey: hotkey, microphone: microphone)
    }

    func testMicrophoneStatusMapping() {
        XCTAssertEqual(MicrophonePermission(.authorized), .granted)
        XCTAssertEqual(MicrophonePermission(.notDetermined), .notDetermined)
        XCTAssertEqual(MicrophonePermission(.denied), .denied)
        XCTAssertEqual(MicrophonePermission(.restricted), .denied)
    }

    func testAllGrantedNeedsBoth() {
        XCTAssertTrue(state(true, .granted).allGranted)
        XCTAssertFalse(state(false, .granted).allGranted)
        XCTAssertFalse(state(true, .notDetermined).allGranted)
        XCTAssertFalse(state(true, .denied).allGranted)
    }

    func testMicrophoneAllowAsksOnceThenOpensItsPane() {
        XCTAssertEqual(Permissions.allowSteps(for: .microphone, in: state(false, .notDetermined)), [.requestMicrophone])
        XCTAssertEqual(Permissions.allowSteps(for: .microphone, in: state(false, .denied)), [.openMicrophoneSettings])
        XCTAssertEqual(Permissions.allowSteps(for: .microphone, in: state(false, .granted)), [])
    }

    func testAccessibilityAllowPromptsAndOpensItsPane() {
        XCTAssertEqual(
            Permissions.allowSteps(for: .hotkey, in: state(false, .granted)),
            [.promptHotkey, .openHotkeySettings]
        )
        XCTAssertEqual(Permissions.allowSteps(for: .hotkey, in: state(true, .notDetermined)), [])
    }

    func testOnlyAppStoreEventGrantsNeedARelaunch() {
        // The direct edition reads its grants live; this is it.
        XCTAssertFalse(Permissions.showsAfterRelaunch(.microphone))
        XCTAssertEqual(Permissions.showsAfterRelaunch(.hotkey), Edition.isAppStore)
        XCTAssertEqual(Permissions.showsAfterRelaunch(.paste), Edition.isAppStore)
    }
}
