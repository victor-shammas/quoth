import SwiftUI

/// About: what Quoth is and which version, and the rarely needed things:
/// the licences, the settings file, and resetting.
struct AboutPane: View {
    @ObservedObject var store: SettingsStore
    @State private var confirmingReset = false

    var body: some View {
        Pane {
            VStack(spacing: 6) {
                AppBadge(size: 72)
                Text("Quoth").font(.title2.weight(.semibold))
                Text("Version \(AppBundle.version)")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("Local voice transcription on your Mac.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 4)

            Divider()

            PillRow("Open-source components") {
                Button("Acknowledgements…") { AcknowledgementsWindow.show() }
                    .buttonStyle(.pill)
            }
            if Edition.opensConfigFiles {
                PillRow("Settings file", caption: "settings.json, for editing by hand.") {
                    Button("Open…") {
                        store.createIfMissing()
                        ConfigFiles.open(store.file)
                    }
                    .buttonStyle(.pill)
                }
            }
            PillRow("All settings", caption: "Your dictionary, example sentences, languages and models are kept.") {
                Button("Reset to Defaults…") { confirmingReset = true }
                    .buttonStyle(.pill)
            }
        }
        .alert("Reset all settings?", isPresented: $confirmingReset) {
            Button("Reset", role: .destructive) { store.write(store.current.reset()) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your dictionary, example sentences, languages and downloaded models are kept.")
        }
    }
}
