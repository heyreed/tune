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

        // Ctrl+Opt+T toggles Tune: if a session is running, end it; otherwise toggle the
        // launcher. Ctrl+Opt is the same modifier family the cycle hotkeys use — it's chosen
        // to avoid collisions with browser, Figma, Slack, Zoom, and macOS shortcuts.
        hotkeyManager.register(keyCode: HotkeyManager.kVK_ANSI_T, modifiers: [.control, .option]) { [weak self] in
            guard let self else { return }
            if self.sessionController.isActive {
                self.sessionController.endSessionIfActive()
            } else {
                self.launcherController.toggle()
            }
        }

        // Mid-session cycling. Ctrl+Opt+← / Ctrl+Opt+→ step through staged windows.
        hotkeyManager.register(keyCode: HotkeyManager.kVK_LeftArrow, modifiers: [.control, .option]) { [weak self] in
            self?.sessionController.cyclePrev()
        }
        hotkeyManager.register(keyCode: HotkeyManager.kVK_RightArrow, modifiers: [.control, .option]) { [weak self] in
            self?.sessionController.cycleNext()
        }

        AccessibilityGate.requestIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        sessionController?.endSessionIfActive()
    }
}
