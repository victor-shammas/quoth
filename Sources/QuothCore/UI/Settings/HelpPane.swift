import SwiftUI

/// Help: a cheat sheet of the gestures, the Quote Card, fixing words, and
/// every voice command, at a glance.
struct HelpPane: View {
    @ObservedObject var store: SettingsStore

    private var key: String { store.current.hotkey.key.shortName }

    var body: some View {
        Pane {
            Text("How to use Quoth").font(.headline)
            VStack(alignment: .leading, spacing: 7) {
                tip("Hold \(key)", "Speak, then let go: the text lands at your cursor.")
                tip("Double-tap \(key)", "Dictate hands-free, with text at each pause. Tap once to stop.")
                tip("Quote Card", "New Quote Card in the menu: dictate, edit, then ⌘↩ inserts it where you were.")
                tip("Fix Last Dictation…", "In the menu: teach Quoth a word it got wrong.")
            }
            Text("Voice commands").font(.subheadline.weight(.semibold)).padding(.top, 4)
            VoiceCommandList()
        }
    }

    private func tip(_ title: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(title).font(.callout.weight(.medium)).frame(width: 150, alignment: .leading)
            Text(text).font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
