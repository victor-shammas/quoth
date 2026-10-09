import Carbon.HIToolbox
import Foundation
import QuothDomain

/// A key combination registered with the system (`RegisterEventHotKey`), for
/// the App Store edition's hotkey. It needs no permission and works in the
/// sandbox, and reports both the press and the release, so hold-to-talk and
/// the double tap work as with a modifier key. Only the registered
/// combination is ever seen.
///
/// Events arrive on the main thread.
final class GlobalShortcut {
    /// The combination went down.
    var onPress: (() -> Void)?
    /// It came back up.
    var onRelease: (() -> Void)?

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    /// Tells this registration's events from any other's.
    private static let signature: OSType = 0x5154_484B // 'QTHK'

    /// Registers `key`, replacing any earlier one. False when it can't be:
    /// another app holds the same combination, or `key` isn't one.
    func register(_ key: HotkeyKey) -> Bool {
        unregister()
        guard key.isShortcut, installHandler() else { return false }
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(key.keycode), Self.carbonModifiers(key.shortcutModifiers), id,
            GetApplicationEventTarget(), 0, &ref
        )
        guard status == noErr, let ref else { return false }
        hotKey = ref
        return true
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }

    deinit {
        unregister()
        if let handler { RemoveEventHandler(handler) }
    }

    /// Carbon's modifier mask for `modifiers`.
    static func carbonModifiers(_ modifiers: [ShortcutModifier]) -> UInt32 {
        modifiers.reduce(0) { mask, modifier in
            switch modifier {
            case .control: return mask | UInt32(controlKey)
            case .option: return mask | UInt32(optionKey)
            case .shift: return mask | UInt32(shiftKey)
            case .command: return mask | UInt32(cmdKey)
            }
        }
    }

    private func installHandler() -> Bool {
        guard handler == nil else { return true }
        let kinds = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
                return shortcut.handle(event)
            },
            kinds.count, kinds, Unmanaged.passUnretained(self).toOpaque(), &handler
        )
        return status == noErr
    }

    private func handle(_ event: EventRef) -> OSStatus {
        var id = EventHotKeyID()
        let status = GetEventParameter(
            event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
            nil, MemoryLayout<EventHotKeyID>.size, nil, &id
        )
        guard status == noErr, id.signature == Self.signature else { return OSStatus(eventNotHandledErr) }
        switch Int(GetEventKind(event)) {
        case kEventHotKeyPressed: onPress?()
        case kEventHotKeyReleased: onRelease?()
        default: return OSStatus(eventNotHandledErr)
        }
        return noErr
    }
}
