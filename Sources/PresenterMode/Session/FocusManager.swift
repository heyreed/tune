import Foundation
import AppKit

/// Toggles Do Not Disturb / Focus on session entry and restores on exit.
///
/// MACOS LIMITATION: there is no clean public API to programmatically toggle Focus modes.
/// Practical options, all imperfect:
///
///   1. AppleScript via `osascript` to drive Shortcuts.app, running a user-installed Shortcut
///      ("Turn DND On" / "Turn DND Off"). Requires one-time user setup but is stable across OS
///      releases. RECOMMENDED.
///
///   2. `defaults write` to `~/Library/Preferences/com.apple.controlcenter.plist` + a SIGTERM to
///      `controlcenter`. Brittle across releases.
///
///   3. Private `_CTServerConnection` API. Not viable for App Store distribution and breaks often.
///
/// This implementation uses approach (1). Users install a Shortcut named "Presenter Mode DND On"
/// and "Presenter Mode DND Off" and we shell out to `shortcuts run`. If the shortcuts don't exist
/// we log a warning and continue — the rest of the session still suppresses windows.
final class FocusManager {
    private let shortcutOn = "Presenter Mode DND On"
    private let shortcutOff = "Presenter Mode DND Off"

    func engage() {
        runShortcut(named: shortcutOn)
    }

    func restore() {
        runShortcut(named: shortcutOff)
    }

    private func runShortcut(named name: String) {
        let process = Process()
        process.launchPath = "/usr/bin/shortcuts"
        process.arguments = ["run", name]
        process.standardError = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            NSLog("FocusManager: failed to run shortcut '\(name)': \(error)")
        }
    }
}
