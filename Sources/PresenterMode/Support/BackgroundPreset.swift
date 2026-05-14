import AppKit
import CoreImage

enum BackgroundPreset: String, CaseIterable, Identifiable {
    case blurredWallpaper
    case duskGradient
    case neutralGray

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blurredWallpaper: return "Blurred wallpaper"
        case .duskGradient: return "Dusk gradient"
        case .neutralGray: return "Neutral gray"
        }
    }

    /// Build an NSImage sized for the given screen.
    func render(for screen: NSScreen) -> NSImage {
        let size = screen.frame.size
        switch self {
        case .blurredWallpaper:
            return Self.renderBlurredWallpaper(for: screen) ?? Self.renderGradient(size: size, top: .black, bottom: .darkGray)
        case .duskGradient:
            let top = NSColor(red: 0.18, green: 0.20, blue: 0.32, alpha: 1)
            let bottom = NSColor(red: 0.05, green: 0.07, blue: 0.14, alpha: 1)
            return Self.renderGradient(size: size, top: top, bottom: bottom)
        case .neutralGray:
            return Self.renderSolid(size: size, color: NSColor(white: 0.12, alpha: 1))
        }
    }

    private static func renderSolid(size: CGSize, color: NSColor) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return image
    }

    private static func renderGradient(size: CGSize, top: NSColor, bottom: NSColor) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        let gradient = NSGradient(starting: top, ending: bottom)
        gradient?.draw(in: NSRect(origin: .zero, size: size), angle: -90)
        image.unlockFocus()
        return image
    }

    private static func renderBlurredWallpaper(for screen: NSScreen) -> NSImage? {
        // Best-effort: pull the wallpaper URL from the workspace and blur it.
        // If the user is on Sonoma+ with dynamic wallpapers, this returns the current snapshot.
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let baseImage = CIImage(contentsOf: url) else {
            return nil
        }
        let filter = CIFilter(name: "CIGaussianBlur")
        filter?.setValue(baseImage, forKey: kCIInputImageKey)
        filter?.setValue(40.0, forKey: kCIInputRadiusKey)
        guard let outputCI = filter?.outputImage?.cropped(to: baseImage.extent) else { return nil }

        let context = CIContext()
        guard let cgImage = context.createCGImage(outputCI, from: outputCI.extent) else { return nil }
        let blurred = NSImage(cgImage: cgImage, size: screen.frame.size)

        // Dim slightly so the staged window stands out.
        let darkened = NSImage(size: blurred.size)
        darkened.lockFocus()
        blurred.draw(in: NSRect(origin: .zero, size: blurred.size))
        NSColor.black.withAlphaComponent(0.35).setFill()
        NSRect(origin: .zero, size: blurred.size).fill()
        darkened.unlockFocus()
        return darkened
    }
}
