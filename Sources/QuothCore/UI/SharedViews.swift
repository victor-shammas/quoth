import AppKit
import QuothDomain
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
