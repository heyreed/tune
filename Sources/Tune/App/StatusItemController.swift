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
        let image = Bundle.module.image(forResource: "MenuBarIcon") ?? NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "Tune")
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = true
        button.image = image
        button.toolTip = sessionController.isActive ? "Tune is on" : "Tune"
    }

    private func configureMenu() {
        let menu = NSMenu()
        let openItem = NSMenuItem(title: "Tune Windows…", action: #selector(openLauncher), keyEquivalent: "t")
        openItem.keyEquivalentModifierMask = [.control, .option]
        openItem.target = self
        menu.addItem(openItem)

        let endItem = NSMenuItem(title: "End Tune", action: #selector(endSession), keyEquivalent: "")
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
