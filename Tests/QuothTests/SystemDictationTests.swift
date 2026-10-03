import XCTest
@testable import QuothDomain
@testable import QuothPlatform

final class SystemDictationTests: XCTestCase {
    /// System hotkey 164 as macOS stores "Press 🌐 twice".
    private func hotkeys(modifier: UInt64, enabled: Int = 1, type: String = "modifier") -> [String: Any] {
        ["164": ["enabled": enabled, "value": ["type": type, "parameters": [modifier, 4_286_578_687]]]]
    }

    func testPressFnTwiceClashesWithFn() {
        XCTAssertEqual(SystemDictation.clash(with: .fn, dictationEnabled: true, hotkeys: hotkeys(modifier: 0x800000)), .clashes)
    }

    func testItDoesntClashWithAnotherModifier() {
        XCTAssertEqual(SystemDictation.clash(with: .rightOption, dictationEnabled: true, hotkeys: hotkeys(modifier: 0x800000)), .none)
    }

    func testPressCommandTwiceClashesWithEitherCommand() {
        XCTAssertEqual(SystemDictation.clash(with: .rightCommand, dictationEnabled: true, hotkeys: hotkeys(modifier: 0x100000)), .clashes)
        XCTAssertEqual(SystemDictation.clash(with: .leftCommand, dictationEnabled: true, hotkeys: hotkeys(modifier: 0x100000)), .clashes)
    }

    func testNoClashWhenDictationOrItsShortcutIsOff() {
        XCTAssertEqual(SystemDictation.clash(with: .fn, dictationEnabled: false, hotkeys: hotkeys(modifier: 0x800000)), .none)
        XCTAssertEqual(SystemDictation.clash(with: .fn, dictationEnabled: true, hotkeys: hotkeys(modifier: 0x800000, enabled: 0)), .none)
        XCTAssertEqual(SystemDictation.clash(with: .fn, dictationEnabled: true, hotkeys: [:]), .none)
    }

    func testAKeyComboShortcutDoesntClash() {
        XCTAssertEqual(SystemDictation.clash(with: .fn, dictationEnabled: true, hotkeys: hotkeys(modifier: 0x800000, type: "standard")), .none)
    }

    func testUnreadableSettingsAreUnknown() {
        XCTAssertEqual(SystemDictation.clash(with: .fn, dictationEnabled: nil, hotkeys: nil), .unknown)
    }

    func testThisMacReadsAsSomething() {
        // The real settings parse without crashing, whatever they say.
        _ = SystemDictation.clash(with: .fn)
    }
}
