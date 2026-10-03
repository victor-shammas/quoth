import Foundation
import QuothDomain
import QuothPlatform

/// Where both editions start (ADR-007): Quoth is the menu-bar app, with no
/// command line. `Sources/quoth/main.swift` and `AppStore/main.swift` call
/// this and nothing else.
public enum QuothApp {
    @MainActor
    public static func main() -> Never {
        AppLaunch.prepare()
        Log.info("Quoth \(AppBundle.version) starting")
        do {
            try Assembly.run()
            exit(0)
        } catch let failure as StartupFailure {
            // Exit 0, so launch at login doesn't reopen into the same dialog.
            Log.error(failure.message)
            AppLaunch.presentStartupFailure(failure)
            exit(0)
        } catch {
            Log.error("\(error)")
            exit(1)
        }
    }
}
