import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Floating thumbnail shown in the corner after each capture: drag it into
/// another app, click to annotate, or let it auto-dismiss.
enum CaptureOverlay {
    private static var panel: NSPanel?
    private static var dismissTimer: Timer?

    static func show(fileURL: URL, qrLink: String? = nil, onAnnotate: @escaping (URL) -> Void) {
        hide()
        guard let image = NSImage(contentsOf: fileURL) else { return }

        let thumbWidth: CGFloat = 224
        let aspect = image.size.height / max(image.size.width, 1)
        let size = NSSize(
            width: thumbWidth,
            height: min(thumbWidth * aspect, 170) + 16)  // padding for shadow

        let overlayPanel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        overlayPanel.level = .statusBar
        overlayPanel.backgroundColor = .clear
        overlayPanel.isOpaque = false
        overlayPanel.hasShadow = false
        overlayPanel.isReleasedWhenClosed = false
        overlayPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = OverlayThumbnail(
            image: image,
            fileURL: fileURL,
            qrLink: qrLink,
            onAnnotate: {
                hide()
                onAnnotate(fileURL)
            },
            onDismiss: { hide() },
            onHoverChanged: { hovering in
                if hovering {
                    dismissTimer?.invalidate()
                    dismissTimer = nil
                } else {
                    scheduleDismiss(after: 3)
                }
            })
        overlayPanel.contentView = NSHostingView(rootView: view)

        // Bottom-left corner of the screen the mouse is on, above the Dock.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens[0]
        overlayPanel.setFrameOrigin(NSPoint(
            x: screen.visibleFrame.minX + 16,
            y: screen.visibleFrame.minY + 16))
        overlayPanel.orderFrontRegardless()

        panel = overlayPanel
        scheduleDismiss(after: 6)
    }

    static func hide() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private static func scheduleDismiss(after seconds: TimeInterval) {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(
            withTimeInterval: seconds, repeats: false
        ) { _ in
            hide()
        }
    }
}

private struct OverlayThumbnail: View {
    let image: NSImage
    let fileURL: URL
    let qrLink: String?
    let onAnnotate: () -> Void
    let onDismiss: () -> Void
    let onHoverChanged: (Bool) -> Void

    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.white.opacity(0.8), lineWidth: 1))
                .shadow(radius: 6)
                .onTapGesture(perform: onAnnotate)
                .onDrag { NSItemProvider(contentsOf: fileURL) ?? NSItemProvider() }

            if isHovering {
                HStack(spacing: 6) {
                    if let qrLink {
                        Button {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(qrLink, forType: .string)
                            onDismiss()
                        } label: {
                            Image(systemName: "qrcode")
                        }
                        .help("QR code found — copy its link")
                    }
                    Button(action: onAnnotate) {
                        Image(systemName: "pencil.tip.crop.circle")
                    }
                    .help("Annotate")
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                    } label: {
                        Image(systemName: "folder")
                    }
                    .help("Show in Finder")
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .help("Dismiss")
                }
                .buttonStyle(.plain)
                .font(.title3)
                .foregroundStyle(.white)
                .shadow(radius: 3)
                .padding(6)
            }
        }
        .padding(8)
        .onHover { hovering in
            isHovering = hovering
            onHoverChanged(hovering)
        }
        .help("Click to annotate · drag into another app · folder icon shows in Finder")
    }
}
