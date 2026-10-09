import XCTest
@testable import QuothCore
@testable import QuothDomain
@testable import QuothPlatform

final class OnboardingTests: XCTestCase {
    private let granted = PermissionState(hotkey: true, microphone: .granted)
    private let missing = PermissionState(hotkey: false, microphone: .notDetermined)

    func testShowsOnceToEveryoneThenOnlyWhileAGrantIsMissing() {
        XCTAssertTrue(Onboarding.showsWindow(completed: false, state: granted))
        XCTAssertTrue(Onboarding.showsWindow(completed: false, state: missing))
        XCTAssertTrue(Onboarding.showsWindow(completed: true, state: missing))
        XCTAssertFalse(Onboarding.showsWindow(completed: true, state: granted))
    }

    func testOlderSettingsFilesHaveNotOnboarded() throws {
        let settings = try JSONDecoder().decode(Settings.self, from: Data(#"{"hotkey":{"key":"fn"}}"#.utf8))
        XCTAssertFalse(settings.onboarding.completed)
    }

    func testHotkeyChoicesKeepAKeyChosenInSettings() {
        XCTAssertEqual(Onboarding.hotkeyChoices(current: .fn), [.fn, .rightOption, .rightCommand, .rightControl])
        XCTAssertEqual(Onboarding.hotkeyChoices(current: .leftShift).last, .leftShift)
        // The App Store edition offers key combinations.
        XCTAssertEqual(Onboarding.hotkeyChoices(current: .optionSpace, shortcuts: true), HotkeyKey.shortcuts)
    }

    func testLanguageMenuListsTheMacsLanguagesFirstWithoutRepeats() {
        let menu = Onboarding.languageMenu(preferred: ["en", "es", "xx"])
        XCTAssertEqual(menu.mac, ["en", "es"])
        XCTAssertFalse(menu.common.contains("en"))
        XCTAssertFalse(menu.common.contains("es"))
        XCTAssertTrue(menu.common.contains("fr"))
        XCTAssertFalse(menu.more.contains("fr"))
        XCTAssertEqual(Set(menu.mac + menu.common + menu.more), WhisperLanguages.codes)
    }

    func testSummary() {
        XCTAssertEqual(Onboarding.summary([]), "None")
        XCTAssertEqual(Onboarding.summary(["English"]), "English")
        XCTAssertEqual(Onboarding.summary(["English", "Spanish"]), "English, Spanish")
        XCTAssertEqual(Onboarding.summary(["English", "Spanish", "French"]), "English +2")
    }

    func testTheMacsLanguagesLeaveTheListUnset() {
        let next = Onboarding.apply(hotkey: .rightOption, languages: ["es", "en"], preferred: ["en", "es"], to: Settings())
        XCTAssertNil(next.language.spoken)
        XCTAssertEqual(next.hotkey.key, .rightOption)
        XCTAssertTrue(next.onboarding.completed)
    }

    func testAChangedListIsSaved() {
        let next = Onboarding.apply(hotkey: .fn, languages: ["en", "fr"], preferred: ["en"], to: Settings())
        XCTAssertEqual(next.language.spoken, ["en", "fr"])
    }

    func testEnglishOnlyKeepsTheModel() {
        XCTAssertNil(Onboarding.apply(hotkey: .fn, languages: ["en"], preferred: ["en"], to: Settings()).model.id)
        var turbo = Settings()
        turbo.model.id = "whisper-large-v3-turbo"
        XCTAssertEqual(Onboarding.apply(hotkey: .fn, languages: ["en"], preferred: ["en"], to: turbo).model.id, "whisper-large-v3-turbo")
    }

    func testAnotherLanguageMovesAnEnglishOnlyModelToSmall() {
        XCTAssertEqual(Onboarding.apply(hotkey: .fn, languages: ["en", "es"], preferred: ["en"], to: Settings()).model.id, "whisper-small")
        var turbo = Settings()
        turbo.model.id = "whisper-large-v3-turbo"
        XCTAssertEqual(Onboarding.apply(hotkey: .fn, languages: ["es"], preferred: ["en"], to: turbo).model.id, "whisper-large-v3-turbo")
    }

    func testStartsWithTheMacsLanguages() {
        XCTAssertEqual(Onboarding.initialLanguages(saved: nil, preferred: ["en", "es"]), ["en", "es"])
        XCTAssertEqual(Onboarding.initialLanguages(saved: nil, preferred: ["xx", "es"]), ["es"])
        XCTAssertEqual(Onboarding.initialLanguages(saved: ["en", "fr"], preferred: ["en", "es"]), ["en", "fr"])
    }
}
