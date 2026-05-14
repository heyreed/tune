import AppKit
import Combine

final class StatusItemController {
    private let statusItem: NSStatusItem
    private let sessionController: SessionController
    private let launcherController: LauncherWindowController
    private var cancellables: Set<AnyCancellable> = []

    init(sessionController: SessionController, launcherController: LauncherWindowController) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.sessionController = sessionController
        self.launcherController = launcherController
        configureButton()
        configureMenu()

        sessionController.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.configureButton() }
            .store(in: &cancellables)
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        let symbol = sessionController.isActive ? "rectangle.inset.filled.and.person.filled" : "rectangle.on.rectangle"
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Presenter Mode")
        button.image?.isTemplate = true
        button.toolTip = sessionController.isActive ? "Presenter Mode active" : "Presenter Mode"
    }

    private func configureMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Launcher…", action: #selector(openLauncher), keyEquivalent: "p"))
        menu.items.last?.keyEquivalentModifierMask = [.control, .shift]
        menu.items.last?.target = self

        let endItem = NSMenuItem(title: "End Presenter Mode", action: #selector(endSession), keyEquivalent: "")
        endItem.target = self
        menu.addItem(endItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func openLauncher() {
        launcherController.show()
    }

    @objc private func endSession() {
        sessionController.endSessionIfActive()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
