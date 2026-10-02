import AppKit
import SwiftUI

/// The panes of the Settings window, in toolbar order.
enum SettingsPane: Int, CaseIterable {
    case general, model, dictionary, help, about

    var title: String {
        switch self {
        case .general: return "General"
        case .model: return "Model"
        case .dictionary: return "Dictionary"
        case .help: return "Help"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .model: return "waveform"
        case .dictionary: return "character.book.closed"
        case .help: return "questionmark.circle"
        case .about: return "info.circle"
        }
    }
}

/// The Settings window, opened from the menu bar's Settings… (⌘,):
/// toolbar tabs, as in Apple's own Settings windows, each sized to its pane
/// so nothing scrolls but the dictionary's list. One instance: opening it
/// again brings the same window to the front, on the pane it was left on,
/// and closing it leaves Quoth running.
///
/// Controls write straight through to `settings.json` via `SettingsStore`
/// and the dictionary file via `DictionaryStore`, so the window holds no
/// state of its own (ADR-002).
@MainActor
final class SettingsWindow {
    private let store: SettingsStore
    private let dictionary: DictionaryStore
    private var window: NSWindow?
    private var tabs: SettingsTabs?

    init(store: SettingsStore, dictionary: DictionaryStore) {
        self.store = store
        self.dictionary = dictionary
    }

    /// Brings the window forward, on `pane` if given.
    func show(pane: SettingsPane? = nil) {
        let window = self.window ?? make()
        self.window = window
        if let pane { tabs?.selectedTabViewItemIndex = pane.rawValue }
        // An accessory app is never active on its own; without this the
        // window opens behind the frontmost app.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func make() -> NSWindow {
        let tabs = SettingsTabs()
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = [.crossfade, .allowUserInteraction]
        for pane in SettingsPane.allCases {
            let host = NSHostingController(rootView: view(for: pane))
            // The pane reports its height, and the window follows it.
            host.sizingOptions = [.preferredContentSize]
            host.title = pane.title
            let item = NSTabViewItem(viewController: host)
            item.label = pane.title
            item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)
            tabs.addTabViewItem(item)
        }
        self.tabs = tabs

        let window = EditingWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        // The latte background runs up under the title and the tabs.
        window.backgroundColor = Latte.windowBackground
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func view(for pane: SettingsPane) -> AnyView {
        switch pane {
        case .general: return AnyView(GeneralPane(store: store))
        case .model: return AnyView(ModelPane(store: store))
        case .dictionary: return AnyView(DictionaryPane(settings: store, dictionary: dictionary))
        case .help: return AnyView(HelpPane(store: store))
        case .about: return AnyView(AboutPane(store: store))
        }
    }
}

/// Resizes the window to the selected pane, keeping its top edge where it
/// is, as Apple's Settings windows do; and again when a pane grows, such as
/// when a download's progress line appears.
final class SettingsTabs: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        fit()
    }

    override func preferredContentSizeDidChange(for viewController: NSViewController) {
        super.preferredContentSizeDidChange(for: viewController)
        fit()
    }

    private func fit() {
        guard let window = view.window,
              tabViewItems.indices.contains(selectedTabViewItemIndex),
              let pane = tabViewItems[selectedTabViewItemIndex].viewController
        else { return }
        let size = pane.preferredContentSize
        guard size.height > 0 else { return }
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        let animate = window.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        window.setFrame(frame, display: true, animate: animate)
    }
}

/// The layout every pane shares: one width, the same margins, and a height
/// that is exactly its content's, which the window then takes.
struct Pane<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            content()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(width: 520, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(Latte.text)
        .tint(Latte.tint)
        .background(Latte.background)
    }
}

/// A small secondary line under a row or a group.
struct Caption: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Latte.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
