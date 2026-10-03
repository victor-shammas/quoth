import XCTest
@testable import QuothCore

final class UpdaterTests: XCTestCase {
    // A syntactically valid Ed25519 public key (32 zero bytes); never used to verify anything.
    private let key = Data(count: 32).base64EncodedString()
    private let feed = "https://github.com/victor-shammas/quoth/releases/latest/download/appcast.xml"

    private func info(version: String, key: String? = nil, feed: String? = nil) -> [String: Any] {
        var info: [String: Any] = ["CFBundleVersion": version]
        info["SUPublicEDKey"] = key ?? self.key
        info["SUFeedURL"] = feed ?? self.feed
        return info
    }

    func testAReleaseBuildWithARealKeyUpdates() {
        XCTAssertNil(Updater.configurationProblem(info: info(version: "0.1.0")))
        XCTAssertNil(Updater.configurationProblem(info: info(version: "12")))
    }

    func testDevelopmentBuildsDoNotUpdate() {
        for version in ["0.0.6-3-gabc1234", "0.0.6-3-gabc1234-dirty", "abc1234", "0.0.0.", "", "1..2"] {
            XCTAssertNotNil(Updater.configurationProblem(info: info(version: version)), version)
        }
        XCTAssertNotNil(Updater.configurationProblem(info: [:]))
    }

    func testThePlaceholderKeyTurnsUpdatesOff() {
        let placeholder = "REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY"
        XCTAssertNotNil(Updater.configurationProblem(info: info(version: "0.1.0", key: placeholder)))
        XCTAssertNotNil(Updater.configurationProblem(info: info(version: "0.1.0", key: Data(count: 16).base64EncodedString())))
    }

    func testTheFeedMustBeSet() {
        XCTAssertNotNil(Updater.configurationProblem(info: info(version: "0.1.0", feed: "not a url")))
    }

    func testThePackagedInfoPlistUpdatesReleasesFromThisRepository() throws {
        // packaging/Info.plist, found from this file: Tests/QuothTests/ → repo root.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("packaging/Info.plist"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["SUFeedURL"] as? String, "https://github.com/victor-shammas/quoth/releases/latest/download/appcast.xml")
        XCTAssertEqual(plist["SUEnableAutomaticChecks"] as? Bool, true)
        // A release updates; a development build (git describe) never does.
        XCTAssertNil(Updater.configurationProblem(info: plist.merging(["CFBundleVersion": "1.0.0"]) { $1 }))
        XCTAssertNotNil(Updater.configurationProblem(info: plist.merging(["CFBundleVersion": "1.0.0-3-gabc1234"]) { $1 }))
        // Its own ID, apart from the App Store edition's (ADR-005).
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "com.victorshammas.quoth.direct")
        XCTAssertTrue(AppBundle.identifiers.contains("com.victorshammas.quoth.direct"))
    }
}
