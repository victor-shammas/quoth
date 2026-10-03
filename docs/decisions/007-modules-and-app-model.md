# ADR-007 :: Modules, a dictation state machine, and one app model

Last updated: `2026.10.03`

> Quoth is restructured into four modules with one-way dependencies, the dictation loop becomes a pure state machine whose effects run in one place, and the UI reads a single observable app model. The command line goes: both editions are the menu-bar app. This supersedes ADR-001.

## 1. Decision

### 1.1 — Modules

| Module | Holds | Imports |
|---|---|---|
| `QuothDomain` | Pure Swift: the dictation state machine, gesture rules, delivery decisions, spacing, voice commands, the dictionary model and matcher, pause splitting, settings values, the model catalog | Foundation only |
| `QuothSpeech` | The `Transcriber` protocol's engine (WhisperKit), decoding options, the on-disk model store | Domain, Platform (for `Paths`), WhisperKit |
| `QuothPlatform` | macOS behind small protocols: `Microphone`, `HotkeySource`, `TextSink`, `FocusProbe`, `Permissions`, `Capabilities` | Domain, AppKit, Core Audio, ApplicationServices |
| `QuothCore` | The app: `AppModel`, `DictationSession`, the windows and views, the stores, and the composition root (`Assembly`) | all of the above |

Dependencies point down the table and never back up. The compiler enforces it: a module can't import one it doesn't list.

### 1.2 — The dictation loop is a state machine

- `DictationMachine` in `QuothDomain` is a value type with one method: `mutating func handle(_ event: Event) -> [Effect]`. Events are hotkey actions, capture results, transcripts, delivery outcomes and route changes. Effects are instructions: start capture, transcribe these samples, deliver this text, show this notice.
- Every state the loop can be in is one case of one enum, with the data that state needs attached. There are no parallel flags such as `isLocked` beside `state`.
- `DictationSession` in `QuothCore` is the only code that performs effects. It feeds their results back as events. It holds no decisions of its own.
- The edge cases in section 3 are unit tests of `DictationMachine`, with no audio, tap or WhisperKit involved.

### 1.3 — One app model

- `AppModel` (`@Observable`, `@MainActor`) is the single source of truth for what the UI shows: the dictation phase, hotkey health, model status, grants, whether a last dictation is available, and the Quote Card's text.
- The menu bar reads `AppModel` and sends intents to it; the Quote Card asks for what it needs through `QuoteCardHost`, which `AppModel` implements. The closures wired in `Daemon.runLoop` go.
- Moments stay `DictationObserver`s: the pill's messages and level meter, the card's status, the latency log. They are events with their own timing, not state, and forcing them through the model would only re-time their animations. `AppModel` is itself an observer, for the activity the menu shows.
- The composition root builds the modules' concrete types once and hands them to `AppModel`. It holds no logic.

### 1.4 — Editions

- `Edition` stays a set of compile-time constants in `QuothPlatform`, which the App Store project compiles with `APPSTORE`. (The first plan was a `Capabilities` value passed in at runtime, so tests could run both editions in one process. Constants are what let the compiler drop every Accessibility call from the App Store build, which ADR-006 relies on.)
- The Accessibility types (`FocusedElement`) stay internal to `QuothPlatform`: public, they can't be dropped, and the App Store build links five AX functions. `scripts/appstore.sh` fails the build if any appear.

### 1.5 — No command line

- Both editions are the menu-bar app only. `quoth run`, `setup`, `doctor`, `models` and `install`, `DaemonOptions`, the `quoth` symlink, SIGINT handling and the `AppLaunch.isApp` branches go.
- What the commands did is already in the app: model download and removal in Settings › Model, launch at login in Settings › General. `doctor`'s checks go: the app always skipped them, and the `fn` key advice is in the README.
- The flags for debugging become `QUOTH_*` environment variables (`DeveloperOptions`), read when the app starts from a terminal.
- `quoth-bench` stays, as a developer tool built against the modules.

## 2. Rationale

