import AppKit
import ClicheKit
import ScreenCaptureKit

/// On-screen preview so users see what will be (or was just) captured.
enum CaptureBoundsOverlay {
    private static var window: NSWindow?

    /// Highlights a region or the full display. Pass `frozen` for a crisp
    /// preview of the pixels that will be captured (repeat-region, etc.).
    /// Stays visible until `hide()` when `duration` is nil.
    static func show(
        pixelRect: CGRect?,
        on screen: NSScreen,
        frozen: CGImage? = nil,
        label: String? = nil,
        duration: TimeInterval? = nil,
        completion: (() -> Void)? = nil
    ) {
        hide()
        let overlay = BoundsPreviewWindow(
            screen: screen,
            pixelRect: pixelRect,
            frozen: frozen,
            label: label ?? defaultLabel(pixelRect: pixelRect))
        overlay.orderFrontRegardless()
        window = overlay

        guard let duration else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            guard window === overlay else { return }
            hide()
            completion?()
        }
    }

    /// Brief shutter flash over the captured bounds.
    static func flash(pixelRect: CGRect?, on screen: NSScreen) {
        let flashWindow = FlashWindow(screen: screen, pixelRect: pixelRect)
        flashWindow.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            flashWindow.orderOut(nil)
        }
    }

    static func hide() {
        window?.orderOut(nil)
        window = nil
    }

    /// Outlines selected windows so the user can see what will be captured.
    static func showWindowHighlights(
        windows: [SCWindow], selectedIDs: Set<CGWindowID>
    ) {
        hideWindowHighlights()
        guard !selectedIDs.isEmpty else { return }
        for screen in NSScreen.screens {
            let view = WindowHighlightView(
                frame: NSRect(origin: .zero, size: screen.frame.size),
                windows: windows,
                selectedIDs: selectedIDs,
                screen: screen)
            let overlay = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false)
            overlay.level = .screenSaver
            overlay.backgroundColor = .clear
            overlay.isOpaque = false
            overlay.hasShadow = false
            overlay.isReleasedWhenClosed = false
            overlay.ignoresMouseEvents = true
            overlay.contentView = view
            overlay.orderFrontRegardless()
            highlightWindows.append(overlay)
        }
    }

    static func hideWindowHighlights() {
        highlightWindows.forEach { $0.orderOut(nil) }
        highlightWindows.removeAll()
    }

    private static var highlightWindows: [NSWindow] = []

    /// Converts a display-relative pixel rect (top-left origin) to view coords.
    static func viewRect(from pixelRect: CGRect, on screen: NSScreen, scale: CGFloat) -> NSRect {
        let height = screen.frame.height
        return NSRect(
            x: pixelRect.minX / scale,
            y: height - (pixelRect.maxY / scale),
            width: pixelRect.width / scale,
            height: pixelRect.height / scale)
    }

    private static func defaultLabel(pixelRect: CGRect?) -> String {
        if let pixelRect {
            return "Capturing \(Int(pixelRect.width)) × \(Int(pixelRect.height)) px"
        }
        return "Capturing full screen"
    }
}

// MARK: - Preview window

private final class BoundsPreviewWindow: NSWindow {
    init(screen: NSScreen, pixelRect: CGRect?, frozen: CGImage?, label: String) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false)
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        contentView = PreviewView(
            bounds: NSRect(origin: .zero, size: screen.frame.size),
            pixelRect: pixelRect,
            frozen: frozen,
            scale: screen.backingScaleFactor,
            label: label)
    }
}

private final class PreviewView: NSView {
    private let pixelRect: CGRect?
    private let frozen: CGImage?
    private let frozenImage: NSImage?
    private let scale: CGFloat
    private let label: String

