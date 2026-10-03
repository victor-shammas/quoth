# Architecture

Last updated: `2026.10.02`

> This document is the target structure. Contributors and agents read it first: it says where each kind of change belongs, so parallel work composes instead of colliding.

Quoth is a macOS menu-bar dictation app. Hold a key, speak, release, and the transcript appears at the cursor; double-tap the key to dictate hands-free, with text typed at each pause. Everything runs on the Mac: audio and text never leave it. It ships as two editions from this one codebase (ADR-006).

## Contents

1. [Goals and non-goals](#1-goals-and-non-goals)
2. [Targets and editions](#2-targets-and-editions)
3. [Layout](#3-layout)
4. [The dictation loop](#4-the-dictation-loop)
5. [Settings](#5-settings)
6. [Files on disk](#6-files-on-disk)
7. [Startup and failure](#7-startup-and-failure)
8. [Rules](#8-rules)
9. [Permissions](#9-permissions)
10. [Decision log](#10-decision-log)

## 1. Goals and non-goals

### 1.1 — Goals

1. **Dictation into any app.** Hold a hotkey, speak, release, and the text lands in the focused field. Double-tap for hands-free dictation of any length.
2. **On-device.** No network calls for transcription. Audio never leaves the machine.
3. **Minimal surface.** A menu-bar item, a small recording pill, and one Settings window. No Dock icon, no main window.
4. **Your words.** A dictionary spells names and terms your way; Fix Last Dictation adds to it from a real mistake.
5. **Trustworthy by construction.** Transcript text is never written to logs or disk.
6. **Pluggable engines.** Whisper (WhisperKit) today, behind the `Transcriber` protocol.

### 1.2 — Non-goals

- Cross-platform. Quoth depends on CoreML and the Apple Neural Engine.
- Cloud transcription, AI rewriting, reading the screen.
- Transcript history or search. The last dictation is kept in memory only, for minutes.
- File and meeting transcription.

## 2. Targets and editions

```
Package.swift (the direct edition)
  QuothCore       library     all behaviour: capture, hotkey, transcription, pipeline, settings, UI
  quoth           executable  thin entry point: ArgumentParser commands that call into QuothCore
  quoth-bench     executable  developer benchmarks, never shipped
  QuothTests, QuothBenchTests

project.yml (the App Store edition, generated with xcodegen)
  Quoth           app         Sources/QuothCore compiled with APPSTORE, plus AppStore/main.swift;
                              leaves out Updater, CommandLineLink, Setup, Doctor, ModelCommands
```

The direct `Quoth.app` wraps the `quoth` executable (`scripts/build-app.sh`). The same binary runs as the app (launched by `SMAppService` or from Finder) and as the CLI (through a symlink); with no subcommand it runs the dictation loop. The App Store app is always the menu-bar app.

Everything that differs between the editions is decided in `Support/Edition.swift` (`Edition`, `HotkeyAccess`, `PasteAccess`); see ADR-006. QuothCore types the benchmarks need are marked `package`; the App Store target compiles with `-package-name quoth` for the same reason.

## 3. Layout

```
Sources/QuothCore/
  App/
    DictationController.swift   the dictation loop: press → capture → transcribe → process → deliver; locks and live text
    DictationObserver.swift     observer protocol and DictationResult (counts and timings, never text)
    LatencyLog.swift            one log line per dictation, as a DictationObserver
    LastDictation.swift         the last transcript, in memory only, for Copy and Fix Last Dictation
    Startup.swift               startup checks and StartupFailure (permanent vs transient)
    Permissions.swift           the hotkey, microphone and paste grants, and what each Allow button asks (pure, tested)
    Onboarding.swift            when the onboarding window shows and what Get Started saves (pure, tested)
    Daemon.swift                the `run` command: startup, wiring, run loop
    ModelSwitcher.swift         a model change while running: loads behind the menu bar, swaps between dictations
    AppLaunch.swift             the app role: bundle detection, single instance, startup dialogs
    LoginItem.swift             launch at login (SMAppService)
    Updater.swift, CommandLineLink.swift, Setup.swift, Doctor.swift, ModelCommands.swift
                                direct edition only: Sparkle, the `quoth` symlink, and the other commands
  Support/
    Edition.swift               what the direct and App Store editions do differently (ADR-006)
    Paths.swift                 every on-disk location Quoth uses
    Log.swift                   stderr logging; never logs transcript text
    SilentExit.swift            "message printed, exit with this code", so QuothCore needs no ArgumentParser
  Settings/
    Settings.swift              Codable settings value with defaults, and reset()
    SettingsStore.swift         load, atomic save, file watching, change publishing
  Input/
    HotkeyMonitor.swift         the listen-only tap for modifier changes, the lock's time limit
    Gesture.swift               press/release rules: short taps, chords, the double-tap lock (pure, tested)
    HotkeySettings.swift        the key, the lock and live text
    TapRecovery.swift           re-enabling a disabled tap; the menu's hotkey status
    FocusSnapshot.swift         what was focused, and whether it is secure; field details in the direct edition
    Delivery.swift              insert, copy or discard (pure decision, tested)
    Spacing.swift               the spaces around a transcript (pure, tested)
    TextInjector.swift          paste or typed Unicode; the borrowed clipboard
  Audio/
    AudioCapture.swift, CaptureBuffer.swift
                                capture, conversion to 16 kHz, per-capture stats; samples so far, for live text
    CaptureInput.swift, HALInput.swift, EngineInput.swift
                                ways of running the mic; the AUHAL unit is the default
    HostClock.swift, InputDevice.swift, MicrophoneAccess.swift, ConverterCache.swift, SilenceTrimmer.swift
  Transcription/
    Transcriber.swift           protocol and TranscriptionContext (language, prompt, previous text)
    WhisperKitTranscriber.swift loading, transcribing, the on-disk model cache and deleting a model
    WhisperTuning.swift         compute units and decoding options, measured with `quoth-bench`
    SpokenLanguage.swift, LanguageDetector.swift, LanguageSettings.swift
                                the language each dictation decodes in
    ModelRegistry.swift, TranscriptionModel.swift, ModelSettings.swift
  Pipeline/
    Transcript.swift, TranscriptProcessor.swift
    VoiceCommands.swift         "new paragraph", "new line"
    PauseSplitter.swift         where a locked recording is cut into segments (pure, tested)
    LiveTranscription.swift     a locked recording's segments, transcribed and typed in order
  Dictionary/
    Dictionary.swift            terms, replacements, example sentences; the plain-text table's parser and writer
    DictionaryStore.swift       loads, reloads on change, saves without overwriting a change made elsewhere
    DictionaryProcessor.swift   the replacement pass, with loose matching
    DictionaryContext.swift, DictionarySettings.swift
                                the example sentence for the active language, as the prompt
  UI/
    MenuBarController.swift, QuoteGlyph.swift
                                the menu and its state glyph
    RecordingOverlay.swift      the pill: recording, locked, transcribing, messages
    OnboardingWindow.swift      hotkey, languages and the grants on one page
    SettingsWindow.swift        toolbar tabs, each pane sizing the window
    Settings/                   GeneralPane, ModelPane, DownloadedModels, DictionaryPane, AboutPane
    FixDictationWindow.swift, AcknowledgementsWindow.swift, AcknowledgementsText.swift (generated)
    EditingWindow.swift         a window whose fields take ⌘C, ⌘V and the rest without a main menu
    Pill.swift                  the pill controls shared with onboarding

Sources/quoth/main.swift        ArgumentParser commands: run, setup, doctor, models, install
Sources/quoth-bench/            transcription and capture benchmarks
AppStore/                       the App Store edition: entry point, Info.plist, entitlements, privacy manifest, icon
docs/                           these documents, and the website (index, support, privacy)
```

## 4. The dictation loop

### 4.1 — Flow

```
HotkeyMonitor ──flags──▶ Gesture ──start/stop/lock──▶ DictationController
                                                         │
                                  start: FocusSnapshot + AudioCapture.start
                                  lock:  LiveTranscription polls the capture,
                                         cuts at pauses (PauseSplitter), and
                                         transcribes and delivers each segment
                                  stop:  AudioCapture.finish → [Float]
                                                         │
                                                         ▼
                              Transcriber.transcribe(audio, context)
                                  context = language + prompt (dictionary sentence, previous segment)
                                                         │ Transcript
                                                         ▼
                              [TranscriptProcessor] in order: VoiceCommands, DictionaryProcessor
                                                         │ Transcript
                                                         ▼
                              delivery: paste at the cursor if focus is unchanged and pasting is
                                        allowed; clipboard otherwise; discard in a password field
                                                         │
                                                         ▼
                              DictationObservers: overlay, menu bar, latency log
                              LastDictation (memory only): Copy and Fix Last Dictation
```

`DictationController` owns the state machine (`idle`, `recording`, `transcribing`) and the lock. It is `@MainActor`; transcription runs off the main actor.

### 4.2 — Extension points

| Point | Shape | Used by |
|---|---|---|
| `TranscriptionContext` | language, prompt, previous text | dictionary prompting, language, live text |
| `TranscriptProcessor` | `func process(_ transcript: Transcript) -> Transcript` | voice commands, dictionary replacements |
| Delivery decision | injector or fallback, from `FocusSnapshot` and `PasteAccess` | secure fields, focus drift, copy-only |
| `DictationObserver` | started, locked, notice, transcribing, finished, failed; empty defaults | overlay, menu bar, latency |
| Settings pane | a field in `Settings` plus a view in `UI/Settings/` | hotkey, model, dictionary |

## 5. Settings

One file: `~/.config/quoth/settings.json` (or `$XDG_CONFIG_HOME/quoth/`), a `Codable` `Settings` value. A missing key takes its default. Writes are atomic. `SettingsStore` watches the directory, so hand edits apply live, and a file that fails to parse keeps the last good settings. Reset to Defaults keeps the example sentences, spoken languages and onboarding state.

## 6. Files on disk

Every location comes from `Paths`. In the App Store edition the home folder is the app's container, so the same paths land inside it.

| Location | Contents |
|---|---|
| `~/.config/quoth/` | `settings.json` and `dictionary` (a plain-text table; see [dictionary.md](dictionary.md)) |
| `~/Library/Application Support/quoth/` | `models/` and the single-instance lock |
| `~/Library/Logs/quoth/` | logs, owner-only; timings and counts, never transcript text |
| `~/Library/Caches/quoth/` | `--dump-wav` debug captures, owner-only |

## 7. Startup and failure

`Startup` checks the microphone authorization and the selected model before loading anything. A permanent `StartupFailure` (denied microphone, unknown model) shows one actionable message, a dialog in the app, and exits 0; anything else exits nonzero. The App Store edition's dialogs never mention the command line.

Everything after the checks happens behind the menu-bar icon: the model loads (downloading on first run) with "Loading model…" in the menu, a failed load retries with backoff, and the hotkey starts once a model is ready and its grant is in place.

## 8. Rules

1. Never write transcript text to logs, disk, or anywhere outside the cursor and the clipboard. The dictionary is the only user-authored text Quoth stores.
2. Every on-disk location comes from `Paths`.
3. Every persistent preference lives in `Settings` and changes through `SettingsStore`. No `UserDefaults`, apart from what Sparkle keeps in the direct edition.
4. New behaviour after transcription is a `TranscriptProcessor` or a `DictationObserver`.
5. Pure logic has unit tests in `QuothTests`.
6. The event tap listens to `flagsChanged` only.
7. Only `Edition`, `HotkeyAccess` and `PasteAccess` test `APPSTORE`, apart from leaving out the direct edition's call sites.

## 9. Permissions

| Grant | Direct edition | App Store edition |
|---|---|---|
| Microphone | required | required |
| The hotkey | Accessibility (which also covers pasting and reading the field) | Input Monitoring |
| Pasting at the cursor | covered by Accessibility | optional, listed under Accessibility; without it, transcripts are copied |

macOS keys grants to the app's code identity, so builds are signed with a stable identity (`scripts/dev-install.sh` takes `QUOTH_SIGN_IDENTITY`). Without the hotkey's grant the app keeps running with "Allow … to start" in the menu and starts the hotkey as soon as the grant appears.

The app never shows a system prompt unannounced. The onboarding window lists each grant with its own Allow button, so prompts never stack; "Finish Setup…" in the menu reopens it while a grant is missing. The rules are in `App/Onboarding.swift` and `App/Permissions.swift`, pure and tested.

## 10. Decision log

| ADR | Decision |
|---|---|
| [001](decisions/001-core-library-and-extension-points.md) | Core library and extension points |
| [002](decisions/002-settings-file.md) | Config in `~/.config/quoth`, data in Application Support |
| [003](decisions/003-push-to-talk-on-a-modifier.md) | Push-to-talk on a modifier, with a hands-free lock |
| [004](decisions/004-local-data-and-privacy.md) | Local data and privacy |
| [005](decisions/005-signed-app-identity.md) | Signed app identity |
| [006](decisions/006-two-editions.md) | Two editions from one codebase |
| [007](decisions/007-modules-and-app-model.md) | Modules, a dictation state machine, one app model; no command line (in progress) |
