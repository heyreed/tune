import AppKit
import ApplicationServices

/// Reads, writes, and raises window position/size via the Accessibility API.
///
/// macOS does not let you address a window by `CGWindowID` directly through AX — you have to walk
/// the AX tree of the owning application and match windows. We do that matching by title + position
/// because AX doesn't expose CGWindowID. This is the standard technique used by Magnet, Rectangle,
/// etc.
struct WindowHandle {
    let cgID: CGWindowID
    let ownerPID: pid_t
    let axElement: AXUIElement
    let originalFrame: CGRect
}

enum AccessibilityWindowController {

    /// Resolves a list of DiscoveredWindows to live AXUIElements, ensuring each AX window is
    /// assigned to at most one selection. Windows that can't be matched are dropped from the
    /// result (the caller already tolerates a short result).
    ///
    /// We resolve per-app rather than per-window because two selections from the same app would
    /// otherwise be matched independently and could both claim the same AXUIElement — the symptom
    /// being "I selected two Firefox windows but only one got repositioned."
    ///
    /// Per-app strategy: fetch the app's AX windows once, then for each selection greedily pick
    /// the unclaimed AX window with the smallest combined origin+size delta from the selection's
    /// CGWindow bounds. Greedy in selection order is good enough — the bounds typically separate
    /// cleanly, and any tie-break is no worse than the old single-window heuristic.
    static func resolveBatch(_ windows: [DiscoveredWindow]) -> [WindowHandle] {
        let groups = Dictionary(grouping: windows.enumerated().map { (index: $0, window: $1) }) {
            $0.window.ownerPID
        }

        var resultByOriginalIndex: [Int: WindowHandle] = [:]

        for (pid, indexed) in groups {
            let app = AXUIElementCreateApplication(pid)
            var rawWindows: AnyObject?
            let status = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &rawWindows)
            guard status == .success, let axWindows = rawWindows as? [AXUIElement], !axWindows.isEmpty else {
                NSLog("AccessibilityWindowController: no AX windows for pid \(pid) (status=\(status.rawValue))")
                continue
            }

            var available: [(element: AXUIElement, frame: CGRect)] = axWindows.compactMap { el in
                guard let f = frame(of: el) else { return nil }
                return (el, f)
            }

            for entry in indexed {
                guard !available.isEmpty else {
                    NSLog("AccessibilityWindowController: ran out of AX windows for pid \(pid) — selection \(entry.window.id) unmatched")
                    break
                }
                let target = entry.window.bounds
                var bestIdx = 0
                var bestDist = CGFloat.greatestFiniteMagnitude
                for i in available.indices {
                    let f = available[i].frame
                    let d = abs(f.minX - target.minX) + abs(f.minY - target.minY)
                          + abs(f.width - target.width) + abs(f.height - target.height)
                    if d < bestDist {
                        bestDist = d
                        bestIdx = i
                    }
                }
                let chosen = available.remove(at: bestIdx)
                resultByOriginalIndex[entry.index] = WindowHandle(
                    cgID: entry.window.id,
                    ownerPID: entry.window.ownerPID,
                    axElement: chosen.element,
                    originalFrame: chosen.frame
                )
            }
        }

