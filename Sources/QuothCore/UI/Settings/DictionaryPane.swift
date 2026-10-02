import AppKit
import SwiftUI

/// The dictionary as rows the Settings table edits. Saves the file a moment
/// after the last change (`DictionaryStore.save`), never over a file that
/// has a mistake in it and never over one that changed since it was read,
/// so neither a hand edit nor Fix Last Dictation is lost; it reloads
/// instead. Reloads, too, whenever the dictionary is saved elsewhere.
@MainActor
final class DictionaryEditor: ObservableObject {
    struct Row: Identifiable, Equatable {
        let id = UUID()
        var word: String
        /// Comma-separated, as typed.
        var heardAs: String
    }

    /// How long after the last keystroke the file is written.
    static let saveDelay: TimeInterval = 0.6

    @Published var rows: [Row] = [] {
        didSet { if !reloading { scheduleSave() } }
    }
    /// Why the file can't be edited here: it has a mistake, which only an
    /// edit of the file can fix.
    @Published private(set) var problem: String?
    /// The last save failed, or found the file changed and reloaded.
    @Published private(set) var saveNote: String?

    private let store: DictionaryStore
    private var pending: Task<Void, Never>?
    private var reloading = false
    /// What the rows were loaded from, so a save never overwrites a change
    /// made elsewhere in the meantime.
    private var base = UserDictionary.empty
    private var observer: NSObjectProtocol?

    init(store: DictionaryStore) {
        self.store = store
        reload()
        observer = NotificationCenter.default.addObserver(
            forName: DictionaryStore.didSave, object: store, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadIfIdle() }
        }
    }

    /// Reads the file again, for a change made outside this editor.
    func reload() {
        flush()
        reloading = true
        defer { reloading = false }
        problem = store.loadProblem()
        base = store.current().dictionary
        rows = base.rows().rows.map {
            Row(word: $0.word, heardAs: $0.heardAs.joined(separator: ", "))
        }
    }

    /// Reloads unless an edit is waiting to be saved: for a save made
    /// elsewhere, and when the window comes forward.
    func reloadIfIdle() {
        guard pending == nil else { return }
        let current = store.current().dictionary
        guard current.rows().rows != base.rows().rows || store.loadProblem() != problem else { return }
        reload()
    }

    /// Appends an empty row and returns it, for the table to select.
    func addRow() -> Row.ID {
        let row = Row(word: "", heardAs: "")
        rows.append(row)
        return row.id
    }

    func remove(_ ids: Set<Row.ID>) {
        rows.removeAll { ids.contains($0.id) }
    }

    /// What the table should point out: a word the file can't hold, and a
    /// word listed twice.
    var issues: [String] {
        var issues: [String] = []
        let words = rows.map { $0.word.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if let bad = words.first(where: { $0.contains(",") || $0.hasPrefix("#") }) {
            issues.append("“\(bad)” can't be saved: a word can't contain a comma or start with #.")
        }
        var seen = Set<String>()
        if let twice = words.first(where: { !seen.insert($0.lowercased()).inserted }) {
            issues.append("“\(twice)” is listed twice; the first row is used.")
        }
        return issues
    }

    /// Writes now if a save is waiting, for when the pane closes.
    func flush() {
        guard pending != nil else { return }
        pending?.cancel()
        save()
    }

    private func scheduleSave() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.saveDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    private func save() {
        pending = nil
        guard problem == nil else { return }
        let table = rows.map { row in
            UserDictionary.Row(
                word: row.word,
                heardAs: row.heardAs.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            )
        }
        let next = UserDictionary(rows: table)
        if store.save(next, basedOn: base) {
            base = next
            saveNote = nil
        } else if let problem = store.loadProblem() {
            self.problem = problem
            saveNote = "Not saved: the dictionary file has a mistake."
        } else if store.current().dictionary.rows().rows != base.rows().rows {
            reload()
            saveNote = "The dictionary changed elsewhere, so it was reloaded. Your last edit wasn't saved."
        } else {
            saveNote = "Couldn't save the dictionary. Check that its file can be written."
        }
    }
}

/// Dictionary: words Quoth should spell your way, as a table, and the
/// optional example sentence.
struct DictionaryPane: View {
    @ObservedObject var settings: SettingsStore
    @StateObject private var editor: DictionaryEditor
    @State private var selection = Set<DictionaryEditor.Row.ID>()

    init(settings: SettingsStore, dictionary: DictionaryStore) {
        self.settings = settings
        _editor = StateObject(wrappedValue: DictionaryEditor(store: dictionary))
    }

