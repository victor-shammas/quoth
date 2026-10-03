import AppKit
import QuothDomain
import SwiftUI

/// Where a dictation goes instead of the cursor (`DictationController.card`).
@MainActor
protocol DictationTarget: AnyObject {
    /// Whether it is open and taking dictation.
    var isOpen: Bool { get }
    /// Opens it, empty, if it isn't.
    func open()
    /// Adds a transcript or a live segment at the end.
    func append(_ text: String)
    /// Removes the last thing appended ("scratch that"). Returns whether it did.
    func scratchLast() -> Bool
}

/// The Quote Card: a floating card, in the latte look of Quoth's windows,
/// that a dictation streams into,
/// where the text can be fixed with the keyboard before it goes anywhere.
/// ⌘↩ inserts it where the user was; Copy All copies it; Escape closes it,
/// keeping the text for Copy Last Dictation.
///
/// A non-activating panel, like Spotlight's: it takes the keyboard without
/// making Quoth the active app, so the app the user was in stays where it
/// was, and Insert lands back in it. Text lives in memory only.
@MainActor
final class QuoteCard: DictationTarget {
    /// Inserts text where the user was; the daemon hands in TextDelivery.
    var insert: ((String) -> Void)?
    /// Copies text, kept out of clipboard histories.
    var copy: ((String) -> Void)?
    /// Keeps the card's text for Copy Last Dictation when it closes.
    var remember: ((String) -> Void)?
    /// Ends a locked recording, for Insert and Copy while still dictating.
    var endLock: (() -> Void)?
    /// Whether a dictation is still recording or transcribing.
    var isDictating: (() -> Bool)?

    private var panel: CardPanel?
    private let model = QuoteCardModel()
    /// An action waiting for the dictation in progress to finish.
    private var pending: (() -> Void)?

    var isOpen: Bool { panel?.isVisible ?? false }

    init() {
        model.onInsert = { [weak self] in self?.whenDictationEnds { self?.insertAndClose() } }
        model.onCopy = { [weak self] in self?.whenDictationEnds { self?.copyAndClose() } }
        model.onClose = { [weak self] in self?.close() }
    }

    func open() {
        let panel = self.panel ?? make()
        self.panel = panel
        if !panel.isVisible {
            model.clear()
            position(panel)
        }
        panel.makeKeyAndOrderFront(nil)
        model.focus()
    }

    func append(_ text: String) {
        guard isOpen else { return }
        model.append(text)
    }

    func scratchLast() -> Bool {
        model.removeLastAppended()
    }

    // MARK: - Actions

    /// Runs `action` now, or, while a dictation is still running, ends the
    /// lock and runs it once the last words are in.
    private func whenDictationEnds(_ action: @escaping () -> Void) {
        guard isDictating?() == true else { return action() }
        pending = action
        model.status = .finishing
        endLock?()
    }

    /// The dictation loop finished or failed: run what was waiting.
    func dictationEnded() {
        model.status = .idle
        guard let pending else { return }
        self.pending = nil
        pending()
    }

    private func insertAndClose() {
        let text = model.text.trimmingCharacters(in: .whitespacesAndNewlines)
        close()
        guard !text.isEmpty else { return }
        // Once the panel is gone the keyboard is back with the app the user
        // was in; give it a moment to take it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [insert] in insert?(text) }
    }

    private func copyAndClose() {
        let text = model.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { copy?(text) }
        close()
    }

    private func close() {
        let text = model.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { remember?(text) }
        pending = nil
        panel?.orderOut(nil)
        model.clear()
    }

    // MARK: - Window

    private func make() -> CardPanel {
        let panel = CardPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 260),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 360, height: 180)
        panel.onCancel = { [weak self] in self?.close() }
        let host = NSHostingView(rootView: QuoteCardView(model: model))
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        return panel
    }

    /// A little above the middle of the screen with the keyboard focus.
    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2 + frame.height * 0.12))
    }
}

extension QuoteCard: DictationObserver {
    func dictationStarted() { if isOpen { model.status = .listening } }
    func dictationLocked() { if isOpen { model.status = .locked } }
    func dictationTranscribing() { if isOpen, pending == nil { model.status = .transcribing } }
    func dictationFinished(_ result: DictationResult) { dictationEnded() }
    func dictationFailed(_ error: Error) { dictationEnded() }
}

