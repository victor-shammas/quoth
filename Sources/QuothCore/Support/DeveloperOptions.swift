import Foundation
import QuothDomain
import QuothPlatform

/// Switches for working on Quoth, read once at launch from the environment.
/// Never persisted, never shown in Settings. Run the app with them from a
/// terminal:
///
///     QUOTH_DUMP_WAV=1 /Applications/Quoth.app/Contents/MacOS/quoth
///
/// - `QUOTH_DEBUG_HOTKEY=1`: log each modifier change the hotkey tap sees.
/// - `QUOTH_DUMP_WAV=1`: write each capture to `Paths.dumpWav`.
/// - `QUOTH_INJECT_MODE=type-unicode`: type transcripts instead of pasting.
struct DeveloperOptions {
    var debugHotkey = false
    var dumpWav = false
    var injectMode: InjectMode = .paste

    /// The options in `environment`; unknown values keep the default.
    static func from(_ environment: [String: String]) -> DeveloperOptions {
        var options = DeveloperOptions()
        options.debugHotkey = environment["QUOTH_DEBUG_HOTKEY"] == "1"
        options.dumpWav = environment["QUOTH_DUMP_WAV"] == "1"
        if let raw = environment["QUOTH_INJECT_MODE"] {
            if let mode = InjectMode(rawValue: raw) { options.injectMode = mode } else { Log.warning("QUOTH_INJECT_MODE: unknown mode \"\(raw)\"") }
        }
        return options
    }

    static let current = from(ProcessInfo.processInfo.environment)
}
