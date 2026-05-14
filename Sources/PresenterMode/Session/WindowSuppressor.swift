import AppKit
import ApplicationServices

/// Watches application activations and window-creation events; whenever an app or window that
/// isn't in the allowlist tries to come forward, hides the app and re-raises the active target.
///
/// Strategy: we hide *non-target apps* rather than trying to lower individual windows, because
/// `NSRunningApplication.hide()` is reliable and atomic. Target apps stay visible; we re-raise
/// the active target window after each suppression to make sure it stays on top.
final class WindowSuppressor {
    private var allowedPIDs: Set<pid_t> = []
    private var activeTarget: WindowHandle?
    private var workspaceObservers: [NSObjectProtocol] = []
    private let workspace = NSWorkspace.shared

    func start(allowedPIDs: Set<pid_t>, activeTarget: WindowHandle) {
        self.allowedPIDs = allowedPIDs.union([ProcessInfo.processInfo.processIdentifier])
        self.activeTarget = activeTarget

        let center = workspace.notificationCenter

        let activateObserver = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handleActivation(note)
        }
        workspaceObservers.append(activateObserver)

        let launchObserver = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handleLaunch(note)
        }
        workspaceObservers.append(launchObserver)
    }

    func stop() {
        for observer in workspaceObservers {
            workspace.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
        allowedPIDs = []
        activeTarget = nil
    }

    func updateActiveTarget(_ handle: WindowHandle) {
        activeTarget = handle
    }

    private func handleActivation(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        if allowedPIDs.contains(app.processIdentifier) {
            // Allowed — but make sure the active staged target stays in front.
            reraiseActiveTarget()
            return
        }
        app.hide()
        reraiseActiveTarget()
    }

    private func handleLaunch(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        if allowedPIDs.contains(app.processIdentifier) { return }
        // New app launched mid-session — hide it immediately.
        app.hide()
        reraiseActiveTarget()
    }

    private func reraiseActiveTarget() {
        guard let target = activeTarget else { return }
        AccessibilityWindowController.raise(target)
    }
}