/// A panel that takes the keyboard while borderless, with the editing
/// shortcuts a menu-bar app otherwise lacks, and Escape to close.
final class CardPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if EditingShortcuts.isCloseWindow(event) {
            onCancel?()
            return true
        }
        return EditingShortcuts.perform(event, in: self) || super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

// MARK: - Model and view

@MainActor
final class QuoteCardModel: ObservableObject {
    enum Status { case idle, listening, locked, transcribing, finishing }

    @Published var status: Status = .idle
    @Published private(set) var isEmpty = true
    var onInsert: (() -> Void)?
    var onCopy: (() -> Void)?
    var onClose: (() -> Void)?

    /// The text view, set by the view that owns it.
    weak var textView: NSTextView?
    /// Ranges appended by dictation, newest last, for "scratch that".
    private var appended: [NSRange] = []

    var text: String { textView?.string ?? "" }

    func clear() {
        textView?.string = ""
        appended = []
        isEmpty = true
        status = .idle
    }

    func focus() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
    }

    /// Adds `text` at the end, spaced like consecutive dictations, without
    /// moving the user's cursor or selection.
    func append(_ text: String) {
        guard let textView, let storage = textView.textStorage, !text.isEmpty else { return }
        let existing = textView.string
        let joined: String
        if let last = existing.last, Spacing.needsSpace(after: last, text: text) {
            joined = " " + text
        } else {
            joined = text
        }
        let start = (existing as NSString).length
        let attributes = textView.typingAttributes
        storage.append(NSAttributedString(string: joined, attributes: attributes))
        appended.append(NSRange(location: start, length: (joined as NSString).length))
        textView.scrollToEndOfDocument(nil)
        isEmpty = textView.string.isEmpty
    }

    /// Removes the last dictated text, if the user hasn't edited over it.
    func removeLastAppended() -> Bool {
        guard let textView, let storage = textView.textStorage, let last = appended.popLast(),
              NSMaxRange(last) <= storage.length
        else { return false }
        storage.deleteCharacters(in: last)
        isEmpty = textView.string.isEmpty
        return true
    }

    func textDidChange() {
        isEmpty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // A hand edit invalidates what "scratch that" would remove.
        appended = appended.filter { NSMaxRange($0) <= (text as NSString).length }
    }
}

struct QuoteCardView: View {
    @ObservedObject var model: QuoteCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                QuotePair(opening: true).frame(width: 18, height: 15)
                Text(statusText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Latte.secondary)
                Spacer()
                Button {
                    model.onClose?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Latte.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)

            CardTextView(model: model)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

            HStack(spacing: 10) {
                Text("Edit freely. Dictation adds to the end.")
                    .font(.system(size: 11))
                    .foregroundStyle(Latte.secondary)
                Spacer()
                Button("Copy All") { model.onCopy?() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(model.isEmpty)
                Button("Insert") { model.onInsert?() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.isEmpty)
                QuotePair().frame(width: 18, height: 15)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
        }
        .tint(Latte.tint)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Latte.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Latte.stroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var statusText: String {
        switch model.status {
        case .idle: return model.isEmpty ? "Hold or double-tap your key to dictate" : "Quote Card"
        case .listening: return "Listening…"
        case .locked: return "Listening hands-free — tap your key to stop"
        case .transcribing: return "Writing it down…"
        case .finishing: return "Finishing the last words…"
        }
    }
}

/// An editable text view, in the latte colors, the model can append to.
private struct CardTextView: NSViewRepresentable {
    @ObservedObject var model: QuoteCardModel

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.scrollerStyle = .overlay
        let view = scroll.documentView as! NSTextView
        view.isRichText = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.font = .systemFont(ofSize: 15)
        view.textColor = NSColor(light: 0x24180F, dark: 0xF6EBDD)
        view.insertionPointColor = NSColor(light: 0xB8610F, dark: 0xFFB457)
        view.textContainerInset = NSSize(width: 6, height: 6)
        view.typingAttributes = [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor(light: 0x24180F, dark: 0xF6EBDD)]
        view.delegate = context.coordinator
        model.textView = view
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let model: QuoteCardModel
        init(model: QuoteCardModel) { self.model = model }
        func textDidChange(_ notification: Notification) {
            MainActor.assumeIsolated { model.textDidChange() }
        }
    }
}