ADR-001 split behaviour into a library with extension points. It worked for the pipeline, but the wiring it was meant to retire came back in `Daemon.runLoop`: about 200 lines of closures connecting the controller, the Quote Card, the menu bar, `LastDictation`, `ModelSwitcher` and the hotkey monitor in both directions. `DictationController` keeps its state across six properties and changes it inside methods that also do the work, so its edge cases are documented in a comment rather than tested; it has no tests. The Quote Card became branches in it, against ADR-001's own rule. One module means nothing stops a view from reaching into Core Audio.

A state machine in a pure module makes the hardest logic in the app the easiest to test. One app model replaces the observer fan-out and most of the wiring. Modules make the layering a compile error rather than a convention. Dropping the command line removes the second startup path that every launch decision branches on.

Rejected:

- **A rewrite in one go.** The capture, hotkey and paste code carries fixes found on real hardware. Replacing it in one change would lose some of them silently. Each phase ships on its own with the tests passing.
- **The Composable Architecture or another framework.** The state machine is small enough to write directly, and a dependency would outlive its usefulness here.
- **Keeping the command line as a separate target.** Nobody using the App Store edition can reach it, and it keeps the launchd and terminal paths alive in the direct edition.

## 3. Behaviour to keep

These are the loop's edge cases today. Each becomes a `DictationMachine` test before the old controller is removed.

1. A press always tries to start capture, even while an earlier dictation is still transcribing. That transcription still delivers, and finishes while the new recording runs.
2. A press whose capture fails to start reports the error and changes no state; the gesture ignores the rest of that hold, so it can't lock or transcribe.
3. A release always stops capture. An empty capture, or one with no speech, transcribes nothing and reports no audio.
4. A hold shorter than 0.3 s, or a chord with another modifier, is discarded. A double tap within 0.4 s locks; a lock ended within 1 s is a triple tap and is discarded.
5. The press that ends a lock transcribes, with or without another modifier held.
6. A microphone change discards a push-to-talk recording on release, and ends a lock, keeping what came before the change.
7. Changing the hotkey cancels a held recording and transcribes a locked one.
8. Delivery: a password field at the start or at delivery discards the text, with nothing typed or copied. Focus that moved since the press puts the text on the clipboard. Without the paste grant, the text is copied and the pill says so.
9. While the Quote Card is open, every dictation goes into it. A lock opens the card when Settings says so, or when the build can't paste.
10. Live text: segments are typed in order, each with the end of the previous one as context and in the first segment's language. After a focus change, everything from then on goes to the clipboard; after a password field, nothing more is delivered. Text already typed stays, even when the recording is discarded.
11. "Scratch that" removes the last insertion only if it was within 120 s and the same app and field still have focus.
12. A model change applies from the next release; a transcription already running finishes with the model it started with.
13. Transcript text never reaches logs, observers or disk. The last dictation is kept in memory for 10 minutes and forgotten on quit or screen lock.

## 4. Migration

Each phase is one pull request, with the app working and the tests passing at its end. `release/1.0` takes App Review fixes meanwhile.

| Phase | Change |
|---|---|
| 0 | This ADR. |
| 1 | Create `QuothDomain`; move the pure types into it. `project.yml` builds the modules. |
| 2 | `DictationMachine` with the section 3 tests; `DictationSession` replaces `DictationController` and the orchestration in `LiveTranscription`. |
| 3a | The command line goes: one entry point, `QuothApp.main()`, for both editions. |
| 3b | `AppModel` and the composition root (`Assembly`); the menu bar reads the model; `Daemon` goes. |
| 4 | `QuothPlatform`: capture, the hotkey tap, text insertion, focus and permissions behind protocols; `Capabilities` replaces `Edition`. |
| 5 | `QuothSpeech`; `Paths` to Platform; `quoth-bench` against the modules. The settings and dictionary stores stay with the windows that edit them. |
| 6 | `architecture.md` rewritten for the new structure; ADR-001 marked superseded. |

All phases landed on 2026.10.03. The app module kept the name `QuothCore`, not `QuothApp` as first planned: the rename would touch every import, and `QuothApp` is the entry point's name.

## 5. When to revisit

- If transcription moves into its own process, `QuothSpeech` becomes the XPC boundary.
- If the state machine's effects need cancellation or ordering it can't express, consider structured concurrency inside `DictationSession` before reaching for a framework.
