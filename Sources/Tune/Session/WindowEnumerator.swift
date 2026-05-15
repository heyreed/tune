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
    /// All on-screen normal-level windows, sorted by stacking order (frontmost first).
    /// Filters out our own windows, menubar items, and system UI.
    static func currentWindows() -> [DiscoveredWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier

        return raw.compactMap { dict -> DiscoveredWindow? in
            guard
                let layer = dict[kCGWindowLayer as String] as? Int, layer == 0,
                let windowID = dict[kCGWindowNumber as String] as? CGWindowID,
                let pid = dict[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                let owner = dict[kCGWindowOwnerName as String] as? String,
                let boundsDict = dict[kCGWindowBounds as String] as? [String: CGFloat],
                let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { return nil }

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
