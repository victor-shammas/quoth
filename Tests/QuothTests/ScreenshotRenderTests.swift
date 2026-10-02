import AppKit
import SwiftUI
import XCTest
@testable import QuothCore

/// Renders Quoth's real UI for the App Store screenshots; skipped unless
/// QUOTH_RENDER_DIR is set. See AppStore/screenshots/compose.swift.
@MainActor
final class ScreenshotRenderTests: XCTestCase {
    var out: String { ProcessInfo.processInfo.environment["QUOTH_RENDER_DIR"] ?? "" }

    func save(_ view: NSView, _ name: String) throws {
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
        print("SAVED \(name) \(rep.pixelsWide)x\(rep.pixelsHigh)")
    }

    func testRender() async throws {
        guard !out.isEmpty else { throw XCTSkip("set QUOTH_RENDER_DIR to render the screenshots") }
        try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        NSApplication.shared.appearance = NSAppearance(named: .aqua)

        // The pill, recording and locked.
        for (state, name) in [(RecordingOverlay.State.recording, "pill-recording"), (.locked, "pill-locked")] {
            let model = OverlayModel()
            model.state = state
            for l: Float in [0.3, 0.6, 0.9, 0.7, 1.0, 0.8, 0.5, 0.75, 0.4, 0.6] { model.pushLevel(l) }
            // ImageRenderer, not a window capture: capturing draws a stray
            // edge from the pill's shadow layer.
            let renderer = ImageRenderer(content: OverlayPill(model: model).padding(40).environment(\.colorScheme, .light))
            renderer.scale = 2
            try await Task.sleep(nanoseconds: 300_000_000)
            let image = renderer.cgImage!
            let rep = NSBitmapImageRep(cgImage: image)
            try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
            print("SAVED \(name) \(rep.pixelsWide)x\(rep.pixelsHigh)")
        }

        // The Quote Card with a dictation in it.
        let card = QuoteCardModel()
        let cardHost = NSHostingView(rootView: QuoteCardView(model: card).frame(width: 520, height: 270))
        let cw = CardPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 270), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        cw.isOpaque = false; cw.backgroundColor = .clear; cw.contentView = cardHost; cw.makeKeyAndOrderFront(nil)
        try await Task.sleep(nanoseconds: 800_000_000)
        card.append("Hi Sam, thanks for the draft. I read it on the train this morning, and I think the second section is the strongest part.")
        card.append("Could we move the timeline up to the first page?")
        card.append("Let's talk on Thursday.")
        card.status = .locked
        try await Task.sleep(nanoseconds: 500_000_000)
        try save(cardHost, "card")
        cw.orderOut(nil)

        // Settings, with a dictionary filled in.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"dictionary":{"examples":{"en":"I asked Siobhan to send the Kubernetes notes to Dr. Okafor before the review."}}}"#.utf8).write(to: dir.appendingPathComponent("settings.json"))
        try Data("Word  Replaces\nSiobhan  Shivon, Shavonne\nKubernetes  Cooper Netties, Cube Ernettis\nDr. Okafor  doctor Okafor, Dr. O'Kafor\nPostgreSQL  postgres QL, post gress\nQuoth\n".utf8).write(to: dir.appendingPathComponent("dictionary"))
        let store = SettingsStore(file: dir.appendingPathComponent("settings.json"))
        let dictionary = DictionaryStore(file: dir.appendingPathComponent("dictionary"))
        let settings = SettingsWindow(store: store, dictionary: dictionary)
        for pane in [SettingsPane.dictionary, .model] {
            settings.show(pane: pane)
            try await Task.sleep(nanoseconds: 1_500_000_000)
            let window = NSApp.windows.first { $0.contentViewController is SettingsTabs }!
            try save(window.contentView!.superview!, "settings-\(pane.title.lowercased())")
        }

        // Fix Last Dictation.
        let fix = FixDictationWindow(dictionary: dictionary)
        fix.show(text: "I'll send the notes to Shavonne before Friday.")
        try await Task.sleep(nanoseconds: 1_200_000_000)
        let fw = NSApp.windows.first { $0.title == "Fix Last Dictation" }!
        try save(fw.contentView!.superview!, "fix")
    }
}
