import AppKit
import QuothDomain
import QuothPlatform
import SwiftUI

/// The choices on the page, the grants, and the Allow and Get Started actions.
@MainActor
final class OnboardingModel: ObservableObject {
    @Published private(set) var state = PermissionState.current
    @Published var hotkey: HotkeyKey
    /// Ticked languages as codes, in the order ticked.
    @Published private(set) var languages: [String]

    let hotkeyChoices: [HotkeyKey]
    let preferred: [String]
    var onGetStarted: (() -> Void)?
    /// A grant changed: the microphone prompt was answered, or a switch
    /// flipped in System Settings.
    var onGrantsChanged: (() -> Void)?

    init(settings: QuothDomain.Settings, preferred: [String] = SpokenLanguage.preferredCodes()) {
        hotkey = settings.hotkey.key
        hotkeyChoices = Onboarding.hotkeyChoices(current: settings.hotkey.key)
        self.preferred = preferred
        languages = Onboarding.initialLanguages(saved: settings.language.spoken, preferred: preferred)
    }

    var canGetStarted: Bool { state.allGranted && !languages.isEmpty }

    func update(_ now: PermissionState) {
        guard now != state else { return }
        state = now
        onGrantsChanged?()
    }

    func isTicked(_ code: String) -> Bool { languages.contains(code) }

    func toggle(_ code: String) {
        if let index = languages.firstIndex(of: code) {
            languages.remove(at: index)
        } else {
            languages.append(code)
        }
    }

    /// The grants whose Allow was clicked in this window.
    @Published private(set) var asked = Set<Permissions.Kind>()

    /// Allow was clicked, but this launch can't see the grant: only a new one can.
    func needsReopen(_ kind: Permissions.Kind) -> Bool {
        asked.contains(kind) && Permissions.showsAfterRelaunch(kind)
    }

    /// Runs `kind`'s steps, waiting for the microphone prompt's answer before
    /// re-reading the grants.
    func allow(_ kind: Permissions.Kind) {
        asked.insert(kind)
        let steps = Permissions.allowSteps(for: kind, in: state)
        if steps == [.requestMicrophone] {
            MicrophoneAccess.requestIfUndetermined { [weak self] in
                MainActor.assumeIsolated { self?.update(PermissionState.current) }
            }
            return
        }
        steps.forEach(Permissions.perform)
    }

    func getStarted() { onGetStarted?() }
}

/// The page, in Quoth's latte look: the app icon and name, the hotkey and
/// languages, the grants, each with its reason, and Get Started.
struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    @State private var showsLanguages = false

    var body: some View {
        VStack(spacing: 0) {
            AppBadge(size: 72)
            Text("Welcome to Quoth")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Latte.text)
                .padding(.top, 14)
            Text("Hold a key, speak, and let go. Your words appear where you type.")
                .foregroundStyle(Latte.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 18) {
                SettingsSection("Set up") {
                    SettingRow("Hotkey", caption: "Hold it to dictate; double-tap for hands-free.") {
                        Picker("Hotkey", selection: Binding(get: { model.hotkey }, set: { model.hotkey = $0 })) {
                            ForEach(model.hotkeyChoices, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    DictationClash(key: model.hotkey) { clash in
                        if clash == .clashes {
                            RowDivider()
                            DictationClashRow(key: model.hotkey)
                        }
                    }
                    RowDivider()
                    SettingRow("Languages", caption: "The ones you dictate in.") {
                        Button(Onboarding.summary(model.languages.map { SpokenLanguage.displayName($0) })) {
                            showsLanguages.toggle()
                        }
                        .popover(isPresented: $showsLanguages, arrowEdge: .bottom) {
                            OnboardingLanguages(model: model)
                        }
                    }
                }

                SettingsSection("Permissions") {
                    SettingRow("Microphone", caption: "To hear you while you dictate.") {
                        permission(.microphone, granted: model.state.microphone == .granted,
                                   action: model.state.microphone == .denied ? "Open Settings" : "Allow")
                    }
                    RowDivider()
                    SettingRow(HotkeyAccess.name, caption: Edition.isAppStore
                        ? "To notice your hotkey. Quoth only watches keys like fn, never what you type."
                        : "To notice your hotkey and paste at the cursor. Quoth never sees what you type.") {
                        permission(.hotkey, granted: model.state.hotkey, action: "Allow")
                    }
                    if Edition.pasteNeedsOwnGrant {
                        RowDivider()
                        // Optional: without it, each transcript is copied for ⌘V.
                        SettingRow("Paste at cursor", caption: "Optional. Without it, dictations are copied for ⌘V.") {
                            permission(.paste, granted: model.state.paste, action: "Allow")
                        }
                    }
                }
            }
            .padding(.top, 26)

            Button("Get Started") { model.getStarted() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canGetStarted)
                .padding(.top, 24)

            Label("Audio and text never leave your Mac.", systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(Latte.secondary)
                .padding(.top, 12)
        }
        .padding(.horizontal, 32)
        .padding(.top, 40)
        .padding(.bottom, 24)
        .frame(width: 480)
        .tint(Latte.tint)
        .background(Latte.background)
    }

    @ViewBuilder
    private func permission(_ kind: Permissions.Kind, granted: Bool, action: String) -> some View {
        if granted {
            AllowedLabel()
        } else if model.needsReopen(kind) {
            // macOS shows this grant to a new launch only.
            Button("Reopen Quoth") { AppLaunch.relaunch() }
                .buttonStyle(.borderedProminent)
                .help("Once it's on in System Settings, Quoth sees it after reopening.")
        } else {
            Button(action) { model.allow(kind) }
                // Prominent, so the missing grants read as what to do next.
                .buttonStyle(.borderedProminent)
        }
    }
}

/// The Languages popover, observing the model so ticks show as they change.
private struct OnboardingLanguages: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        LanguageChecklist(ticked: model.languages, toggle: model.toggle)
    }
}
