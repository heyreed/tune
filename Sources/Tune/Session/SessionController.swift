import AppKit
import Combine

struct SessionConfiguration {
    var targetWindows: [DiscoveredWindow]
    var displayUUID: String?           // nil = main display
    var background: BackgroundPreset
}

/// The orchestrator. Owns the lifecycle of a Tune session: enter, switch, exit.
///
/// Public state is `isActive` and `activeTargetIndex`. Everything else is internal.
final class SessionController: ObservableObject {
    @Published private(set) var isActive: Bool = false
    @Published private(set) var activeTargetIndex: Int = 0

    private struct StashedWindow {
        let axElement: AXUIElement
        let wasMinimized: Bool   // if true at session start, leave it minimized on exit
    }

    private var configuration: SessionConfiguration?
    private var resolvedTargets: [WindowHandle] = []
    private var allowedPIDs: Set<pid_t> = []
    private var stashedWindows: [StashedWindow] = []
    private var overlay: StagingOverlay?
    private let suppressor = WindowSuppressor()
    private let focusManager = FocusManager()
    private var escMonitor: Any?
    private var escDownStartedAt: Date?
    private let escHoldThreshold: TimeInterval = 1.0
    private var watchdogTimer: Timer?

    /// 80% of the screen, centered.
    private let stageInsetFraction: CGFloat = 0.10

    func start(_ config: SessionConfiguration) {
        guard !isActive else { return }
        guard !config.targetWindows.isEmpty else { return }

        // Gate 1: Accessibility permission. Without it, every AX call silently fails.
        guard AccessibilityGate.isTrusted() else {
            showAlert(
                title: "Accessibility permission required",
                message: "Tune can't resize or raise your windows because Accessibility access has not been granted (or was revoked when the app was reinstalled).\n\nOpen System Settings → Privacy & Security → Accessibility, remove Tune if it's listed, re-add it, and make sure the toggle is on. Then quit and relaunch the app.",
                openSettings: true
            )
            return
        }

        let screen = resolveScreen(uuid: config.displayUUID)

        // Resolve AX handles for each target. Skip any we can't resolve.
        resolvedTargets = AccessibilityWindowController.resolveBatch(config.targetWindows)
        guard !resolvedTargets.isEmpty else {
            showAlert(
                title: "Couldn't find your selected windows",
                message: "The app tried to look up your selected windows through the Accessibility API and got nothing back. Common causes:\n\n• The windows were closed or minimized between picking them and pressing Start.\n• Accessibility permission was granted but the app needs to be relaunched to pick it up.\n\nClose this dialog, reopen Tune, and try again.",
                openSettings: false
            )
            return
        }
        if resolvedTargets.count < config.targetWindows.count {
            NSLog("SessionController: resolved \(resolvedTargets.count) of \(config.targetWindows.count) selected windows.")
        }

        // Stage every target to the same frame so switching feels seamless.
        let stageFrame = stagedFrame(in: screen)
        for handle in resolvedTargets {
            AccessibilityWindowController.setFrame(stageFrame, of: handle.axElement)
        }

        overlay = StagingOverlay(screen: screen)
        overlay?.show(background: config.background)

        allowedPIDs = Set(resolvedTargets.map { $0.ownerPID })

        // Stash sibling windows of allowed apps (e.g. the second Firefox window when only the
        // first is a target). Without this, hideAllNonTargetApps leaves the whole app visible
        // because we allowlist by PID, not by AX element.
        stashOtherWindowsOfAllowedApps()

        hideAllNonTargetApps()
        suppressor.start(allowedPIDs: allowedPIDs, activeTarget: resolvedTargets[0])
        focusManager.engage()

        configuration = config
        activeTargetIndex = 0
        isActive = true

        AccessibilityWindowController.raise(resolvedTargets[0])
        installEscMonitor()
        startWatchdog()
    }

    /// For each allowed app, minimize any AX windows that aren't targets. Records each one's
    /// prior minimized state so `endSessionIfActive` can restore them correctly. Idempotent:
    /// safe to call again from the watchdog to catch new windows opened mid-session.
    private func stashOtherWindowsOfAllowedApps() {
        let targetElements = resolvedTargets.map { $0.axElement }
        for pid in allowedPIDs {
            let others = AccessibilityWindowController.otherWindows(forApp: pid, excluding: targetElements)
            for other in others {
                if stashedWindows.contains(where: { CFEqual($0.axElement, other) }) { continue }
                let wasMin = AccessibilityWindowController.isMinimized(other)
                if !wasMin {
                    AccessibilityWindowController.setMinimized(true, of: other)
                }
                stashedWindows.append(StashedWindow(axElement: other, wasMinimized: wasMin))
            }
        }
    }