        return windows.indices.compactMap { resultByOriginalIndex[$0] }
    }

    static func frame(of axWindow: AXUIElement) -> CGRect? {
        var posValue: AnyObject?
        var sizeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeValue) == .success else {
            return nil
        }
        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: position, size: size)
    }

    /// Sets a window's frame, working around the two most common AX quirks:
    ///
    /// 1. **Position/size anchoring.** Many apps (Firefox especially) anchor on a corner when
    ///    you change size, so setting position THEN size can shift the window away from the
    ///    requested origin. Workaround: set size → position → size → position. The duplicate
    ///    writes are the canonical idiom from Rectangle/Magnet.
    ///
    /// 2. **"Fullscreen" / "zoomed" silent refusal.** If the window is in the AX-fullscreen
    ///    state, every position/size write is silently dropped. We detect this by reading the
    ///    frame back after writing — if it doesn't match the target, try toggling
    ///    `AXFullScreen` off and retry once. The state can be set by the green button, by the
    ///    Window menu's "Fill" / "Zoom" items, or by leftover state from a prior session.
    @discardableResult
    static func setFrame(_ frame: CGRect, of axWindow: AXUIElement) -> Bool {
        applyFrame(frame, to: axWindow)
        if frameMatches(frame, on: axWindow) { return true }

        // Frame didn't take. The window is likely AX-fullscreen. Try to exit, give it a beat,
        // and retry. This is synchronous-sleep on purpose — we're already inside a one-shot
        // session-start path and need the window in the right state before continuing.
        if tryExitFullscreen(of: axWindow) {
            Thread.sleep(forTimeInterval: 0.6)  // animation duration ~0.5s
            applyFrame(frame, to: axWindow)
            if frameMatches(frame, on: axWindow) { return true }
        }

        NSLog("AccessibilityWindowController: setFrame failed; final frame does not match target")
        return false
    }

    private static func applyFrame(_ frame: CGRect, to axWindow: AXUIElement) {
        var position = frame.origin
        var size = frame.size
        guard
            let posValue = AXValueCreate(.cgPoint, &position),
            let sizeValue = AXValueCreate(.cgSize, &size)
        else { return }
        // Double-set idiom: each write may shift the other due to corner anchoring; two passes
        // converge in practice.
        AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, posValue)
        AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, posValue)
    }

    private static func frameMatches(_ target: CGRect, on axWindow: AXUIElement, tolerance: CGFloat = 4) -> Bool {
        guard let actual = frame(of: axWindow) else { return false }
        return abs(actual.minX - target.minX) <= tolerance
            && abs(actual.minY - target.minY) <= tolerance
            && abs(actual.width - target.width) <= tolerance
            && abs(actual.height - target.height) <= tolerance
    }

    /// Writes `AXFullScreen = false` to the window. Returns true if the write succeeded.
    ///
    /// `AXFullScreen` is a documented AX attribute but not exported as a Swift `kAX*` constant;
    /// it's addressed by string. Writing false exits both native fullscreen and the legacy
    /// green-button "zoom" state on apps that map that to fullscreen.
    private static func tryExitFullscreen(of axWindow: AXUIElement) -> Bool {
        let attr = "AXFullScreen" as CFString
        let status = AXUIElementSetAttributeValue(axWindow, attr, kCFBooleanFalse)
        if status == .success { return true }
        NSLog("AccessibilityWindowController: AXFullScreen toggle returned status=\(status.rawValue)")
        return false
    }

    /// All AX windows of `pid` that are NOT in `excluding`. Used to find "sibling" windows of a
    /// target app — e.g. the second Firefox window when only the first is a target — so we can
    /// stash them out of the way for the session.
    static func otherWindows(forApp pid: pid_t, excluding: [AXUIElement]) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        var rawWindows: AnyObject?
        let status = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &rawWindows)
        guard status == .success, let axWindows = rawWindows as? [AXUIElement] else { return [] }
        return axWindows.filter { candidate in
            !excluding.contains { CFEqual($0, candidate) }
        }
    }

    static func isMinimized(_ axWindow: AXUIElement) -> Bool {
        var value: AnyObject?
        let status = AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &value)
        guard status == .success, let bool = value as? Bool else { return false }
        return bool
    }

    static func setMinimized(_ minimized: Bool, of axWindow: AXUIElement) {
        AXUIElementSetAttributeValue(
            axWindow,
            kAXMinimizedAttribute as CFString,
            (minimized ? kCFBooleanTrue : kCFBooleanFalse) as CFTypeRef
        )
    }

    static func raise(_ handle: WindowHandle) {
        AXUIElementPerformAction(handle.axElement, kAXRaiseAction as CFString)
        if let app = NSRunningApplication(processIdentifier: handle.ownerPID) {
            app.activate(options: [])
        }
    }
}
