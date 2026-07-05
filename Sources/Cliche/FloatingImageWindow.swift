import AppKit

/// Shows an image in a small always-on-top panel for reference while working
/// in other apps (Shottr/Flameshot-style "pin screenshot").
enum FloatingImageWindow {
    private static var openPanels: [NSPanel] = []

    static func show(image: NSImage) {
        let maxSide: CGFloat = 480
        let scale = min(1, maxSide / max(image.size.width, image.size.height, 1))
        let size = NSSize(width: image.size.width * scale,
                          height: image.size.height * scale)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        panel.title = "Pinned Screenshot"
        panel.titlebarAppearsTransparent = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        panel.contentView = imageView

        panel.center()
        panel.orderFrontRegardless()

        openPanels.append(panel)
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: panel, queue: .main
        ) { notification in
            guard let closing = notification.object as? NSPanel else { return }
            openPanels.removeAll { $0 === closing }
        }
    }
}
