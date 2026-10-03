import XCTest
@testable import QuothDomain

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
        ]
        XCTAssertEqual(Set(expected.keys), Set(HotkeyKey.allCases))
        for (key, (display, short, keycode)) in expected {
            XCTAssertEqual(key.displayName, display)
            XCTAssertEqual(key.shortName, short)
            XCTAssertEqual(key.keycode, keycode)
        }
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
