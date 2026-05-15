import AppKit

/// Manages the visual stage behind the presented window:
///
/// - **Main background window** (below normal windows). Paints the chosen background preset
///   across the full screen. Sits at desktop-icon level so target windows naturally float
///   above it. Non-target apps are hidden by SessionController so nothing else shows through.
///
/// - **Menu bar mask** (above the menu bar). A thin strip at the top of the screen, drawn at
///   `kCGMainMenuWindowLevel + 1`, that obscures the menu bar and its extras (Slack/Notion/
///   battery/clock/etc.). Renders the same background image, cropped to the strip so the
///   visual treatment looks continuous.
///
/// - **Dock mask** (above the Dock). Same idea: a strip along the bottom or side of the screen
///   covering the Dock. Only created when the Dock is actually visible (i.e., not in auto-hide
///   mode and currently consuming visibleFrame).
///
/// We can't use `NSApp.presentationOptions = [.autoHideMenuBar]` because those flags only apply
/// when our app is frontmost — and we deliberately activate the target app for keyboard input.
final class StagingOverlay {
    private var mainWindow: NSWindow?
    private var menuBarMask: NSWindow?
    private var dockMask: NSWindow?

    let screen: NSScreen

    init(screen: NSScreen) {
        self.screen = screen
    }

    func show(background: BackgroundPreset) {
        let image = background.render(for: screen)
        mainWindow = makeMainWindow(image: image)
        menuBarMask = makeMenuBarMask(image: image)
        dockMask = makeDockMask(image: image)
    }

    func hide() {
        mainWindow?.orderOut(nil); mainWindow = nil
        menuBarMask?.orderOut(nil); menuBarMask = nil
        dockMask?.orderOut(nil); dockMask = nil
    }

    // MARK: - Main background window

    private func makeMainWindow(image: NSImage) -> NSWindow {
        let frame = screen.frame
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.isOpaque = true
        window.hasShadow = false
        window.ignoresMouseEvents = true
        // Below the normal window plane so target windows float above us naturally.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.backgroundColor = .black

        let view = NSImageView(frame: NSRect(origin: .zero, size: frame.size))
        view.imageScaling = .scaleAxesIndependently
        view.image = image
        view.autoresizingMask = [.width, .height]
        window.contentView = view

        window.orderFrontRegardless()
        return window
    }

    // MARK: - Menu bar mask

    private func makeMenuBarMask(image: NSImage) -> NSWindow? {
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        guard menuBarHeight > 0.5 else { return nil }  // menu bar is auto-hidden already

        let frame = NSRect(
            x: screen.frame.minX,
            y: screen.frame.maxY - menuBarHeight,
            width: screen.frame.width,
            height: menuBarHeight
        )
        return makeMaskWindow(frame: frame, fullScreenImage: image, alignment: .alignTop)
    }

    // MARK: - Dock mask

    private func makeDockMask(image: NSImage) -> NSWindow? {
        // The Dock can be on the bottom, left, or right. We figure out which by comparing
        // screen.frame and screen.visibleFrame.
        let full = screen.frame
        let visible = screen.visibleFrame

        let bottomGap = visible.minY - full.minY
        let leftGap = visible.minX - full.minX
        let rightGap = full.maxX - visible.maxX

        if bottomGap > 0.5 {
            let frame = NSRect(x: full.minX, y: full.minY, width: full.width, height: bottomGap)
            return makeMaskWindow(frame: frame, fullScreenImage: image, alignment: .alignBottom)
        }
        if leftGap > 0.5 {
            let frame = NSRect(x: full.minX, y: full.minY, width: leftGap, height: full.height)
            return makeMaskWindow(frame: frame, fullScreenImage: image, alignment: .alignLeft)
        }
        if rightGap > 0.5 {
            let frame = NSRect(x: full.maxX - rightGap, y: full.minY, width: rightGap, height: full.height)
            return makeMaskWindow(frame: frame, fullScreenImage: image, alignment: .alignRight)
        }
        return nil
    }

    // MARK: - Mask window builder

    /// Builds an opaque, click-blocking window at a level above the menu bar/dock that displays
    /// the corresponding slice of the full-screen background image. We position a full-screen-sized
    /// NSImageView with no scaling and an alignment that anchors the desired slice to the view's
    /// bounds — the rest of the image is clipped by the window's frame.
    private func makeMaskWindow(frame: NSRect, fullScreenImage: NSImage, alignment: NSImageAlignment) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.isOpaque = true
        window.hasShadow = false
        window.ignoresMouseEvents = false   // we *want* to swallow clicks on the menu bar / Dock
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.backgroundColor = .black

        let imageView = NSImageView(frame: NSRect(origin: .zero, size: frame.size))
        imageView.imageScaling = .scaleNone
        imageView.imageAlignment = alignment
        imageView.image = fullScreenImage
        imageView.autoresizingMask = [.width, .height]
        window.contentView = imageView

        window.orderFrontRegardless()
        return window
    }
}
