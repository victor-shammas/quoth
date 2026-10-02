import XCTest
@testable import QuothCore

final class PackagingTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("quoth-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - App role

    func testAppLaunchNeedsBundleNoArgumentsAndNoTerminal() {
        XCTAssertTrue(AppLaunch.isAppLaunch(arguments: ["quoth"], stdinIsTTY: false, inBundle: true))
        XCTAssertTrue(AppLaunch.isAppLaunch(arguments: ["quoth", "-psn_0_12345"], stdinIsTTY: false, inBundle: true))
        XCTAssertFalse(AppLaunch.isAppLaunch(arguments: ["quoth"], stdinIsTTY: true, inBundle: true))
        XCTAssertFalse(AppLaunch.isAppLaunch(arguments: ["quoth"], stdinIsTTY: false, inBundle: false))
        XCTAssertFalse(AppLaunch.isAppLaunch(arguments: ["quoth", "doctor"], stdinIsTTY: false, inBundle: true))
        XCTAssertFalse(AppLaunch.isAppLaunch(arguments: ["quoth", "--no-overlay"], stdinIsTTY: false, inBundle: true))
    }

    func testPermissionFailuresPointAtTheirPane() {
        XCTAssertEqual(AppLaunch.appMessage(for: .microphoneDenied).2, "Privacy_Microphone")
        XCTAssertNil(AppLaunch.appMessage(for: .noModelsRegistered).2)
        // The app's wording never sends the user to a terminal.
        for failure in [StartupFailure.microphoneDenied] {
            XCTAssertFalse(AppLaunch.appMessage(for: failure).1.contains("quoth setup"))
        }
    }

    // MARK: - Command line link

    func testLinkStates() throws {
        let target = dir.appendingPathComponent("Quoth.app/Contents/MacOS/quoth")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: target.path, contents: Data())
        let link = dir.appendingPathComponent("quoth")

        XCTAssertEqual(CommandLineLink.state(at: link, target: target), .missing)

        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertEqual(CommandLineLink.state(at: link, target: target), .linked)

        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "/Applications/Old/Quoth.app/Contents/MacOS/quoth")
        XCTAssertEqual(
            CommandLineLink.state(at: link, target: target),
            .linkedElsewhere("/Applications/Old/Quoth.app/Contents/MacOS/quoth")
        )

        try FileManager.default.removeItem(at: link)
        FileManager.default.createFile(atPath: link.path, contents: Data("old binary".utf8))
        XCTAssertEqual(CommandLineLink.state(at: link, target: target), .plainFile)

        try FileManager.default.removeItem(at: link)
        try FileManager.default.createDirectory(at: link, withIntermediateDirectories: false)
        XCTAssertEqual(CommandLineLink.state(at: link, target: target), .other)
    }

    func testInstallReplacesAPlainFileWithALink() throws {
        let target = dir.appendingPathComponent("target")
        FileManager.default.createFile(atPath: target.path, contents: Data())
        let link = dir.appendingPathComponent("quoth")
        FileManager.default.createFile(atPath: link.path, contents: Data("old binary".utf8))

        try CommandLineLink.install(at: link, target: target, privileged: false)
        XCTAssertEqual(CommandLineLink.state(at: link, target: target), .linked)
    }

    func testInstallRefusesAnUnwritableDirectoryWithoutPrivilege() {
        let link = URL(fileURLWithPath: "/System/quoth-test-link")
        XCTAssertThrowsError(try CommandLineLink.install(at: link, target: dir, privileged: false)) { error in
            guard case CommandLineLink.LinkError.notWritable = error else {
                return XCTFail("expected notWritable, got \(error)")
            }
        }
    }

    func testShellQuote() {
        XCTAssertEqual(CommandLineLink.shellQuote("/Applications/Quoth.app"), "'/Applications/Quoth.app'")
        XCTAssertEqual(CommandLineLink.shellQuote("it's"), "'it'\\''s'")
    }

    // MARK: - Paths

    func testPackagingPaths() {
        XCTAssertEqual(Paths.commandLineLink.path, "/usr/local/bin/quoth")
        XCTAssertEqual(Paths.instanceLock.deletingLastPathComponent().path, Paths.appSupport.path)
    }
}
