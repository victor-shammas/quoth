import AppKit
import QuothDomain
import QuothSpeech
import SwiftUI

/// Model: which Whisper model transcribes, in which language, and
/// the models downloaded to this Mac.
struct ModelPane: View {
    @ObservedObject var store: SettingsStore
    /// For a model loading behind the one in use; nil in tests.
    var app: AppModel?

    /// Every language Whisper knows, by name in the user's language.
    private static let languages: [(code: String, name: String)] = WhisperLanguages.codes
        .map { (code: $0, name: SpokenLanguage.displayName($0)) }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

    private var selectedModel: TranscriptionModel {
        store.current.model.id.flatMap(ModelRegistry.find) ?? ModelRegistry.recommended
    }

    var body: some View {
        Pane {
            SettingsSection("Transcription") {
                SettingRow("Model", caption: app?.modelLoad == nil ? selectedModel.summary : nil) {
                    SettingMenu(title: selectedModel.name) {
                        modelGroup("English only", ModelRegistry.all.filter { !$0.isMultilingual })
                        modelGroup("Multilingual, including English", ModelRegistry.all.filter(\.isMultilingual))
                    }
                }
                if let state = app?.modelLoad {
                    HStack(spacing: 8) {
                        switch state.phase {
                        case .downloading(let fraction?):
                            ProgressView(value: fraction).frame(width: 90)
                        case .downloading(nil), .loading:
                            ProgressView().controlSize(.small)
                        case .failed:
                            EmptyView()
                        }
                        Caption(state.text)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }
                RowDivider()
                languagePicker
            }

            DownloadedModels(selected: selectedModel, app: app)
        }
    }

    /// One group of the Model menu, smallest first, with a checkmark on the
    /// selected model and a download arrow on each not yet on the Mac.
    @ViewBuilder
    private func modelGroup(_ title: String, _ models: [TranscriptionModel]) -> some View {
        Section(title) {
            ForEach(models.sorted { $0.sizeMB < $1.sizeMB }, id: \.id) { model in
                Toggle(isOn: Binding(
                    get: { selectedModel.id == model.id },
                    set: { on in if on { store.update { $0.model.id = model.id } } }
                )) {
                    // A model not on the Mac yet downloads when chosen; the
                    // arrow says so without words.
                    if ModelFiles(model).isDownloaded {
                        Text(model.shortName)
                    } else {
                        Label(model.shortName, systemImage: "arrow.down.circle")
                    }
                }
            }
        }
    }

    /// Automatic, then every language by name. A saved code Whisper does not
    /// know shows as Automatic, which is how it is treated.
    @ViewBuilder private var languagePicker: some View {
        let multilingual = selectedModel.isMultilingual
        let code = store.current.language.code?.lowercased()
        let selected = code.flatMap { WhisperLanguages.codes.contains($0) ? $0 : nil }
        SettingRow("Language", caption: multilingual ? nil : "This model hears \(SpokenLanguage.displayName(selectedModel.onlyLanguage ?? "en")) only. For other languages, choose a multilingual model.") {
            SettingMenu(title: selected.map { SpokenLanguage.displayName($0) } ?? "Automatic") {
                languageToggle("Automatic", nil, selected: selected)
                Divider()
                ForEach(Self.languages, id: \.code) { language in
                    languageToggle(language.name, language.code, selected: selected)
                }
            }
            .disabled(!multilingual)
        }

        if multilingual, store.current.language.code == nil {
            RowDivider()
            SettingRow("Languages you speak", caption: "Automatic picks among these.") {
                SpokenLanguagesButton(store: store)
            }
        }
    }

    private func languageToggle(_ name: String, _ code: String?, selected: String?) -> some View {
        Toggle(name, isOn: Binding(
            get: { selected == code },
            set: { on in if on { store.update { $0.language.code = code } } }
        ))
    }

}

/// The languages Automatic chooses among, as a pill that opens checkboxes.
/// Starts from the Mac's preferred languages; the first edit saves the list
/// to settings.json.
private struct SpokenLanguagesButton: View {
    @ObservedObject var store: SettingsStore
    @State private var isOpen = false

    private var spoken: [String] {
        store.current.language.spokenOrPreferred.filter(WhisperLanguages.codes.contains)
    }

    var body: some View {
        Button(Onboarding.summary(spoken.map { SpokenLanguage.displayName($0) })) { isOpen.toggle() }
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            SpokenLanguagesList(store: store)
        }
    }
}

/// The popover's content, observing the store so ticks show as they change.
private struct SpokenLanguagesList: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        let spoken = store.current.language.spokenOrPreferred.filter(WhisperLanguages.codes.contains)
        LanguageChecklist(ticked: spoken, toggle: { code in
            var next = spoken.filter { $0 != code }
            if !spoken.contains(code) { next.append(code) }
            // Keep at least one: an empty list trusts nothing.
            guard !next.isEmpty else { return }
            store.update { $0.language.spoken = next }
        }) {
            if store.current.language.spoken != nil {
                Divider().padding(.vertical, 2)
                Button("Use the Mac's Languages") { store.update { $0.language.spoken = nil } }
                    .buttonStyle(.link)
            }
        }
    }
}