    init(
        bounds: NSRect,
        pixelRect: CGRect?,
        frozen: CGImage?,
        scale: CGFloat,
        label: String
    ) {
        self.pixelRect = pixelRect
        self.frozen = frozen
        self.frozenImage = frozen.map { NSImage(cgImage: $0, size: bounds.size) }
        self.scale = scale
        self.label = label
        super.init(frame: bounds)
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        if let frozenImage {
            frozenImage.draw(in: bounds)
        }
        NSColor.black.withAlphaComponent(frozen == nil ? 0.25 : 0.35).setFill()
        bounds.fill()

        if let pixelRect, let frozenImage {
            let rect = CaptureBoundsOverlay.viewRect(from: pixelRect, on: enclosingScreen, scale: scale)
            frozenImage.draw(in: rect, from: rect, operation: .copy, fraction: 1)
            stroke(rect, color: .white)
            drawBadge(near: rect)
        } else if let pixelRect {
            let rect = CaptureBoundsOverlay.viewRect(from: pixelRect, on: enclosingScreen, scale: scale)
            NSColor.systemBlue.withAlphaComponent(0.15).setFill()
            rect.fill()
            stroke(rect, color: .systemBlue)
            drawBadge(near: rect)
        } else {
            stroke(bounds.insetBy(dx: 3, dy: 3), color: .white, width: 3)
            drawBadge(near: NSRect(x: bounds.midX - 120, y: bounds.midY, width: 240, height: 24))
        }
    }

    private var enclosingScreen: NSScreen {
        window?.screen ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func stroke(_ rect: NSRect, color: NSColor, width: CGFloat = 2) {
        color.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = width
        path.stroke()
    }

    private func drawBadge(near rect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let size = (label as NSString).size(withAttributes: attributes)
        var origin = NSPoint(x: rect.midX - size.width / 2, y: rect.maxY + 8)
        if origin.y + size.height > bounds.maxY - 8 {
            origin.y = rect.minY - size.height - 8
        }
        let badge = NSRect(
            x: origin.x - 8, y: origin.y - 4,
            width: size.width + 16, height: size.height + 8)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: badge, xRadius: 6, yRadius: 6).fill()
        (label as NSString).draw(at: origin, withAttributes: attributes)
    }
}

// MARK: - Flash window

private final class FlashWindow: NSWindow {
    init(screen: NSScreen, pixelRect: CGRect?) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false)
        level = .screenSaver + 1
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isReleasedWhenClosed = true
        ignoresMouseEvents = true
        contentView = FlashView(
            bounds: NSRect(origin: .zero, size: screen.frame.size),
            pixelRect: pixelRect,
            scale: screen.backingScaleFactor)
    }
}

private final class FlashView: NSView {
    private let pixelRect: CGRect?
    private let scale: CGFloat

    init(bounds: NSRect, pixelRect: CGRect?, scale: CGFloat) {
        self.pixelRect = pixelRect
        self.scale = scale
        super.init(frame: bounds)
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let rect: NSRect
        if let pixelRect {
            rect = CaptureBoundsOverlay.viewRect(
                from: pixelRect,
                on: window?.screen ?? NSScreen.main ?? NSScreen.screens[0],
                scale: scale)
        } else {
            rect = bounds
        }
        NSColor.white.withAlphaComponent(0.35).setFill()
        rect.fill()
        NSColor.white.setStroke()
        let outline = NSBezierPath(rect: rect)
        outline.lineWidth = 2
        outline.stroke()
    }
}

// MARK: - Window highlight

private final class WindowHighlightView: NSView {
    private let windows: [SCWindow]
    private let selectedIDs: Set<CGWindowID>
    private let screen: NSScreen

    init(
        frame: NSRect,
        windows: [SCWindow],
        selectedIDs: Set<CGWindowID>,
        screen: NSScreen
    ) {
        self.windows = windows
        self.selectedIDs = selectedIDs
        self.screen = screen
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        for window in windows where selectedIDs.contains(window.windowID) {
            let rect = globalTopLeftRect(window.frame, on: screen)
            guard bounds.intersects(rect) else { continue }
            NSColor.systemBlue.withAlphaComponent(0.12).setFill()
            rect.fill()
            NSColor.systemBlue.setStroke()
            let outline = NSBezierPath(rect: rect)
            outline.lineWidth = 2.5
            outline.stroke()
        }
    }

    /// SCWindow frames use global top-left origin; convert to view coords.
    private func globalTopLeftRect(_ frame: CGRect, on screen: NSScreen) -> NSRect {
        NSRect(
            x: frame.minX - screen.frame.minX,
            y: screen.frame.maxY - frame.maxY,
            width: frame.width,
            height: frame.height)
    }
}
