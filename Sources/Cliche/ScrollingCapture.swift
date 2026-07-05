import AppKit
import ClicheKit

/// Panoramic (scrolling) capture: after the user picks a region, frames of
/// that region are grabbed on a timer while THEY scroll the content; Done
/// stitches everything into one tall image.
final class ScrollingCapture {
    private static var active: ScrollingCapture?
    private static let maxFrames = 40

    private let displayID: CGDirectDisplayID
    private let pointRect: CGRect  // display-relative, top-left origin, points
    private let scale: CGFloat
    private let showsCursor: Bool
    private let deliver: (CGImage) -> Void

    private var frames: [CGImage] = []
    private var timer: Timer?
    private var hud: NSPanel?
    private var countLabel: NSTextField?

    static func begin(
        displayID: CGDirectDisplayID,
        pixelRect: CGRect,
        scale: CGFloat,
        showsCursor: Bool,
        on screen: NSScreen,
        deliver: @escaping (CGImage) -> Void
    ) {
        guard active == nil else { return }
        let capture = ScrollingCapture(
            displayID: displayID,
            pointRect: CGRect(
                x: pixelRect.minX / scale, y: pixelRect.minY / scale,
                width: pixelRect.width / scale, height: pixelRect.height / scale),
            scale: scale,
            showsCursor: showsCursor,
            deliver: deliver)
        active = capture
        capture.start(on: screen)
    }

    private init(
        displayID: CGDirectDisplayID, pointRect: CGRect, scale: CGFloat,
        showsCursor: Bool, deliver: @escaping (CGImage) -> Void
    ) {
        self.displayID = displayID
        self.pointRect = pointRect
        self.scale = scale
        self.showsCursor = showsCursor
        self.deliver = deliver
    }

    private func start(on screen: NSScreen) {
        showHUD(on: screen)
        timer = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: true) { [weak self] _ in
            self?.captureFrame()
        }
        captureFrame()
    }

    private func captureFrame() {
        guard frames.count < Self.maxFrames else {
            finish()
            return
        }
        Task { @MainActor in
            guard ScrollingCapture.active === self else { return }
            if let frame = try? await ScreenshotEngine.captureImage(
                displayID: displayID, sourceRect: pointRect, scale: scale,
                showsCursor: showsCursor) {
                frames.append(frame)
                countLabel?.stringValue =
                    "Scroll the content — \(frames.count) frames"
            }
        }
    }

    private func showHUD(on screen: NSScreen) {
        let size = NSSize(width: 340, height: 56)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true

        let background = NSView(frame: NSRect(origin: .zero, size: size))
        background.wantsLayer = true
        background.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.8).cgColor
        background.layer?.cornerRadius = 12

        let label = NSTextField(labelWithString: "Scroll the content — 0 frames")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.frame = NSRect(x: 14, y: 30, width: 312, height: 18)

        let done = NSButton(title: "Done — Stitch", target: self, action: #selector(doneTapped))
        done.bezelStyle = .rounded
        done.frame = NSRect(x: 14, y: 4, width: 130, height: 24)
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancel.bezelStyle = .rounded
        cancel.frame = NSRect(x: 150, y: 4, width: 80, height: 24)

        background.addSubview(label)
        background.addSubview(done)
        background.addSubview(cancel)
        panel.contentView = background
        // Bottom-center of the screen, clear of the region being scrolled.
        panel.setFrameOrigin(NSPoint(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.minY + 24))
        panel.orderFrontRegardless()

        hud = panel
        countLabel = label
    }

    @objc private func doneTapped() { finish() }

    @objc private func cancelTapped() { teardown() }

    private func finish() {
        let captured = frames
        teardown()
        guard !captured.isEmpty else { return }
        InfoHUD.show("Stitching \(captured.count) frames…")
        DispatchQueue.global(qos: .userInitiated).async { [deliver] in
            let stitched = Stitcher.stitch(captured)
            DispatchQueue.main.async {
                if let stitched {
                    deliver(stitched)
                } else {
                    InfoHUD.show("Could not stitch the frames")
                }
            }
        }
    }

    private func teardown() {
        timer?.invalidate()
        timer = nil
        hud?.orderOut(nil)
        hud = nil
        Self.active = nil
    }
}
