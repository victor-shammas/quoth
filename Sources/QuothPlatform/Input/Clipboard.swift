import AppKit
import Foundation
import QuothDomain

/// One representation (a type and its bytes) of one pasteboard item.
public struct PasteboardRepresentation: Equatable {
    public var type: String
    public var data: Data
}

/// Everything on a pasteboard, every representation of every item, so text,
/// images and copied Finder files all come back.
public struct PasteboardSnapshot: Equatable {
    public var items: [[PasteboardRepresentation]]
}

/// What paste mode needs of a pasteboard: `NSPasteboard` in the app, a fake
/// in tests.
public protocol PasteboardAccess: AnyObject {
    var changeCount: Int { get }
    func snapshot() -> PasteboardSnapshot
    func restore(_ snapshot: PasteboardSnapshot)
    /// Replaces the contents with `text`, plus an empty item of each marker type.
    func write(_ text: String, markers: [String])
}

/// Borrows the clipboard for a paste and gives it back.
///
/// A paste saves the clipboard, writes the text, posts ⌘V, and puts the
/// saved clipboard back after the settle delay. Pastes in quick succession
/// keep the first save, so what comes back is the user's clipboard, not an
/// earlier transcript. Anything else that writes the clipboard meanwhile
/// wins: nothing is put back over it.
public final class PasteboardSession {
    /// nspasteboard.org markers that keep clipboard managers from recording
    /// a borrowed clipboard.
    public static let transientMarkers = ["org.nspasteboard.TransientType", "org.nspasteboard.ConcealedType"]
    /// For text left on the clipboard on purpose: kept, but out of history.
    public static let concealedMarkers = ["org.nspasteboard.ConcealedType"]

    public typealias Schedule = (TimeInterval, @escaping () -> Void) -> Void

    private let pasteboard: PasteboardAccess
    private let settleDelay: TimeInterval
    private let postPaste: () -> Void
    private let schedule: Schedule

    /// The user's clipboard, while it is out on loan.
    private var saved: PasteboardSnapshot?
    /// The change count just after Quoth's last write, to tell whether
    /// anything else wrote since.
    private var written = 0
    /// Bumped by every write, so only the latest give-back runs.
    private var generation = 0

    public init(
        pasteboard: PasteboardAccess,
        settleDelay: TimeInterval,
        postPaste: @escaping () -> Void,
        schedule: @escaping Schedule = { delay, work in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work) }
    ) {
        self.pasteboard = pasteboard
        self.settleDelay = settleDelay
        self.postPaste = postPaste
        self.schedule = schedule
    }

    public var isRestorePending: Bool { saved != nil }

    public func paste(_ text: String) {
        saved = saved ?? pasteboard.snapshot()
        write(text, markers: Self.transientMarkers)
        postPaste()
        let loan = generation
        schedule(settleDelay) { [weak self] in self?.giveBack(loan) }
    }

    /// Puts `text` on the clipboard to stay, cancelling any give-back that
    /// would overwrite it.
    public func copy(_ text: String) {
        saved = nil
        write(text, markers: Self.concealedMarkers)
    }

    private func write(_ text: String, markers: [String]) {
        generation += 1
        pasteboard.write(text, markers: markers)
        written = pasteboard.changeCount
    }

    private func giveBack(_ loan: Int) {
        guard loan == generation, let saved else { return }
        self.saved = nil
        guard pasteboard.changeCount == written else {
            return Log.info("  clipboard changed during paste; not restoring")
        }
        pasteboard.restore(saved)
    }
}

/// `PasteboardAccess` over an `NSPasteboard`.
public final class SystemPasteboard: PasteboardAccess {
    private let pasteboard: NSPasteboard

    public init(_ pasteboard: NSPasteboard) {
        self.pasteboard = pasteboard
    }

    public var changeCount: Int { pasteboard.changeCount }

    public func snapshot() -> PasteboardSnapshot {
        PasteboardSnapshot(items: (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in
                item.data(forType: type).map { PasteboardRepresentation(type: type.rawValue, data: $0) }
            }
        })
    }

    public func restore(_ snapshot: PasteboardSnapshot) {
        pasteboard.clearContents()
        let items = snapshot.items.map { representations in
            let item = NSPasteboardItem()
            for r in representations { item.setData(r.data, forType: NSPasteboard.PasteboardType(r.type)) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }

    public func write(_ text: String, markers: [String]) {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        for marker in markers { item.setData(Data(), forType: NSPasteboard.PasteboardType(marker)) }
        pasteboard.writeObjects([item])
    }
}
