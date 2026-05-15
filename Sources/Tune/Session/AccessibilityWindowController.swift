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

    /// Resolves a DiscoveredWindow to a live AXUIElement we can manipulate.
    /// Returns nil if the window has gone away or AX permission is missing.
    ///
    /// Resolution strategy (tries each in order until one matches):
    ///   1. If the app has only one AX window, return it.
    ///   2. Closest match by bounding-box size (within 20px tolerance).
    ///   3. Closest match by frame distance (smallest combined size + origin delta).
    static func resolve(_ window: DiscoveredWindow) -> WindowHandle? {
        let app = AXUIElementCreateApplication(window.ownerPID)
        var rawWindows: AnyObject?
        let status = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &rawWindows)
        guard status == .success, let axWindows = rawWindows as? [AXUIElement], !axWindows.isEmpty else {
            NSLog("AccessibilityWindowController: no AX windows for pid \(window.ownerPID) (status=\(status.rawValue))")
            return nil
        }

        let target = window.bounds

        // 1. Only one window? Use it.
        if axWindows.count == 1, let frame = frame(of: axWindows[0]) {
            return WindowHandle(cgID: window.id, ownerPID: window.ownerPID,
                                axElement: axWindows[0], originalFrame: frame)
        }

        // 2. Match on both position AND size, within 20px tolerance. Position alone disambiguates
        //    multiple windows of the same size, which size-only matching couldn't handle.
        for axWindow in axWindows {
            guard let frame = frame(of: axWindow) else { continue }
            if abs(frame.minX - target.minX) < 20 &&
               abs(frame.minY - target.minY) < 20 &&
               abs(frame.width - target.width) < 20 &&
               abs(frame.height - target.height) < 20 {
                return WindowHandle(cgID: window.id, ownerPID: window.ownerPID,
                                    axElement: axWindow, originalFrame: frame)
            }
        }

        // 3. Closest by combined geometric distance.
        var best: (axWindow: AXUIElement, frame: CGRect, distance: CGFloat)?
        for axWindow in axWindows {
            guard let frame = frame(of: axWindow) else { continue }
            let d = abs(frame.minX - target.minX) + abs(frame.minY - target.minY)
                  + abs(frame.width - target.width) + abs(frame.height - target.height)
            if best == nil || d < best!.distance {
                best = (axWindow, frame, d)
            }
        }
        if let best {
            NSLog("AccessibilityWindowController: fell back to closest-match (distance=\(best.distance)) for pid \(window.ownerPID)")
            return WindowHandle(cgID: window.id, ownerPID: window.ownerPID,
                                axElement: best.axWindow, originalFrame: best.frame)
        }

        NSLog("AccessibilityWindowController: could not resolve any AX window for pid \(window.ownerPID)")
        return nil
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

    static func raise(_ handle: WindowHandle) {
        AXUIElementPerformAction(handle.axElement, kAXRaiseAction as CFString)
        if let app = NSRunningApplication(processIdentifier: handle.ownerPID) {
            app.activate(options: [])
        }
    }
}
