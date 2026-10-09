<p align="center">
  <img src="docs/assets/quoth-icon.png" width="128" alt="Quoth">
</p>

# Quoth

**Local voice transcription on your Mac.**

Hold `fn`, speak, release, and your words appear at the cursor. For longer dictation, double-tap `fn` to lock recording on, and tap again when you're done. Everything runs on-device.

Quoth is based on [Parrot](https://github.com/humanitas-labs/parrot) by Humanitas Labs (MIT), with a hands-free lock added.

Website: [victorshammas.com/quoth](https://victorshammas.com/quoth/).

## 1. Install

Quoth comes in two editions from this one codebase ([ADR-006](docs/decisions/006-two-editions.md)):

- **Mac App Store**, $1.99, sandboxed. Pastes at the cursor once you allow it; otherwise each dictation is copied for ⌘V.
- **Free and open source**, this repository. It also reads the text field it types into, for exact spacing and to keep out of password fields, and updates itself. [Download the latest release](https://github.com/victor-shammas/quoth/releases/latest/download/Quoth.dmg) (notarized), or build it from source (section 6).

Requires macOS 14+ on Apple silicon. Open Quoth and allow it when macOS asks for the microphone and Accessibility (the App Store edition needs only the microphone: its hotkey is a key combination, ⌥Space by default). The first start downloads the speech model (about 150 MB).

## 2. Usage

1. Click into any text field.
2. **Hold `fn` and speak.** A small pill at the bottom of the screen shows the mic is live. On a keyboard where `fn` does nothing (Logitech and most third-party keyboards), choose another key under **Hotkey** in **Settings**: left or right Option, Command, Control, or Shift.
3. Release. The transcript is pasted at the cursor and your clipboard is restored.

**Hands-free:** double-tap the hotkey to lock recording on. The pill shows a lock. Tap the hotkey again to stop and transcribe. A lock never throws your words away: a shortcut typed on the hotkey, changing the hotkey, or switching microphones ends it and transcribes what you said. While locked, text appears at the cursor at each pause in your speech, so a long dictation builds up as you talk and finishes almost at once. If you click into another window mid-dictation, the pill says so and the rest goes to the clipboard instead. A locked recording stops by itself after 10 minutes. Turn these off with **Double-tap to lock** and **Live text while locked** in Settings.

If the hotkey is `fn`, set **System Settings → Keyboard → Dictation → Shortcut** to Off, since macOS also uses a double press of `fn` to start its own dictation.

**Quote Card:** choose **Hands-free goes to › Quote Card** in Settings, or **New Quote Card** in the menu, and dictation streams into a small floating card instead, where you can edit it before **⌘↩** inserts it where you were. While the card is open, every dictation goes into it. The App Store edition uses it whenever it can't paste.

**Voice commands** (English): "new paragraph", "new line", "bullet point", "comma", "question mark", "quote … unquote", and "scratch that" to remove what was just typed. Settings › General lists them all. If Quoth misspells a word, **Fix Last Dictation…** in **Settings › Dictionary** teaches it, and the same pane lists your words.

**Music on headphones:** while AirPods or other Bluetooth headphones are playing, Quoth listens through the Mac's own microphone, so the music stays at full quality instead of dropping to call quality for the length of the dictation and a few seconds after. The pill shows a small laptop when it does. With nothing playing, or a MacBook's lid closed, Quoth uses the headphones' microphone, so you can still dictate away from the Mac; pausing the music does the same. Turn this off with **Use the Mac's microphone while headphones play** in Settings.

**Fade out sound while dictating** in Settings lowers the Mac's volume while the microphone is on and brings it back after. It leaves a Bluetooth headset such as AirPods alone while its own microphone records: opening that microphone switches the headset to call quality faster than a fade can hide.

Choose **Open at login** in **Settings** to start Quoth with your Mac. A tap shorter than 0.3 s, or a hold with another modifier, is ignored, so shortcuts on the hotkey still work. If `fn` changes the input source or shows emoji, set **System Settings → Keyboard → Press 🌐 key to** to **Do Nothing**.

To dictate in another language, choose a multilingual model in Settings (⌘, from the menu), then either one Language or Automatic. Automatic detects which of the languages under **Languages** each dictation is in, and never picks one you haven't listed. The list starts as your Mac's languages.

## 3. Dictionary

Add your names and technical terms to `~/.config/quoth/dictionary`, a plain-text table of each word and what the model writes instead, and Quoth spells them your way. **Open Dictionary File** in Settings opens it. Edits apply on the next dictation. See [docs/dictionary.md](docs/dictionary.md).

## 4. Settings and developer options

Everything is in **Settings**: the hotkey, models (download, switch and delete them under **Model**), languages, the dictionary, and launch at login. Quoth has no command line ([ADR-007](docs/decisions/007-modules-and-app-model.md)).

For working on Quoth, start the app with any of these through `open`, and follow its log in `~/Library/Logs/quoth/quoth.err.log`:

| Variable | What it does |
|---|---|
| `QUOTH_DEBUG_HOTKEY=1` | Log each modifier change the hotkey tap sees |
| `QUOTH_DUMP_WAV=1` | Write each capture to `~/Library/Caches/quoth/last-capture.wav` |
| `QUOTH_INJECT_MODE=type-unicode` | Type instead of paste (leaves the clipboard alone) |

```sh
open -a Quoth --env QUOTH_DUMP_WAV=1
tail -f ~/Library/Logs/quoth/quoth.err.log
```

Quit a running Quoth first. Started through `open`, macOS checks Quoth's own microphone and Accessibility grants; running the binary from a terminal checks the terminal's instead, which usually has none.

## 5. How it works

WhisperKit runs Whisper on the Apple Neural Engine via CoreML, a Core Audio input unit captures the mic, a CGEventTap watches the hotkey, and a synthesized ⌘V pastes the result. Nothing leaves your Mac, and logs never contain what you said. See [docs/architecture.md](docs/architecture.md).

## 6. Build from source

```sh
swift build -c release && swift test
scripts/dev-install.sh      # build, sign and install Quoth.app
```

### App Store edition

The Mac App Store build is generated from `project.yml` and compiles the same sources, sandboxed (see [ADR-006](docs/decisions/006-two-editions.md)):

```sh
xcodegen && open Quoth.xcodeproj
```

## 7. License

[MIT](LICENSE). Based on Parrot, copyright © 2026 Humanitas Labs.
