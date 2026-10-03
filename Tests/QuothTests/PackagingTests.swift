import XCTest
@testable import QuothCore
@testable import QuothPlatform

final class PackagingTests: XCTestCase {
    // MARK: - Startup dialogs

    func testTheMicrophoneDialogOpensItsPane() {
        let message = AppLaunch.appMessage(for: .microphoneDenied)
        XCTAssertEqual(message.pane, "Privacy_Microphone")
        // It never sends the user to a terminal.
        XCTAssertFalse(message.body.contains("`quoth"))
    }

    // MARK: - Developer options

    func testDeveloperOptionsDefaultToTheShippedBehaviour() {
        let options = DeveloperOptions.from([:])
        XCTAssertFalse(options.debugHotkey)
        XCTAssertFalse(options.dumpWav)
        XCTAssertEqual(options.injectMode, .paste)
        XCTAssertEqual(options.captureMode, .standard)
    }

    func testDeveloperOptionsFromTheEnvironment() {
        let options = DeveloperOptions.from([
            "QUOTH_DEBUG_HOTKEY": "1",
            "QUOTH_DUMP_WAV": "1",
            "QUOTH_INJECT_MODE": "type-unicode",
        ])
        XCTAssertTrue(options.debugHotkey)
        XCTAssertTrue(options.dumpWav)
        XCTAssertEqual(options.injectMode, .typeUnicode)
    }

    func testAnUnknownDeveloperOptionKeepsTheDefault() {
        let options = DeveloperOptions.from(["QUOTH_INJECT_MODE": "telepathy", "QUOTH_CAPTURE": "?"])
        XCTAssertEqual(options.injectMode, .paste)
        XCTAssertEqual(options.captureMode, .standard)
    }

    // MARK: - Paths

    func testTheInstanceLockOutlivesTheCaches() {
        XCTAssertEqual(Paths.instanceLock.deletingLastPathComponent().path, Paths.appSupport.path)
    }
}
