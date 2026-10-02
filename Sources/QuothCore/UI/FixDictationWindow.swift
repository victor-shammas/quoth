import AppKit
import SwiftUI

/// Fix Last Dictation…: shows the last transcript; select the word Quoth got
/// wrong, type how it should be spelled, and it goes into the dictionary, so
/// the next dictation gets it right. Learning from real mistakes beats
/// guessing in advance how Whisper will mishear a word.
@MainActor
final class FixDictationWindow {
    private var window: NSWindow?
    private let dictionary: DictionaryStore

    init(dictionary: DictionaryStore) {
        self.dictionary = dictionary
    }

    func show(text: String?) {
        let window = self.window ?? make()
        self.window = window
        window.contentView = NSHostingView(rootView: FixDictationView(
            text: text,
            add: { [dictionary] word, heardAs in dictionary.add(word: word, heardAs: heardAs) },
            close: { [weak window] in window?.performClose(nil) }
        ))
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func make() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Fix Last Dictation"
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

struct FixDictationView: View {
    let text: String?
    let add: (_ word: String, _ heardAs: String) -> Bool
    let close: () -> Void

    @State private var heardAs = ""
    @State private var word = ""
    @State private var added: String?
    @FocusState private var wordFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let text {
                Text("Select the word Quoth got wrong.")
                    .foregroundStyle(.secondary)
                SelectableText(text: text) { selection in
                    guard !selection.isEmpty else { return }
                    heardAs = selection
                    added = nil
                    wordFocused = true
                }
                .frame(minHeight: 70, maxHeight: 110)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("Quoth wrote").foregroundStyle(.secondary)
                        TextField("Select it above, or type it", text: $heardAs)
                    }
                    GridRow {
                        Text("Correct spelling").foregroundStyle(.secondary)
                        TextField("How it should be spelled", text: $word)
                            .focused($wordFocused)
                            .onSubmit(addToDictionary)
                    }
                }

                HStack {
                    if let added {
                        Label(added, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Done", action: close)
                        .keyboardShortcut(.cancelAction)
                    Button("Add to Dictionary", action: addToDictionary)
                        .keyboardShortcut(.defaultAction)
                        .disabled(word.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else {
                Text("Nothing dictated in the last \(Int(LastDictation.lifetime / 60)) minutes.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack {
                    Spacer()
                    Button("Done", action: close).keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func addToDictionary() {
        let word = word.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty else { return }
        if add(word, heardAs) {
            added = "Added. Quoth will spell it “\(word)” from now on."
            heardAs = ""
            self.word = ""
        } else {
            added = "Couldn't save the dictionary."
        }
    }
}

/// Read-only, selectable text that reports what the user selects, which
/// SwiftUI's `Text` can't.
private struct SelectableText: NSViewRepresentable {
    let text: String
    let onSelect: (String) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        let view = scroll.documentView as! NSTextView
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.font = .systemFont(ofSize: NSFont.systemFontSize)
        view.textContainerInset = NSSize(width: 8, height: 8)
        view.delegate = context.coordinator
        view.string = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let view = scroll.documentView as! NSTextView
        if view.string != text { view.string = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let onSelect: (String) -> Void
        init(onSelect: @escaping (String) -> Void) { self.onSelect = onSelect }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            let selected = (view.string as NSString).substring(with: view.selectedRange())
            onSelect(selected.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)))
        }
    }
}
