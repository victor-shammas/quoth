import Foundation

/// What a locked recording's live text has done so far, and the rules for
/// each new segment. Pure; `LiveTranscription` transcribes the segments and
/// delivers what this says to.
///
/// When a delivery fails, later segments are not typed: after a focus
/// change everything from that segment on is held for the clipboard, and
/// after a password field (or anything else) nothing more is delivered.
/// Text already typed stays.
public struct LiveTextLedger: Equatable, Sendable {
    /// Everything transcribed, typed or held, for Copy Last Dictation.
    public private(set) var text = ""
    /// Characters transcribed.
    public private(set) var chars = 0
    /// The first delivery failure, which stops typing.
    public private(set) var deliveryError: DeliveryError?
    /// Delivery stopped for a reason other than a `DeliveryError`.
    private var stoppedOtherwise = false
    /// Segments held back after a focus change, for the clipboard.
    private var held: [String] = []
    /// The segments typed so far, so "scratch that" can take the last one
    /// back out of `text`.
    private var typed: [String] = []

    public init() {}

    /// Whether segments are still being delivered.
    public var isDelivering: Bool { deliveryError == nil && !stoppedOtherwise }

    /// What "scratch that" should do: remove the last typed segment while
    /// delivering. Once delivery has stopped, it drops the last held segment
    /// here instead, and there is nothing for the caller to remove.
    public mutating func scratch() -> Bool {
        if isDelivering { return true }
        if !held.isEmpty { held.removeLast() }
        return false
    }

    /// The caller removed the last typed segment.
    public mutating func scratched() {
        guard !typed.isEmpty else { return }
        typed.removeLast()
        text = Self.join(typed)
    }

    /// A segment's text, after processing. Returns whether to deliver it;
    /// once delivery has stopped it is held or dropped instead.
    public mutating func add(_ segment: String) -> Bool {
        guard !segment.isEmpty else { return false }
        chars += segment.count
        text = Self.join([text, segment].filter { !$0.isEmpty })
        guard isDelivering else {
            if deliveryError == .focusChanged { held.append(segment) }
            return false
        }
        return true
    }

    /// The segment from `add` reached the cursor or the card.
    public mutating func delivered(_ segment: String) {
        typed.append(segment)
    }

    /// The segment from `add` was refused. After a focus change it is on the
    /// clipboard already; the end copies it again with everything after it.
    public mutating func deliveryFailed(_ segment: String, error: DeliveryError?) {
        guard isDelivering else { return }
        if let error {
            deliveryError = error
            if error == .focusChanged { held.append(segment) }
        } else {
            stoppedOtherwise = true
        }
    }

    /// The held segments, joined, for the clipboard at the end. Nil when
    /// nothing is held.
    public var heldText: String? {
        held.isEmpty ? nil : Self.join(held)
    }

    /// Segments as one text, spaced as consecutive dictations are: no space
    /// between Chinese, Japanese or Thai segments.
    public static func join(_ segments: [String]) -> String {
        segments.reduce("") { text, segment in
            guard let last = text.last else { return segment }
            return text + (Spacing.needsSpace(after: last, text: segment) ? " " : "") + segment
        }
    }
}
