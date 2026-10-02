import SwiftUI

/// The push-to-talk key (#42), a row in the General section.
struct HotkeyRow: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        PillRow("Hotkey") {
            PillMenu(title: store.current.hotkey.key.displayName) {
                ForEach(HotkeyKey.allCases, id: \.self) { key in
                    Toggle(key.displayName, isOn: Binding(
                        get: { store.current.hotkey.key == key },
                        set: { on in if on { store.update { $0.hotkey.key = key } } }
                    ))
                }
            }
        }
        // Outside a Form a toggle is a checkbox; this keeps the switch on
        // the right, like Launch at login.
        PillRow("Double-tap to lock") {
            Toggle("Double-tap to lock", isOn: Binding(
                get: { store.current.hotkey.doubleTapLock },
                set: { on in store.update { $0.hotkey.doubleTapLock = on } }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        PillRow("Live text while locked") {
            Toggle("Live text while locked", isOn: Binding(
                get: { store.current.hotkey.liveText },
                set: { on in store.update { $0.hotkey.liveText = on } }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(!store.current.hotkey.doubleTapLock)
        }
    }
}
