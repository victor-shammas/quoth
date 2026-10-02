import SwiftUI

/// Help: a cheat sheet of the gestures, the Quote Card, fixing words, and
/// every voice command, at a glance.
struct HelpPane: View {
    @ObservedObject var store: SettingsStore

    private var key: String { store.current.hotkey.key.shortName }

    var body: some View {
        Pane {
            SettingsSection("How to use Quoth") {
                VStack(alignment: .leading, spacing: 8) {
                    tip("Hold \(key)", "Speak, then let go: the text lands at your cursor.")
                    tip("Double-tap \(key)", "Dictate hands-free, with text at each pause. Tap once to stop.")
                    tip("Quote Card", "New Quote Card in the menu: dictate, edit, then ⌘↩ inserts it where you were.")
                    tip("Fix Last Dictation…", "In the menu: teach Quoth a word it got wrong.")
                }
                .padding(14)
            }
            SettingsSection("Voice commands") {
                VoiceCommandList().padding(14)
            }
        }
    }

    private func tip(_ title: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(title).font(.callout.weight(.medium)).frame(width: 150, alignment: .leading)
            Text(text).font(.callout).foregroundStyle(Latte.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
