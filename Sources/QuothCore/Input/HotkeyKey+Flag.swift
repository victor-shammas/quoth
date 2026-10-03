import CoreGraphics
import QuothDomain

extension HotkeyKey {
    /// The device-independent flag this key sets. Left and right share it.
    var flag: CGEventFlags {
        switch self {
        case .fn: return .maskSecondaryFn
        case .leftOption, .rightOption: return .maskAlternate
        case .leftCommand, .rightCommand: return .maskCommand
        case .leftControl, .rightControl: return .maskControl
        case .leftShift, .rightShift: return .maskShift
        }
    }
}
