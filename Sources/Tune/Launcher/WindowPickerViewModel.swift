import AppKit
import Combine

final class WindowPickerViewModel: ObservableObject {
    @Published var availableWindows: [DiscoveredWindow] = []
    @Published var selectedWindowIDs: Set<CGWindowID> = []
    @Published var selectedScreenUUID: String?
    @Published var selectedBackground: BackgroundPreset = .blurredWallpaper

    let screens: [(uuid: String, name: String)]

    init() {
        self.screens = NSScreen.screens.map { screen in
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? "?"
            let name = screen.localizedName
            return (uuid: id, name: name)
        }
        self.selectedScreenUUID = screens.first?.uuid
    }

    func refresh() {
        availableWindows = WindowEnumerator.currentWindows()
        // Drop any selected IDs that are no longer visible.
        let visible = Set(availableWindows.map { $0.id })
        selectedWindowIDs.formIntersection(visible)
    }

    func toggle(_ window: DiscoveredWindow) {
        if selectedWindowIDs.contains(window.id) {
            selectedWindowIDs.remove(window.id)
        } else if selectedWindowIDs.count < 4 {
            selectedWindowIDs.insert(window.id)
        }
    }

    func buildConfiguration() -> SessionConfiguration? {
        let selected = availableWindows.filter { selectedWindowIDs.contains($0.id) }
        guard !selected.isEmpty else { return nil }
        return SessionConfiguration(
            targetWindows: selected,
            displayUUID: selectedScreenUUID,
            background: selectedBackground
        )
    }
}
