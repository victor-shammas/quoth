import AppKit
import SwiftUI
import XCTest
@testable import QuothCore

/// Each Settings pane sizes the window to itself and never scrolls, so each
/// must fit a small laptop screen.
@MainActor
final class SettingsPaneTests: XCTestCase {
    func testEveryPaneFitsASmallScreen() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: dir.appendingPathComponent("settings.json"))
        let store = SettingsStore(file: dir.appendingPathComponent("settings.json"), log: { _ in })
        let dictionary = DictionaryStore(file: dir.appendingPathComponent("dictionary"), log: { _ in })
        let panes: [(String, AnyView)] = [
            ("General", AnyView(GeneralPane(store: store))),
            ("Model", AnyView(ModelPane(store: store))),
            ("Dictionary", AnyView(DictionaryPane(settings: store, dictionary: dictionary))),
            ("Help", AnyView(HelpPane(store: store))),
            ("About", AnyView(AboutPane(store: store))),
        ]
        for (name, view) in panes {
            let height = NSHostingView(rootView: view).fittingSize.height
            XCTAssertGreaterThan(height, 100, name)
            XCTAssertLessThan(height, 640, "\(name) is \(height) pt tall; it would need to scroll on a small screen")
        }
    }
}
