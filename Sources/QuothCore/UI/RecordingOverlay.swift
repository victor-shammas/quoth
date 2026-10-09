import AppKit
import QuothDomain
import SwiftUI

/// The pill: a small, click-through panel at the bottom of the screen that
/// shows the dictation loop as it happens (a `DictationObserver`), and a
/// one-line message when there's something to say. A `UserFacingError` is
/// shown that way; any other failure just hides the pill.
@MainActor
final class RecordingOverlay {
    enum State: Equatable {
        case hidden
        case recording
        /// Recording, locked on by a double tap.
        case locked
        case transcribing
        /// One line, such as why nothing was typed. Never transcript text.
        case message(String)
    }

    /// How long a message stays unless something replaces it.
    nonisolated static let messageDuration: TimeInterval = 4
    /// How long the pill takes to grow or shrink. A hidden panel is ordered
    /// out once it has.
    nonisolated static let scaleDuration: TimeInterval = 0.3
    /// Wide enough for a message and tall enough for the pill's shadow;
    /// transparent and click-through, so the extra is invisible.
    private static let panelSize = NSSize(width: 640, height: 64)

    private let model = OverlayModel()
    private var panel: NSPanel?
    /// Bumped by every change, so a message's timer only clears its own.
    private var generation = 0

    init() {
        // Built now, so the first pill appears as quickly as every later one.
        _ = makePanelIfNeeded()
    }

    func show(_ state: State) {
        generation += 1
        let panel = makePanelIfNeeded()
        if state == .recording { model.resetLevels() }
        if panel.isVisible {
            model.state = state
            return
        }
        placeAtBottomCenter(panel)
        panel.orderFrontRegardless()
        // Let SwiftUI lay the pill out hidden first, so it grows in.
        DispatchQueue.main.async { [model] in model.state = state }
    }

    func hide() {
        model.state = .hidden
        // Order the panel out once the shrink has played, unless something
        // was shown meanwhile.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.scaleDuration) { [model, panel] in
            if model.state == .hidden { panel?.orderOut(nil) }
        }
    }

    /// Shows `text` for `duration`, then whatever `after` is (hidden by
    /// default), unless something else has been shown by then.
    func showMessage(_ text: String, for duration: TimeInterval = messageDuration, then after: State = .hidden) {
        show(.message(text))
        let shown = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == shown else { return }
                after == .hidden ? self.hide() : self.show(after)
            }
        }
    }

    /// The message for a failed dictation, or nil to just hide.
    nonisolated static func message(for error: Error) -> String? {
        (error as? UserFacingError)?.userMessage
    }

    /// A new microphone level, 0 to about 1. Safe from any thread.
    nonisolated func pushLevel(_ level: Float) {
        Task { @MainActor in self.model.pushLevel(level) }
    }

    private func makePanelIfNeeded() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The pill draws its own shadow. A window's would be computed once,
        // when shown, and neither follow the pill as it grows nor leave with it.
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        let host = NSHostingView(rootView: OverlayPill(model: model))
        // The panel keeps its size and SwiftUI centres the pill in it, so a
        // longer message grows both ways, not off to the right.
        host.sizingOptions = []
        host.frame = panel.contentView?.bounds ?? .zero
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        self.panel = panel
        return panel
    }

    /// 32 pt above the bottom of the visible screen.
    private func placeAtBottomCenter(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 32 - (size.height - 44) / 2))
    }
}

extension RecordingOverlay: DictationObserver {
    func dictationStarted() { show(.recording) }
    func dictationInput(_ input: RecordingInput) { model.macMicrophone = input.inPlaceOfHeadset }
    func dictationLocked() { show(.locked) }
    func dictationTranscribing() { show(.transcribing) }
    func dictationFinished(_ result: DictationResult) { hide() }

    /// A problem mid-recording: say so, then go back to what was showing.
    func dictationNotice(_ error: Error) {
        guard let text = Self.message(for: error) else { return }
        showMessage(text, then: model.state)
    }

    func dictationFailed(_ error: Error) {
        if let text = Self.message(for: error) { showMessage(text) } else { hide() }
    }
}

/// What the pill shows.
@MainActor
final class OverlayModel: ObservableObject {
    static let barCount = LevelMeter.barCount

    @Published var state: RecordingOverlay.State = .hidden
    @Published var levels = [Float](repeating: 0, count: LevelMeter.barCount)
    /// Whether this recording has been louder than silence.
    @Published private(set) var heardVoice = false
    /// Whether this recording uses the Mac's microphone in place of
    /// Bluetooth headphones that are playing.
    @Published var macMicrophone = false
    private var meter = LevelMeter()

    func pushLevel(_ level: Float) {
        guard let bars = meter.add(level, at: ProcessInfo.processInfo.systemUptime) else { return }
        if meter.heardVoice, !heardVoice { heardVoice = true }
        levels = bars
    }

    func resetLevels() {
        meter.reset()
        heardVoice = false
        levels = [Float](repeating: 0, count: LevelMeter.barCount)
    }
}
