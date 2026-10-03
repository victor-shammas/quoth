import AppKit
import QuothDomain
import QuothPlatform
import SwiftUI

// Views the onboarding and Settings windows share.

/// The app icon, for the onboarding and Settings headers. Outside the app
/// bundle (a foreground `swift run`) it falls back to the menu-bar glyph.
struct AppBadge: View {
    var size: CGFloat = 64

    var body: some View {
        Image(nsImage: AppBundle.current != nil ? NSApplication.shared.applicationIconImage : QuoteGlyph.image(.recording))
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

/// Checkboxes for the languages the user speaks, in a popover so ticks stay
/// open between clicks, which a menu can't do: the Mac's languages, the
/// common ones, then More Languages (`Onboarding.languageMenu`).
struct LanguageChecklist<Footer: View>: View {
    let ticked: [String]
    let toggle: (String) -> Void
    @ViewBuilder var footer: () -> Footer
    @State private var showsMore = false

    private let menu = Onboarding.languageMenu(preferred: SpokenLanguage.preferredCodes())

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                rows(menu.mac)
                if !menu.mac.isEmpty { Divider().padding(.vertical, 2) }
                rows(menu.common)
                Divider().padding(.vertical, 2)
                DisclosureGroup("More Languages", isExpanded: $showsMore) {
                    VStack(alignment: .leading, spacing: 6) {
                        rows(menu.more)
                    }
                    .padding(.top, 6)
                }
                footer()
            }
            .padding(14)
        }
        .frame(width: 240, height: 340)
    }

    private func rows(_ codes: [String]) -> some View {
        ForEach(codes, id: \.self) { code in
            Toggle(SpokenLanguage.displayName(code), isOn: Binding(
                get: { ticked.contains(code) },
                set: { _ in toggle(code) }
            ))
            .toggleStyle(.checkbox)
        }
    }
}

extension LanguageChecklist where Footer == EmptyView {
    init(ticked: [String], toggle: @escaping (String) -> Void) {
        self.init(ticked: ticked, toggle: toggle, footer: { EmptyView() })
    }
}

/// Watches for macOS Dictation's shortcut sharing `key`, which starts Apple's
/// Dictation along with Quoth's hands-free lock (`SystemDictation`). Looked
/// up again whenever Quoth comes back to the front, as after the user has
/// been to System Settings.
struct DictationClash<Content: View>: View {
    let key: HotkeyKey
    @ViewBuilder let content: (SystemDictation.Clash) -> Content
    @State private var clash = SystemDictation.Clash.none

    var body: some View {
        content(clash)
            .onAppear { clash = SystemDictation.clash(with: key) }
            .onChange(of: key) { _, key in clash = SystemDictation.clash(with: key) }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                clash = SystemDictation.clash(with: key)
            }
    }
}

/// The row that says macOS Dictation will start too, and opens the setting
/// that stops it.
struct DictationClashRow: View {
    let key: HotkeyKey

    var body: some View {
        SettingRow(
            "macOS Dictation shares this key",
            caption: "A double press of \(key.shortName) starts Apple's Dictation too. Turn its shortcut off in Keyboard › Dictation."
        ) {
            Button("Open Keyboard Settings") { SystemDictation.openKeyboardSettings() }
        }
    }
}
