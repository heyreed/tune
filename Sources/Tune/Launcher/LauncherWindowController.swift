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
        viewModel.refresh()

        if let window {
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
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
