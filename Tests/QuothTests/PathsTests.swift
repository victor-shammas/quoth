import XCTest
@testable import QuothCore
@testable import QuothPlatform
@testable import QuothSpeech

final class PathsTests: XCTestCase {
    func testFilesLiveUnderTheirDirectories() {
        XCTAssertEqual(Paths.settingsFile.deletingLastPathComponent().path, Paths.config.path)
        XCTAssertEqual(Paths.dictionaryFile.deletingLastPathComponent().path, Paths.config.path)
        XCTAssertEqual(Paths.dictionaryFile.lastPathComponent, "dictionary")
        XCTAssertEqual(Paths.outLog.deletingLastPathComponent().path, Paths.logs.path)
        XCTAssertEqual(Paths.errLog.deletingLastPathComponent().path, Paths.logs.path)
        XCTAssertEqual(Paths.dumpWav.deletingLastPathComponent().path, Paths.caches.path)
    }

    func testNothingLivesInTmpOrDocuments() {
        let all = [
            Paths.config, Paths.appSupport, Paths.logs, Paths.caches, Paths.settingsFile, Paths.dictionaryFile,
            Paths.outLog, Paths.errLog, Paths.dumpWav,
        ]
        for url in all {
            XCTAssertFalse(url.path.hasPrefix("/tmp"), url.path)
            XCTAssertFalse(url.path.hasPrefix(Paths.documents.path), url.path)
        }
    }
}

final class InstanceLockTests: XCTestCase {
    func testOneCopyHoldsTheLockUntilItLetsGo() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("quoth-lock-\(UUID().uuidString)/quoth.lock")
        do {
            let first = InstanceLock.claim(file)
            guard case .held = first else { return XCTFail("expected to hold the lock") }
            guard case .heldElsewhere = InstanceLock.claim(file) else { return XCTFail("a second copy must be refused") }
            withExtendedLifetime(first) {}
        }
        guard case .held = InstanceLock.claim(file) else { return XCTFail("the lock should be free once released") }
    }
}
