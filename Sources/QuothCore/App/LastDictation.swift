import AppKit

/// The last transcript, for Copy Last Dictation and Fix Last Dictation.
///
/// Memory only, never written anywhere (ADR-004): it is forgotten after
/// `lifetime`, when the screen locks, and when Quoth quits. A dictation into
/// a password field is never kept.
@MainActor
final class LastDictation {
    static let lifetime: TimeInterval = 10 * 60

    private(set) var text: String?
    /// Called whenever `text` appears or goes, so the menu can enable its items.
    var onChange: ((Bool) -> Void)?
    private var expiry: DispatchWorkItem?
    private var lockObserver: NSObjectProtocol?

    init() {
        lockObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.forget() }
        }
    }

    func remember(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        self.text = text
        expiry?.cancel()
        let expiry = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.forget() }
        }
        self.expiry = expiry
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.lifetime, execute: expiry)
        onChange?(true)
    }

    func forget() {
        guard text != nil else { return }
        text = nil
        expiry?.cancel()
        onChange?(false)
    }

    /// Puts the last dictation on the clipboard, marked concealed so
    /// clipboard managers don't keep it in their history.
    func copy() {
        guard let text else { return }
        SystemPasteboard(.general).write(text, markers: PasteboardSession.concealedMarkers)
    }
}