    /// Hides every running app except our own and the target apps. Drops the `.regular` filter
    /// from the original implementation because some apps (Electron-based ones, including the
    /// Anthropic desktop app) use non-`.regular` activation policies and were leaking through.
    /// Skips `.prohibited` apps which are background daemons that can't be hidden anyway.
    private func hideAllNonTargetApps() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications {
            if allowedPIDs.contains(app.processIdentifier) { continue }
            if app.processIdentifier == ownPID { continue }
            if app.activationPolicy == .prohibited { continue }
            let ok = app.hide()
            if !ok {
                NSLog("SessionController: app.hide() refused for \(app.localizedName ?? "unknown") (pid \(app.processIdentifier))")
            }
        }
    }

    func cycleNext() {
        guard isActive, resolvedTargets.count > 1 else { return }
        activeTargetIndex = (activeTargetIndex + 1) % resolvedTargets.count
        let next = resolvedTargets[activeTargetIndex]
        suppressor.updateActiveTarget(next)
        AccessibilityWindowController.raise(next)
    }

    func cyclePrev() {
        guard isActive, resolvedTargets.count > 1 else { return }
        let count = resolvedTargets.count
        activeTargetIndex = (activeTargetIndex - 1 + count) % count
        let prev = resolvedTargets[activeTargetIndex]
        suppressor.updateActiveTarget(prev)
        AccessibilityWindowController.raise(prev)
    }

    func endSessionIfActive() {
        guard isActive else { return }
        stopWatchdog()
        suppressor.stop()
        focusManager.restore()
        overlay?.hide()
        overlay = nil
        removeEscMonitor()

        // Restore every staged window to its original frame.
        for handle in resolvedTargets {
            AccessibilityWindowController.setFrame(handle.originalFrame, of: handle.axElement)
        }

        // Un-minimize the sibling windows we stashed at session start, leaving alone the ones
        // that were already minimized when we found them.
        for stashed in stashedWindows where !stashed.wasMinimized {
            AccessibilityWindowController.setMinimized(false, of: stashed.axElement)
        }
        stashedWindows = []

        resolvedTargets = []
        allowedPIDs = []
        configuration = nil
        isActive = false
        activeTargetIndex = 0
    }

    // MARK: - Helpers

    private func resolveScreen(uuid: String?) -> NSScreen {
        guard let uuid else { return NSScreen.main ?? NSScreen.screens[0] }
        let match = NSScreen.screens.first { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue == uuid
        }
        return match ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func stagedFrame(in screen: NSScreen) -> CGRect {
        let frame = screen.frame
        let inset = CGSize(
            width: frame.width * stageInsetFraction,
            height: frame.height * stageInsetFraction
        )
        return CGRect(
            x: frame.minX + inset.width,
            y: frame.minY + inset.height,
            width: frame.width - inset.width * 2,
            height: frame.height - inset.height * 2
        )
    }

    // MARK: - Esc hold-to-exit

    private func installEscMonitor() {
        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return }
            if event.keyCode != 53 { return } // Esc
            if event.type == .keyDown, self.escDownStartedAt == nil {
                self.escDownStartedAt = Date()
                DispatchQueue.main.asyncAfter(deadline: .now() + self.escHoldThreshold) { [weak self] in
                    guard let self,
                          let started = self.escDownStartedAt,
                          Date().timeIntervalSince(started) >= self.escHoldThreshold else { return }
                    self.endSessionIfActive()
                }
            } else if event.type == .keyUp {
                self.escDownStartedAt = nil
            }
        }
    }

    private func removeEscMonitor() {
        if let m = escMonitor { NSEvent.removeMonitor(m); escMonitor = nil }
        escDownStartedAt = nil
    }

    // MARK: - Watchdog
    //
    // The activation observer in WindowSuppressor reacts to apps coming forward, but doesn't help
    // with apps that were running and visible at start (handled by initial hide) or that re-show
    // themselves without triggering an activation event (system events, certain Electron apps).
    // A 1s timer sweeps and re-hides anything that's slipped through, and also re-raises the
    // active target in case it got buried.

    private func startWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.watchdogTick()
        }
    }

    private func stopWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
    }

    private func watchdogTick() {
        guard isActive else { return }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications {
            if app.isHidden { continue }
            if allowedPIDs.contains(app.processIdentifier) { continue }
            if app.processIdentifier == ownPID { continue }
            if app.activationPolicy == .prohibited { continue }
            app.hide()
        }
        // Catch new sibling windows (e.g. user opened a third Firefox window mid-session)
        // and re-minimize any stashed window that got un-minimized.
        stashOtherWindowsOfAllowedApps()
        for stashed in stashedWindows {
            if !AccessibilityWindowController.isMinimized(stashed.axElement) {
                AccessibilityWindowController.setMinimized(true, of: stashed.axElement)
            }
        }
        // Re-raise active target in case it lost the front position.
        if resolvedTargets.indices.contains(activeTargetIndex) {
            AccessibilityWindowController.raise(resolvedTargets[activeTargetIndex])
        }
    }

    private func showAlert(title: String, message: String, openSettings: Bool) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .warning
            if openSettings {
                alert.addButton(withTitle: "Open System Settings")
                alert.addButton(withTitle: "OK")
            } else {
                alert.addButton(withTitle: "OK")
            }
            let response = alert.runModal()
            if openSettings, response == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
