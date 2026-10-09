import AppKit
import QuothDomain
import QuothPlatform
import SwiftUI

/// General: how dictation starts (the hotkey, the lock, live text), other
/// sound while dictating, opening at login, and in the App Store build the
/// optional paste grant.
struct GeneralPane: View {
    @ObservedObject var store: SettingsStore

    private var hotkey: HotkeySettings { store.current.hotkey }

    var body: some View {
        Pane {
            DictationClash(key: hotkey.key) { clash in
            VStack(alignment: .leading, spacing: 18) {
            // The App Store edition can't read the shortcut, so for fn it can only advise.
            SettingsSection("Dictation", footer: clash == .unknown && hotkey.key == .fn && hotkey.doubleTapLock
                ? "If a double tap of fn starts Apple's Dictation too, turn off its shortcut in Keyboard settings."
                : nil) {
                SettingRow("Hotkey", caption: "Hold it to dictate.") {
                    Picker("Hotkey", selection: Binding(
                        get: { hotkey.key },
                        set: { key in store.update { $0.hotkey.key = key } }
                    )) {
                        ForEach(HotkeyKey.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                if clash == .clashes {
                    RowDivider()
                    DictationClashRow(key: hotkey.key)
                }
                RowDivider()
                SettingRow("Double-tap to lock", caption: "Hands-free dictation; tap once to stop.") {
                    switchToggle("Double-tap to lock", isOn: Binding(
                        get: { hotkey.doubleTapLock },
                        set: { on in store.update { $0.hotkey.doubleTapLock = on } }
                    ))
                }
                RowDivider()
                SettingRow("Hands-free goes to", caption: hotkey.lockTarget == .card || !PasteAccess.isGranted
                    ? "A Quote Card, to edit before ⌘↩ inserts it."
                    : "Straight to the cursor in the app you're in.") {
                    Picker("Hands-free goes to", selection: Binding(
                        get: { PasteAccess.isGranted ? hotkey.lockTarget : .card },
                        set: { target in store.update { $0.hotkey.lockTarget = target } }
                    )) {
                        ForEach(LockTarget.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    // Without the paste grant, the card is the only way.
                    .disabled(!PasteAccess.isGranted)
                }
                .disabled(!hotkey.doubleTapLock)
                RowDivider()
                SettingRow("Live text while locked", caption: "Text appears each time you pause.") {
                    switchToggle("Live text while locked", isOn: Binding(
                        get: { hotkey.liveText },
                        set: { on in store.update { $0.hotkey.liveText = on } }
                    ))
                }
                .disabled(!hotkey.doubleTapLock)
                RowDivider()
                SettingRow("Voice commands", caption: "Punctuation and editing by voice; see Help.") {
                    VoiceCommandsButton()
                }
            }

            if clash == .unknown && hotkey.key == .fn && hotkey.doubleTapLock {
                Button("Open Keyboard Settings") { SystemDictation.openKeyboardSettings() }
                    .buttonStyle(.link)
                    .font(.caption)
                    .padding(.top, -14)
                    .padding(.leading, 4)
            }
            }
            }

            SettingsSection("Sound") {
                SettingRow(
                    "Fade out sound while dictating",
                    caption: "Lowers the Mac's volume while the microphone is on, and brings it back after. A Bluetooth headset recording with its own microphone is left alone."
                ) {
                    switchToggle("Fade out sound while dictating", isOn: Binding(
                        get: { store.current.sound.fadeWhileDictating },
                        set: { on in store.update { $0.sound.fadeWhileDictating = on } }
                    ))
                }
            }

            SettingsSection("Startup") {
                LaunchAtLoginRow()
                if Edition.pasteNeedsOwnGrant {
                    RowDivider()
                    PasteRow()
                }
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
            SettingRow("Open at login") {
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
            SettingRow("Open at login", caption: "Available when Quoth runs as Quoth.app.") {
                EmptyView()
            }
        }
    }
}

/// App Store build: the optional grant to paste at the cursor. Re-read when
/// the window comes forward, since it is given in System Settings; macOS
/// shows it only to a new launch, so after Allow the button reopens Quoth.
private struct PasteRow: View {
    @State private var granted = PasteAccess.isGranted
    @State private var asked = false

    var body: some View {
        SettingRow("Paste at cursor", caption: "Allow Quoth under Accessibility in System Settings. Without it, each dictation is copied, ready for ⌘V.") {
            if granted {
                AllowedLabel()
            } else if asked && Permissions.showsAfterRelaunch(.paste) {
                Button("Reopen Quoth") { AppLaunch.relaunch() }
                    .help("Once it's on in System Settings, Quoth sees it after reopening.")
            } else {
                Button("Allow…") {
                    asked = true
                    Permissions.perform(.promptPaste)
                    Permissions.perform(.openPasteSettings)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            granted = PasteAccess.isGranted
        }
    }
}

/// The list of voice commands, in a popover.
private struct VoiceCommandsButton: View {
    @State private var isOpen = false

    var body: some View {
        Button("Show…") { isOpen.toggle() }
            .popover(isPresented: $isOpen, arrowEdge: .bottom) {
                // A fixed width and the list's own height: without them the
                // popover has no size to take and opens tall and empty.
                VoiceCommandList()
                    .padding(16)
                    .frame(width: 470)
                    .fixedSize(horizontal: false, vertical: true)
            }
    }
}

/// Every voice command and what it does, for the popover and the cheat
/// sheet in About.
struct VoiceCommandList: View {
    static let commands: [(say: String, does: String)] = [
        ("“new paragraph”, “new line”", "Break the text"),
        ("“bullet point”", "Start a bulleted line"),
        ("“comma”, “semicolon”, “question mark”, “exclamation point”, “full stop”", "Type the mark"),
        ("“period”, “colon”", "Type the mark, when you pause around the word"),
        ("“quote” … “unquote”", "Put the words between in “quotes”"),
        ("“scratch that”", "Remove what you said just before it, or, on its own, what Quoth just typed"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text("Say").frame(width: 210, alignment: .leading)
                Text("To")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Latte.secondary)
            ForEach(Self.commands, id: \.say) { command in
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(command.say).frame(width: 210, alignment: .leading)
                    Text(command.does).foregroundStyle(Latte.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            Text("In English, for now.")
                .font(.caption)
                .foregroundStyle(Latte.secondary)
        }
        .font(.callout)
    }
}
