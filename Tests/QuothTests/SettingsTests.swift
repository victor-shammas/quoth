import XCTest
@testable import QuothCore

final class SettingsTests: XCTestCase {
    private func decode(_ json: String) throws -> Settings {
        try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
    }

    func testEmptyObjectDecodesToDefaults() throws {
        XCTAssertEqual(try decode("{}"), Settings())
    }

    func testPartialObjectDecodesMissingKeysToDefaults() throws {
        XCTAssertEqual(try decode(#"{"hotkey": {}, "stats": {}}"#), Settings())
    }

    func testUnknownKeysAreIgnored() throws {
        XCTAssertEqual(try decode(#"{"fromTheFuture": 1}"#), Settings())
    }

    func testRoundTrips() throws {
        let data = try JSONEncoder().encode(Settings())
        XCTAssertEqual(try JSONDecoder().decode(Settings.self, from: data), Settings())
    }
}

final class SettingsFieldTests: XCTestCase {
    private func decode(_ json: String) throws -> Settings {
        try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
    }

    func testHotkeyDecodesByName() throws {
        XCTAssertEqual(try decode(#"{"hotkey": {"key": "right-option"}}"#).hotkey.key, .rightOption)
    }

    func testDoubleTapLockDefaultsOnAndDecodes() throws {
        XCTAssertTrue(try decode("{}").hotkey.doubleTapLock)
        XCTAssertFalse(try decode(#"{"hotkey": {"doubleTapLock": false}}"#).hotkey.doubleTapLock)
        XCTAssertTrue(try decode("{}").hotkey.liveText)
        XCTAssertFalse(try decode(#"{"hotkey": {"liveText": false}}"#).hotkey.liveText)
    }

    func testUnknownHotkeyFallsBackToFn() throws {
        XCTAssertEqual(try decode(#"{"hotkey": {"key": "caps-lock"}}"#).hotkey.key, .fn)
    }

    func testModelAndLanguageDefaultToNil() throws {
        let settings = try decode("{}")
        XCTAssertNil(settings.model.id)
        XCTAssertNil(settings.language.code)
    }

    func testSpokenLanguagesDecodeAndDefaultToTheMac() throws {
        XCTAssertNil(try decode("{}").language.spoken)
        XCTAssertEqual(try decode("{}").language.spokenOrPreferred, SpokenLanguage.preferredCodes())
        let settings = try decode(#"{"language": {"spoken": ["en", "es"]}}"#)
        XCTAssertEqual(settings.language.spoken, ["en", "es"])
        XCTAssertEqual(settings.language.spokenOrPreferred, ["en", "es"])
    }

    func testModelAndLanguageDecode() throws {
        let settings = try decode(#"{"model": {"id": "whisper-large-v3-turbo"}, "language": {"code": "pt"}}"#)
        XCTAssertEqual(settings.model.id, "whisper-large-v3-turbo")
        XCTAssertEqual(settings.language.code, "pt")
    }

    func testDictionaryExamplesDecodeAndDefaultToEmpty() throws {
        XCTAssertEqual(try decode("{}").dictionary.examples, [:])
        XCTAssertEqual(try decode(#"{"dictionary": {}}"#).dictionary.examples, [:])
        let settings = try decode(#"{"dictionary": {"examples": {"en": "One sentence.", "pt-BR": "Uma frase."}}}"#)
        XCTAssertEqual(settings.dictionary.examples, ["en": "One sentence.", "pt-BR": "Uma frase."])
    }
}

@MainActor
final class SettingsStoreTests: XCTestCase {
    private var dir: URL!
    private var logged: [String] = []

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("quoth-settings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        logged = []
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func store(_ file: URL? = nil) -> SettingsStore {
        SettingsStore(file: file ?? dir.appendingPathComponent("settings.json")) { [weak self] in self?.logged.append($0) }
    }

    private func put(_ json: String, _ name: String = "settings.json") throws {
        try Data(json.utf8).write(to: dir.appendingPathComponent(name))
    }

    func testMissingFileLoadsDefaults() {
        XCTAssertEqual(store().current, Settings())
        XCTAssertTrue(logged.isEmpty)
    }

    func testLoadsExistingFile() throws {
        try put(#"{"hotkey": {"key": "left-command"}}"#)
        XCTAssertEqual(store().current.hotkey.key, .leftCommand)
    }

    func testWriteRoundTripsAndNotifies() throws {
        let s = store()
        var seen: [(Settings, Settings)] = []
        s.observe { seen.append(($0, $1)) }
        s.update { $0.hotkey.key = .rightShift }
        XCTAssertEqual(seen.count, 1)
        XCTAssertEqual(seen.first?.1.hotkey.key, .rightShift)
        XCTAssertEqual(store().current.hotkey.key, .rightShift)
        let mode = try FileManager.default.attributesOfItem(atPath: s.file.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
    }

    func testUnchangedWriteDoesNotNotify() {
        let s = store()
        var count = 0
        s.observe { _, _ in count += 1 }
        s.write(Settings())
        XCTAssertEqual(count, 0)
    }

    func testMalformedEditKeepsLastGoodAndLogsOnce() throws {
        try put(#"{"hotkey": {"key": "right-option"}}"#)
        let s = store()
        try put(#"{"hotkey": "#)
        s.reload()
        s.reload()
        XCTAssertEqual(s.current.hotkey.key, .rightOption)
        XCTAssertEqual(logged.count, 1)
        try put(#"{"hotkey": {"key": "left-option"}}"#)
        s.reload()
        XCTAssertEqual(s.current.hotkey.key, .leftOption)
    }

    func testHandEditNotifiesObservers() throws {
        let s = store()
        var latest: Settings?
        s.observe { _, new in latest = new }
        try put(#"{"language": {"code": "es"}}"#)
        s.reload()
        XCTAssertEqual(latest?.language.code, "es")
    }

    func testWriteKeepsASymlinkedFile() throws {
        let target = dir.appendingPathComponent("dotfiles-settings.json")
        try put("{}", "dotfiles-settings.json")
        let link = dir.appendingPathComponent("settings.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let s = store(link)
        s.update { $0.hotkey.key = .rightCommand }
        XCTAssertEqual(Paths.fileType(link.path), .typeSymbolicLink)
        let saved = try JSONDecoder().decode(Settings.self, from: Data(contentsOf: target))
        XCTAssertEqual(saved.hotkey.key, .rightCommand)
    }

    func testUnknownSavedModelFallsBack() {
        XCTAssertNil(Daemon.knownModel("no-such-model"))
        XCTAssertEqual(Daemon.knownModel("whisper-base.en"), "whisper-base.en")
        XCTAssertNil(Daemon.knownModel(nil))
    }
}

final class SettingsResetTests: XCTestCase {
    func testResetKeepsWhatIsTheUsersOwn() {
        var settings = Settings()
        settings.hotkey.key = .rightOption
        settings.hotkey.liveText = false
        settings.model.id = "whisper-small"
        settings.dictionary.examples = ["en": "I pushed the WhisperKit fix."]
        settings.language.spoken = ["en", "de"]
        settings.onboarding.completed = true
        let reset = settings.reset()
        XCTAssertEqual(reset.hotkey, HotkeySettings())
        XCTAssertNil(reset.model.id)
        XCTAssertEqual(reset.dictionary.examples, ["en": "I pushed the WhisperKit fix."])
        XCTAssertEqual(reset.language.spoken, ["en", "de"])
        XCTAssertTrue(reset.onboarding.completed)
    }
}

@MainActor
final class SettingsStoreSafetyTests: XCTestCase {
    func testAChangeNeverOverwritesAFileWithAMistake() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try Data(#"{"hotkey": {"key": "right-option"}}"#.utf8).write(to: file)
        let store = SettingsStore(file: file, log: { _ in })
        // A hand edit in progress.
        try Data(#"{"hotkey": {"key": "right-option",}"#.utf8).write(to: file)
        store.update { $0.hotkey.liveText = false }
        XCTAssertFalse(store.current.hotkey.liveText)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), #"{"hotkey": {"key": "right-option",}"#)
    }
}

