import AppKit
import SwiftUI

final class LauncherWindowController {
    private let sessionController: SessionController
    private let viewModel = WindowPickerViewModel()
    private var window: NSWindow?

    init(sessionController: SessionController) {
        self.sessionController = sessionController
    }

    func toggle() {
        if let window, window.isVisible {
            window.orderOut(nil)
        } else {
            show()
        }
    }

    func show() {
        // Window titles in the picker depend on Screen Recording permission. Prompt lazily
        // here rather than at launch so users who only use the menu-bar items aren't asked.
        ScreenRecordingGate.requestIfNeeded()
        viewModel.refresh()

        if let window {
            // Re-center on the active Space's main screen so a cached window doesn't appear
            // off to the side after a display change, and `.moveToActiveSpace` pulls it onto
            // the user's current Space.
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = LauncherView(
            viewModel: viewModel,
            onStart: { [weak self] config in
                self?.window?.orderOut(nil)
                self?.sessionController.start(config)
            },
            onCancel: { [weak self] in
                self?.window?.orderOut(nil)
            }
        )

        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Tune"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        // Without this, the cached window stays anchored to whichever Space it was first shown
        // on. Re-invoking the hotkey from another Space would yank the user back to that Space
        // instead of bringing the launcher to them.
        window.collectionBehavior = [.moveToActiveSpace]
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