    var body: some View {
        Pane {
            Text("Words Quoth should spell your way. Heard as lists what it writes instead, separated by commas.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let problem = editor.problem {
                Label("The dictionary file has a mistake (\(problem)). Fix it in the file to edit it here.",
                      systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 0) {
                table
                    .disabled(editor.problem != nil)
                tableBar
            }

            ForEach(editor.issues, id: \.self) { Caption($0) }
            if let note = editor.saveNote {
                Label(note, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            ExampleSentence(settings: settings)
        }
        .onAppear { editor.reload() }
        .onDisappear { editor.flush() }
        // The window is kept between openings, so onAppear alone would miss
        // a change made while it was closed.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            editor.reloadIfIdle()
        }
    }

    private var table: some View {
        Table(editor.rows, selection: $selection) {
            TableColumn("Word") { row in
                TextField("Word", text: binding(row.id, \.word))
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Word")
            }
            .width(min: 120, ideal: 170)
            TableColumn("Heard as") { row in
                TextField("optional", text: binding(row.id, \.heardAs))
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Heard as")
            }
        }
        .tableStyle(.bordered(alternatesRowBackgrounds: true))
        .frame(height: 230)
        .onDeleteCommand { removeSelected() }
        .overlay {
            if editor.rows.isEmpty {
                VStack(spacing: 4) {
                    Text("No words yet").font(.headline)
                    Text("Add names and terms Quoth gets wrong, or use Fix Last Dictation in the menu bar right after dictating.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                .padding(.horizontal, 40)
                .allowsHitTesting(false)
            }
        }
    }

    /// The + and − buttons under the table, as in macOS's own lists.
    private var tableBar: some View {
        HStack(spacing: 2) {
            Button {
                selection = [editor.addRow()]
            } label: {
                Image(systemName: "plus").frame(width: 22, height: 20)
            }
            .help("Add a word")
            .accessibilityLabel("Add word")
            Button {
                removeSelected()
            } label: {
                Image(systemName: "minus").frame(width: 22, height: 20)
            }
            .help("Remove the selected words")
            .accessibilityLabel("Remove selected words")
            .disabled(selection.isEmpty)
            Spacer()
            let count = editor.rows.filter { !$0.word.trimmingCharacters(in: .whitespaces).isEmpty }.count
            Text(count == 1 ? "1 word" : "\(count) words")
                .font(.caption)
                .foregroundStyle(.secondary)
            if Edition.opensConfigFiles {
                Button("Edit as Text…") { ConfigFiles.open(Paths.dictionaryFile) }
                    .buttonStyle(.link)
                    .font(.caption)
                    .padding(.leading, 8)
            }
        }
        .buttonStyle(.borderless)
        .padding(.top, 4)
        .disabled(editor.problem != nil)
    }

    private func removeSelected() {
        editor.remove(selection)
        selection = []
    }

    private func binding(_ id: DictionaryEditor.Row.ID, _ field: WritableKeyPath<DictionaryEditor.Row, String>) -> Binding<String> {
        Binding(
            get: { editor.rows.first { $0.id == id }?[keyPath: field] ?? "" },
            set: { value in
                guard let i = editor.rows.firstIndex(where: { $0.id == id }) else { return }
                editor.rows[i][keyPath: field] = value
            }
        )
    }
}

/// The optional example sentence: what Whisper reads as the speech just
/// before a dictation, which biases it toward the user's spellings. One per
/// language; a multilingual model picks among the languages the user speaks.
private struct ExampleSentence: View {
    @ObservedObject var settings: SettingsStore
    @State private var language = "en"
    @State private var text = ""
    @State private var pending: Task<Void, Never>?

    private var languages: [String] {
        let model = settings.current.model.id.flatMap(ModelRegistry.find) ?? ModelRegistry.recommended()
        guard model?.isMultilingual == true else { return ["en"] }
        let spoken = settings.current.language.spokenOrPreferred.filter(SpokenLanguage.whisperLanguages.contains)
        return spoken.isEmpty ? ["en"] : spoken
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PillRow("Example sentence", caption: "Optional. One sentence using your words, the way you'd say it. It helps Whisper spell them, and adds a little time to each dictation.") {
                if languages.count > 1 {
                    PillMenu(title: SpokenLanguage.displayName(language)) {
                        ForEach(languages, id: \.self) { code in
                            Toggle(SpokenLanguage.displayName(code), isOn: Binding(
                                get: { language == code },
                                set: { if $0 { language = code } }
                            ))
                        }
                    }
                }
            }
            TextField("I pushed the WhisperKit fix and checked the PostHog dashboard.", text: $text, axis: .vertical)
                .lineLimit(2...3)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Example sentence")
        }
        .onAppear {
            if !languages.contains(language) { language = languages.first ?? "en" }
            text = settings.current.dictionary.examples[language] ?? ""
        }
        .onChange(of: language) { old, new in
            flush(for: old)
            text = settings.current.dictionary.examples[new] ?? ""
        }
        .onChange(of: text) { _, _ in
            pending?.cancel()
            pending = Task {
                try? await Task.sleep(nanoseconds: UInt64(DictionaryEditor.saveDelay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                save()
            }
        }
        .onDisappear { flush(for: language) }
    }

    /// Saves what was typed now, under `code`: the language it was typed
    /// for, even when the menu has just changed to another.
    private func flush(for code: String) {
        guard pending != nil else { return }
        pending?.cancel()
        save(for: code)
    }

    private func save(for code: String? = nil) {
        pending = nil
        let code = code ?? language
        let sentence = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard settings.current.dictionary.examples[code] ?? "" != sentence else { return }
        settings.update { $0.dictionary.examples[code] = sentence.isEmpty ? nil : sentence }
    }
}

/// Opening Quoth's own files in a text editor, for the direct build. The
/// dictionary has no extension, so `open(_:)` alone wouldn't know how.
enum ConfigFiles {
    static func open(_ file: URL) {
        if file == Paths.dictionaryFile { DictionaryStore(file: file).createIfMissing() }
        let editor = NSWorkspace.shared.urlForApplication(toOpen: .plainText)
            ?? URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        NSWorkspace.shared.open([file], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { Log.warning("couldn't open \(file.path): \(error.localizedDescription)") }
        }
    }
}
