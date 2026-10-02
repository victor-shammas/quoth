# ADR-002 :: Config in ~/.config, data in Application Support

Last updated: `2026.10.02`

> What the user writes lives in `~/.config/quoth`: `settings.json` (plain JSON) and `dictionary` (a plain-text table), both hand-editable and fit for dotfiles. What Quoth downloads lives in `~/Library/Application Support/quoth`: models. Every persistent preference goes through one `Codable` `Settings` value and `SettingsStore`.

## 1. Decision

- **Config in `~/.config/quoth/`.** `settings.json` holds preferences, and `dictionary` holds the user's words and what the model writes instead (see `docs/dictionary.md`); Settings › Dictionary edits the same file. `$XDG_CONFIG_HOME/quoth/` is used instead when that variable is set to an absolute path.
- **Data in `~/Library/Application Support/quoth/`.** `models/` holds downloaded weights. Nothing there is meant to be edited or synced.
- **JSON.** No extra dependency, and the same `Codable` types read and write it.
- **One `Codable` value.** `Settings` aggregates one struct per feature (`HotkeySettings`, `DictionarySettings`, `LanguageSettings`, `ModelSettings`, `OnboardingSettings`). A missing key takes its default, and unknown keys are ignored.
- **`SettingsStore` is the only writer.** Writes are atomic. It watches the directory so hand edits apply without a restart; a file that fails to parse keeps the last good settings and logs one line.
- **CLI flags override one foreground run and are never persisted.** Launch at login carries no arguments.

## 2. Rationale

Quoth is a menu-bar utility driven from the command line, used mostly by developers. Its config is small and meant to be hand-edited, and the dictionary is the user's own work: the thing worth versioning in a dotfiles repo and carrying between Macs. `~/.config` is where developer tools on macOS keep that kind of file (Zed, Ghostty, Karabiner).

Model weights (up to 1.6 GB each) are the opposite: downloaded, machine-specific, and never edited. They belong in Application Support (see ADR-004). Splitting by kind is not two sources of truth; each file has one home. Zed makes the same split.

Before this, configuration was scattered: the hotkey was hard-coded, the README advertised a `--hotkey` flag that did not exist, and the LaunchAgent's `ProgramArguments` froze whatever flags were passed at install, so a setting could silently disappear after a reboot. A file Quoth owns removes that class of bug.

Rejected:
- Everything in Application Support: native for GUI apps, but a long path to hand-edit and awkward for dotfiles, which is where the dictionary most wants to be.
- Reading `~/.config` when it exists and Application Support otherwise: two possible homes for one file, so the settings window would have to guess where to write.
- `UserDefaults`: opaque, hard to hand-edit or back up, and the command-line binary and an app bundle can see different defaults domains.
- TOML: nicer to hand-edit, but adds a dependency for a file that the settings window also writes.
- Per-feature config files: make atomic changes and file watching harder for no gain.

## 3. Design Implications

- Rule: no `UserDefaults`, no plist flags, no per-feature config files. Every location comes from `Paths`.
- The settings window is a view over `Settings`; it holds no state of its own.
- A user who symlinks `~/.config/quoth` (or the files in it) from a dotfiles repo must keep working. `Paths.prepareDirectory` refuses symlinks, which is right for logs and caches but wrong here, so config access resolves the symlink and then checks that the target is owned by the user. Atomic writes replace the file at the resolved path, and file watching follows it.
- Uninstall leaves `~/.config/quoth` alone. It is user content.

## 4. When to Revisit

- If Quoth ships through the Mac App Store, the sandbox cannot write `~/.config`, and config moves into the container.
- If the settings window becomes the only way people change settings and nobody hand-edits them, the case for `~/.config` weakens.

In the App Store edition the home folder is the app's sandbox container, so these paths resolve inside it and the files can't be kept in dotfiles; the Settings window edits everything there instead (ADR-006).
