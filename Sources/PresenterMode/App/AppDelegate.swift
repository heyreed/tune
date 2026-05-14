import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController!
    private var hotkeyManager: HotkeyManager!
    private var sessionController: SessionController!
    private var launcherController: LauncherWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        sessionController = SessionController()
        launcherController = LauncherWindowController(sessionController: sessionController)
        statusItemController = StatusItemController(
            sessionController: sessionController,
            launcherController: launcherController
        )

        hotkeyManager = HotkeyManager()
        hotkeyManager.register(keyCode: HotkeyManager.kVK_ANSI_P, modifiers: [.control, .shift]) { [weak self] in
            self?.launcherController.toggle()
        }
        // Cycle between staged windows mid-session. Ctrl+Opt+Tab is chosen because it doesn't
        // collide with Firefox/Chrome/Figma/Slack/Zoom/macOS shortcuts.
        hotkeyManager.register(keyCode: HotkeyManager.kVK_Tab, modifiers: [.control, .option]) { [weak self] in
            self?.sessionController.cycleNext()
        }

        AccessibilityGate.requestIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        sessionController?.endSessionIfActive()
    }
}
