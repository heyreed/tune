import AppKit
import CoreGraphics

/// Checks whether Tune has Screen Recording permission and prompts the user if not.
///
/// We don't actually capture the screen — we only need this so `CGWindowListCopyWindowInfo`
/// returns window titles (the `kCGWindowName` field). Without it, every window comes back with
/// an empty title and the picker shows rows like "Slack" "Slack" "Slack" that the user can't
/// tell apart.
///
/// Like Accessibility, this is a permission only the user can grant. We can trigger the
/// system prompt once via `CGRequestScreenCaptureAccess()`; after that, denial sticks until
/// the user toggles the entry in System Settings → Privacy & Security → Screen Recording and
/// relaunches Tune.
enum ScreenRecordingGate {
    static func isTrusted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Triggers the system prompt the first time it's called per install. Subsequent calls
    /// after a denial are no-ops as far as the system prompt is concerned — at that point
    /// the user has to grant via System Settings.
    static func requestIfNeeded() {
        if CGPreflightScreenCaptureAccess() { return }
        // Returns immediately; the system shows its own prompt asynchronously. If the user
        // grants it from here, the new state still doesn't apply to the current process —
        // they have to relaunch. That's a macOS quirk, not something we can work around.
        _ = CGRequestScreenCaptureAccess()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            presentExplainer()
        }
    }

    private static func presentExplainer() {
        let alert = NSAlert()
        alert.messageText = "Tune needs Screen Recording access"
        alert.informativeText = """
        Tune doesn't record your screen. macOS gates window titles behind this permission, so \
        without it the picker can't tell two Slack windows apart.

        Open System Settings → Privacy & Security → Screen Recording, enable Tune, then quit \
        and reopen the app to pick up the change.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
