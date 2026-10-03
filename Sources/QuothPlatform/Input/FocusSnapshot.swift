import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation
import QuothDomain

/// What had keyboard focus at one moment: the frontmost app, its focused
/// element, and whether that element is a secure (password) field.
///
/// Taken at recording start and again right before delivery, over
/// Accessibility, so delivery needs no watch on keystrokes or clicks.
public struct FocusSnapshot {
    /// The frontmost app, if any.
    public var pid: pid_t?
    /// The focused element, if the app exposes one over Accessibility.
    /// Internal, with `FocusedElement`, so the App Store build, where it is
    /// always nil, compiles no Accessibility calls (ADR-006).
    var element: FocusedElement?
    /// The focused element is a secure text field or reports protected content.
    public var isSecure: Bool

    /// Upper bound on each Accessibility call, so a hung app cannot stall
    /// the main thread (and with it the hotkey tap).
    private static let messagingTimeout: Float = 0.25

    @MainActor
    public static func capture() -> FocusSnapshot {
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        // The App Store build can't read other apps' elements: it compares
        // the frontmost app, and treats secure input (which macOS turns on
        // for password fields) as a secure field when that app turned it on.
        guard Edition.readsFocusedField else {
            return FocusSnapshot(pid: pid, element: nil, isSecure: secureInputIsFrontmost(pid))
        }
        let systemWide = AXUIElementCreateSystemWide()
        // On the system-wide element, this sets the timeout for every element.
        AXUIElementSetMessagingTimeout(systemWide, messagingTimeout)

        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &value)
        guard status == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return FocusSnapshot(pid: pid, element: nil, isSecure: false)
        }
        let element = value as! AXUIElement
        return FocusSnapshot(pid: pid, element: FocusedElement(element), isSecure: isSecure(element))
    }

    /// Whether the frontmost app (`pid`) has secure input on. Secure input is
    /// system-wide, and Terminal's Secure Keyboard Entry or a password
    /// manager can leave it on for every app, so the session's owner of it
    /// must be the frontmost app. With no owner recorded, it counts: never
    /// type into what may be a password field.
    public static func secureInputIsFrontmost(_ pid: pid_t?) -> Bool {
        guard IsSecureEventInputEnabled() else { return false }
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              let owner = (session["kCGSSessionSecureInputPID"] as? NSNumber)?.int32Value
        else { return true }
        return pid.map { $0 == owner } ?? true
    }

    /// Whether focus moved from `self` to `now`. The app must match. The
    /// element must match when both snapshots saw one; an element seen only
    /// once is not a change, because Chromium and Electron apps build their
    /// Accessibility tree lazily and may expose nothing at recording start.
    public func hasChanged(to now: FocusSnapshot) -> Bool {
        if pid != now.pid { return true }
        if let element, let other = now.element, element != other { return true }
        return false
    }

    /// Secure only when the element says so. One that can't be read isn't
    /// treated as secure, or every app without Accessibility support would
    /// lose its dictation.
    private static func isSecure(_ element: AXUIElement) -> Bool {
        if AX.value(element, kAXSubroleAttribute) as String? == kAXSecureTextFieldSubrole as String { return true }
        return AX.value(element, NSAccessibility.Attribute.containsProtectedContent.rawValue) as Bool? ?? false
    }
}

/// An Accessibility element compared by identity (`CFEqual`). Internal, with
/// everything that reads it, so the App Store build, which never has one,
/// links no Accessibility calls (ADR-006).
struct FocusedElement: Equatable {
    let ref: AXUIElement

    init(_ ref: AXUIElement) { self.ref = ref }

    static func == (lhs: FocusedElement, rhs: FocusedElement) -> Bool { CFEqual(lhs.ref, rhs.ref) }

    /// The character before the insertion point, for `Spacing`. Call after
    /// `FocusSnapshot.capture()`, which sets the timeout, and never on a
    /// secure field.
    func textBeforeCursor() -> TextBeforeCursor {
        guard let rangeValue: CFTypeRef = AX.value(ref, kAXSelectedTextRangeAttribute),
              CFGetTypeID(rangeValue) == AXValueGetTypeID() else { return .unknown }
        var range = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range), range.location >= 0 else { return .unknown }
        return .reading(
            location: range.location,
            fieldLength: range.location == 0 ? characterCount() : nil,
            before: range.location > 0 ? string(before: range.location) : nil,
            value: { AX.value(ref, kAXValueAttribute) }
        )
    }

    /// Up to two UTF-16 units before `location`, where the app answers
    /// `AXStringForRange`.
    private func string(before location: Int) -> String? {
        var range = CFRange(location: location - min(location, 2), length: min(location, 2))
        guard let query = AXValueCreate(.cfRange, &range) else { return nil }
        var text: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(ref, kAXStringForRangeParameterizedAttribute as CFString, query, &text) == .success else { return nil }
        return text as? String
    }

    /// The field's length in UTF-16 units, or nil when the app doesn't say.
    private func characterCount() -> Int? {
        AX.value(ref, kAXNumberOfCharactersAttribute) ?? (AX.value(ref, kAXValueAttribute) as String?)?.utf16.count
    }
}

/// Reading one Accessibility attribute, typed.
private enum AX {
    static func value<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? T
    }
}
