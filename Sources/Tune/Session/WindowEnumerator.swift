import AppKit
import ApplicationServices

struct DiscoveredWindow: Identifiable, Hashable {
    let id: CGWindowID
    let ownerPID: pid_t
    let ownerName: String
    let title: String
    let bounds: CGRect

    var displayLabel: String {
        title.isEmpty ? ownerName : "\(ownerName) — \(title)"
    }
}

enum WindowEnumerator {
    /// All normal-level windows across every Space, sorted by stacking order (frontmost first).
    /// Filters out our own windows, menubar items, and system UI.
    ///
    /// Note: we deliberately omit `.optionOnScreenOnly` so that windows on other Spaces show up
    /// in the picker. With the on-screen filter, the launcher could only see whatever happened
    /// to be on the current Space when invoked — which made the picker effectively empty if the
    /// launcher's own Space had no apps on it.
    static func currentWindows() -> [DiscoveredWindow] {
        let options: CGWindowListOption = [.excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier

        // Cache the activation-policy lookup per PID. CGWindowList returns many rows per app
        // and NSRunningApplication(processIdentifier:) is not free.
        var policyCache: [pid_t: NSApplication.ActivationPolicy?] = [:]
        func isProhibited(_ pid: pid_t) -> Bool {
            if let cached = policyCache[pid] { return cached == .prohibited }
            let policy = NSRunningApplication(processIdentifier: pid)?.activationPolicy
            policyCache[pid] = policy
            return policy == .prohibited
        }

        return raw.compactMap { dict -> DiscoveredWindow? in
            guard
                let layer = dict[kCGWindowLayer as String] as? Int, layer == 0,
                let windowID = dict[kCGWindowNumber as String] as? CGWindowID,
                let pid = dict[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                let owner = dict[kCGWindowOwnerName as String] as? String,
                let boundsDict = dict[kCGWindowBounds as String] as? [String: CGFloat],
                let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { return nil }

            // Drop windows owned by background-only processes (Safari's AutoFill helper,
            // Spotlight, Notification Center, etc.). Their CGWindow rows leak through the
            // layer/size filters but the user can't meaningfully "tune" them.
            if isProhibited(pid) { return nil }

            let title = (dict[kCGWindowName as String] as? String) ?? ""
            // Skip zero-sized or hidden chrome windows
            if bounds.width < 80 || bounds.height < 80 { return nil }

            return DiscoveredWindow(
                id: windowID,
                ownerPID: pid,
                ownerName: owner,
                title: title,
                bounds: bounds
            )
        }
    }
}
