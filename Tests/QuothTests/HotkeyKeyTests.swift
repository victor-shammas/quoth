import XCTest
@testable import QuothDomain
@testable import QuothPlatform
import Carbon.HIToolbox

final class HotkeyKeyTests: XCTestCase {
    func testNamesAndKeycodes() {
        let expected: [HotkeyKey: (String, String, Int64)] = [
            .fn: ("fn", "fn", 63),
            .leftOption: ("Left Option (⌥)", "left ⌥", 58),
            .rightOption: ("Right Option (⌥)", "right ⌥", 61),
            .leftCommand: ("Left Command (⌘)", "left ⌘", 55),
            .rightCommand: ("Right Command (⌘)", "right ⌘", 54),
            .leftControl: ("Left Control (⌃)", "left ⌃", 59),
            .rightControl: ("Right Control (⌃)", "right ⌃", 62),
            .leftShift: ("Left Shift (⇧)", "left ⇧", 56),
            .rightShift: ("Right Shift (⇧)", "right ⇧", 60),
            .optionSpace: ("⌥Space", "⌥Space", 49),
            .controlOptionSpace: ("⌃⌥Space", "⌃⌥Space", 49),
            .optionShiftSpace: ("⌥⇧Space", "⌥⇧Space", 49),
            .commandShiftSpace: ("⇧⌘Space", "⇧⌘Space", 49),
        ]
        XCTAssertEqual(Set(expected.keys), Set(HotkeyKey.allCases))
        for (key, (display, short, keycode)) in expected {
            XCTAssertEqual(key.displayName, display)
            XCTAssertEqual(key.shortName, short)
            XCTAssertEqual(key.keycode, keycode)
        }
    }

    func testEachEditionOffersItsOwnKind() {
        XCTAssertEqual(HotkeyKey.choices(shortcuts: false), HotkeyKey.modifierKeys)
        XCTAssertEqual(HotkeyKey.choices(shortcuts: true), HotkeyKey.shortcuts)
        XCTAssertEqual(Set(HotkeyKey.modifierKeys + HotkeyKey.shortcuts), Set(HotkeyKey.allCases))
        XCTAssertTrue(HotkeyKey.shortcuts.allSatisfy { $0.isShortcut && !$0.shortcutModifiers.isEmpty })
        XCTAssertTrue(HotkeyKey.modifierKeys.allSatisfy { !$0.isShortcut && $0.shortcutModifiers.isEmpty })
    }

    func testAKeyTheEditionCantUseFallsBackToItsDefault() {
        // The App Store edition can't watch modifier keys (Guideline 2.4.5(v)).
        XCTAssertEqual(HotkeyKey.fn.usable(shortcuts: true), .optionSpace)
        XCTAssertEqual(HotkeyKey.rightOption.usable(shortcuts: true), .optionSpace)
        XCTAssertEqual(HotkeyKey.controlOptionSpace.usable(shortcuts: true), .controlOptionSpace)
        XCTAssertEqual(HotkeyKey.optionSpace.usable(shortcuts: false), .fn)
        XCTAssertEqual(HotkeyKey.rightCommand.usable(shortcuts: false), .rightCommand)
    }

    func testCombinationsRegisterWithTheirModifiers() {
        XCTAssertEqual(GlobalShortcut.carbonModifiers(HotkeyKey.optionSpace.shortcutModifiers), UInt32(optionKey))
        XCTAssertEqual(GlobalShortcut.carbonModifiers(HotkeyKey.controlOptionSpace.shortcutModifiers), UInt32(controlKey | optionKey))
        XCTAssertEqual(GlobalShortcut.carbonModifiers(HotkeyKey.commandShiftSpace.shortcutModifiers), UInt32(cmdKey | shiftKey))
        XCTAssertEqual(UInt32(HotkeyKey.optionSpace.keycode), UInt32(kVK_Space))
        // A modifier key can't be registered as a combination.
        XCTAssertFalse(GlobalShortcut().register(.fn))
    }

    func testAnUnknownKeyInTheFileFallsBackToFn() throws {
        let settings = try JSONDecoder().decode(HotkeySettings.self, from: Data(#"{"key":"caps-lock","liveText":false}"#.utf8))
        XCTAssertEqual(settings.key, .fn)
        XCTAssertFalse(settings.liveText)
    }

    func testModelsHaveUniqueIDsAndTheRecommendedOneIsEnglish() {
        XCTAssertEqual(Set(ModelRegistry.all.map(\.id)).count, ModelRegistry.all.count)
        XCTAssertEqual(ModelRegistry.recommended.onlyLanguage, "en")
        XCTAssertTrue(ModelRegistry.find("whisper-large-v3-turbo")!.isMultilingual)
    }

    func testModelNamesAndSummary() {
        let base = ModelRegistry.find("whisper-base.en")!
        XCTAssertEqual(base.name, "Base (English)")
        XCTAssertEqual(base.shortName, "Base")
        XCTAssertEqual(base.summary, "Fastest · English only · 145 MB")
        let turbo = ModelRegistry.find("whisper-large-v3-turbo")!
        XCTAssertEqual(turbo.name, "Large v3 Turbo")
        XCTAssertEqual(turbo.summary, "Most accurate, slowest · Multilingual · 1.6 GB")
    }
}
