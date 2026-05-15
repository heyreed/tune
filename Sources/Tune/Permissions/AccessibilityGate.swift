import AppKit
import ApplicationServices

/// Checks whether Tune has Accessibility permission and prompts the user if not.
///
/// macOS does not let an app grant itself this permission. We can only nudge the system to show
/// the "Allow this app to control your computer" prompt and open System Settings → Privacy &
/// Security → Accessibility for the user.
enum AccessibilityGate {
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    static func requestIfNeeded() {
        // Prompt option: shows the system permission dialog the first time.
        let options: NSDictionary = [
            "AXTrustedCheckOptionPrompt" as NSString: true
        ]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        if !trusted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                presentExplainer()
            }
        }
    }

    private static func presentExplainer() {
        let alert = NSAlert()
        alert.messageText = "Tune needs Accessibility access"
        alert.informativeText = """
        Tune resizes and re-orders the windows you choose to share so your screen is clean for the \
        moment. macOS requires Accessibility permission for any app that controls other windows.

        Open System Settings → Privacy & Security → Accessibility and enable Tune. You may need to \
        quit and reopen the app afterward.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
