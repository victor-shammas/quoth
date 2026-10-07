import Foundation
import QuothDomain

/// Where a finished transcript goes. Pure, so it is tested.
public enum DeliveryDecision: Equatable {
    /// Insert at the cursor.
    case inject
    /// A secure field had focus at start or at delivery: drop the transcript.
    case discardSecure
    /// Focus moved: leave the transcript on the clipboard instead.
    case copyToClipboard

    /// `start` is nil when no recording start was seen; then only the
    /// secure-field check applies.
    public static func decide(start: FocusSnapshot?, now: FocusSnapshot) -> DeliveryDecision {
        if start?.isSecure == true || now.isSecure { return .discardSecure }
        if let start, start.hasChanged(to: now) { return .copyToClipboard }
        return .inject
    }
}

/// The delivery step of the dictation loop: checks focus against the
/// snapshot from recording start, then injects, copies or discards. An
/// injected transcript gets a trailing space, and a leading one when the
/// text before the cursor needs it (`Spacing`).
@MainActor
public final class TextDelivery {
    private let injector: TextInjector

    /// What was last inserted, for "scratch that": how many characters, and
    /// where. Never the text itself.
    private struct Insertion {
        let length: Int
        let pid: pid_t?
        let element: FocusedElement?
        let at: Date
    }
    private var insertions: [Insertion] = []
    /// How long after an insertion "scratch that" may still remove it.
    public static let scratchWindow: TimeInterval = 120

    public init(mode: InjectMode) {
        self.injector = TextInjector(mode: mode)
    }

    /// Leaves `text` on the clipboard, for live text held back after a
    /// focus change.
    public func copyToClipboard(_ text: String) {
        injector.copyToClipboard(text)
    }

    /// Whether a transcript can be inserted at the cursor, rather than only
    /// copied (`PasteAccess`).
    public var canInsert: Bool { PasteAccess.isGranted }

    /// Inserts `text` at the cursor now, for the Quote Card's Insert: no
    /// focus to compare with, but never into a password field. Returns
    /// false, leaving the text on the clipboard, when this build can't paste
    /// or nothing took the paste.
    @discardableResult
    public func insertNow(_ text: String) async -> Bool {
        let now = FocusSnapshot.capture()
        guard !now.isSecure else {
            Log.info("  secure field focused; card text not inserted")
            return false
        }
        guard canInsert else {
            injector.copyToClipboard(text)
            return false
        }
        let before = now.element?.textBeforeCursor() ?? .unknown
        let spaced = Spacing.spaced(text, before: before)
        guard await injector.inject(spaced) else {
            Log.info("  nothing took the paste; card text left on the clipboard")
            return false
        }
        insertions.append(Insertion(length: spaced.count, pid: now.pid, element: now.element, at: Date()))
        return true
    }

    /// Removes the last insertion ("scratch that"), if it was recent and the
    /// same app and field still have focus, so the Delete keys can only reach
    /// what Quoth typed. Each call removes one more, back through the
    /// segments of a hands-free dictation. Returns whether it removed one.
    @discardableResult
    public func scratchLast() -> Bool {
        guard canInsert, let last = insertions.last, Date().timeIntervalSince(last.at) < Self.scratchWindow else {
            Log.info("  scratch that: nothing recent to remove")
            return false
        }
        let now = FocusSnapshot.capture()
        let sameField = last.element == nil || now.element == nil || last.element == now.element
        guard !now.isSecure, now.pid == last.pid, sameField else {
            Log.info("  scratch that: focus moved; nothing removed")
            return false
        }
        insertions.removeLast()
        injector.deleteBackward(last.length)
        Log.info("  scratch that: removed \(last.length) characters")
        return true
    }

    /// Throws `DeliveryError` when the transcript did not reach the cursor.
    /// A paste returns once the app in front read it, or the settle delay
    /// passed without it doing so.
    public func deliver(_ text: String, focusAtStart: FocusSnapshot?) async throws {
        guard !text.isEmpty else { return }
        let now = FocusSnapshot.capture()
        switch DeliveryDecision.decide(start: focusAtStart, now: now) {
        case .inject where !canInsert:
            injector.copyToClipboard(text)
            Log.info("  no paste grant; transcript copied to clipboard")
            throw DeliveryError.copied
        case .inject:
            let before = now.element?.textBeforeCursor() ?? .unknown
            let spaced = Spacing.spaced(text, before: before)
            // The kind of character only: the log never carries text.
            Log.info("  before cursor: \(before.kind)\(spaced.first == " " && text.first != " " ? " · leading space" : "")")
            guard await injector.inject(spaced) else {
                Log.info("  nothing took the paste; transcript left on the clipboard")
                throw DeliveryError.notPasted
            }
            insertions.append(Insertion(length: spaced.count, pid: now.pid, element: now.element, at: Date()))
            if insertions.count > 20 { insertions.removeFirst() }
        case .discardSecure:
            let when = focusAtStart?.isSecure == true ? "recording start" : "delivery"
            Log.info("  secure field focused at \(when); transcript discarded")
            throw DeliveryError.secureField
        case .copyToClipboard:
            injector.copyToClipboard(text)
            Log.info("  focus changed during dictation; transcript copied to clipboard")
            throw DeliveryError.focusChanged
        }
    }
}
