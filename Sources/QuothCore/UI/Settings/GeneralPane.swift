import AppKit
import SwiftUI

/// General: how dictation starts (the hotkey, the lock, live text), opening
/// at login, and in the App Store build the optional paste grant.
struct GeneralPane: View {
    @ObservedObject var store: SettingsStore

    private var hotkey: HotkeySettings { store.current.hotkey }

    var body: some View {
        Pane {
            PillRow("Hotkey", caption: "Hold it to dictate.") {
                PillMenu(title: hotkey.key.displayName) {
                    ForEach(HotkeyKey.allCases, id: \.self) { key in
                        Toggle(key.displayName, isOn: Binding(
                            get: { hotkey.key == key },
                            set: { on in if on { store.update { $0.hotkey.key = key } } }
                        ))
                    }
                }
            }

            PillRow("Double-tap to lock", caption: "Double-tap the hotkey to keep recording hands-free; tap once to stop.") {
                switchToggle("Double-tap to lock", isOn: Binding(
                    get: { hotkey.doubleTapLock },
                    set: { on in store.update { $0.hotkey.doubleTapLock = on } }
                ))
            }

            PillRow("Live text while locked", caption: "Text appears each time you pause.") {
                switchToggle("Live text while locked", isOn: Binding(
                    get: { hotkey.liveText },
                    set: { on in store.update { $0.hotkey.liveText = on } }
                ))
            }
            .disabled(!hotkey.doubleTapLock || !PasteAccess.isGranted)

            PillRow("Voice commands", caption: "Say “new paragraph” or “new line” to start one. English only, for now.") {
                EmptyView()
            }

            if hotkey.key == .fn && hotkey.doubleTapLock {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Caption("If a double tap of fn starts Apple's Dictation instead, turn off its shortcut in Keyboard settings.")
                    Spacer(minLength: 0)
                    Button("Open Keyboard Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.pill)
                    .fixedSize()
                }
            }

            Divider()

            LaunchAtLoginRow()

            if Edition.pasteNeedsOwnGrant {
                PasteRow()
            }
        }
    }
}

/// A switch on the right, like the other controls; outside a Form a
/// toggle would be a checkbox.
func switchToggle(_ label: String, isOn: Binding<Bool>) -> some View {
    Toggle(label, isOn: isOn)
        .toggleStyle(.switch)
        .labelsHidden()
}

/// Opening at login through `SMAppService`. Read live, since the user can
/// change it in System Settings while Quoth runs; not stored in
/// `settings.json`.
private struct LaunchAtLoginRow: View {
    @State private var isOn = LoginItem.isEnabled

    var body: some View {
        if LoginItem.isAvailable {
            PillRow("Open at login") {
                switchToggle("Open at login", isOn: Binding(
                    get: { isOn },
                    set: { on in
                        do {
                            try LoginItem.setEnabled(on)
                        } catch {
                            Log.warning("couldn't change open at login: \(error)")
                        }
                        isOn = LoginItem.isEnabled
                    }
                ))
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
                isOn = LoginItem.isEnabled
            }
        } else {
            PillRow("Open at login", caption: "Available when Quoth runs as Quoth.app.") {
                EmptyView()
            }
        }
    }
}

/// App Store build: the optional grant to paste at the cursor. Re-read when
/// the window comes forward, since it is given in System Settings.
private struct PasteRow: View {
    @State private var granted = PasteAccess.isGranted

    var body: some View {
        PillRow("Paste at cursor", caption: "Allow Quoth under Accessibility in System Settings. Without it, each dictation is copied, ready for ⌘V.") {
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
            } else {
                Button("Allow…") {
                    Permissions.perform(.promptPaste)
                    Permissions.perform(.openPasteSettings)
                }
                .buttonStyle(.pill)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            granted = PasteAccess.isGranted
        }
    }
}
