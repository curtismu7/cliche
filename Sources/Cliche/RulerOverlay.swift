import AppKit
import ClicheKit

/// Pixel ruler: full-screen overlay on a frozen frame. Hovering shows the
/// enclosing UI element's box (edge-snapped) with pixel dimensions; dragging
/// measures between two points; clicking copies the dimensions. Esc exits.
final class RulerOverlay {
    private static var active: RulerOverlay?

    private var window: NSWindow?

    static func begin(frozen: CGImage, on screen: NSScreen) {
        guard active == nil, let measure = EdgeMeasure(image: frozen) else { return }
        let overlay = RulerOverlay()
        active = overlay
        overlay.show(frozen: frozen, measure: measure, on: screen)
    }

    private func show(frozen: CGImage, measure: EdgeMeasure, on screen: NSScreen) {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false)
        window.level = .screenSaver
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true

        let view = RulerView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            frozen: frozen,
            measure: measure)
        view.onDone = { [weak self] in
            self?.window?.orderOut(nil)
            self?.window = nil
            RulerOverlay.active = nil
        }
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(view)
        self.window = window
    }
}

private final class RulerView: NSView {
    var onDone: (() -> Void)?

    private let frozenImage: NSImage
    private let measure: EdgeMeasure
    private let pixelWidth: CGFloat

    private var hoverPoint: NSPoint = .zero
    private var dragStart: NSPoint?
    private var dragCurrent: NSPoint?
    private var lastBoxText = ""

    private var scale: CGFloat { pixelWidth / bounds.width }

    init(frame: NSRect, frozen: CGImage, measure: EdgeMeasure) {
        self.frozenImage = NSImage(cgImage: frozen, size: frame.size)
        self.measure = measure
        self.pixelWidth = CGFloat(frozen.width)
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseMoved(with event: NSEvent) {
        hoverPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
        dragCurrent = dragStart
    }

    override func mouseDragged(with event: NSEvent) {
        dragCurrent = convert(event.locationInWindow, from: nil)
        hoverPoint = dragCurrent!
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let start = dragStart, let current = dragCurrent,
           hypot(current.x - start.x, current.y - start.y) < 4,
           !lastBoxText.isEmpty {
            // Click: copy the hovered element's dimensions.
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(lastBoxText, forType: .string)
            InfoHUD.show("\(lastBoxText) copied")
        }
        dragStart = nil
        dragCurrent = nil
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onDone?() }  // Esc
    }

    override func draw(_ dirtyRect: NSRect) {
        frozenImage.draw(in: bounds)

        if let start = dragStart, let current = dragCurrent,
           hypot(current.x - start.x, current.y - start.y) >= 4 {
            drawManualMeasure(from: start, to: current)
        } else {
            drawEdgeBox(at: hoverPoint)
        }
        drawHint()
    }

    private func drawEdgeBox(at point: NSPoint) {
        let px = Int(point.x * scale)
        let py = Int((bounds.height - point.y) * scale)  // top-left pixel coords
        guard let span = measure.span(x: px, y: py) else { return }

        let left = point.x - CGFloat(span.left) / scale
        let right = point.x + CGFloat(span.right) / scale
        let top = point.y + CGFloat(span.up) / scale
        let bottom = point.y - CGFloat(span.down) / scale

        NSColor.systemRed.setStroke()
        let lines = NSBezierPath()
        lines.move(to: NSPoint(x: left, y: point.y))
        lines.line(to: NSPoint(x: right, y: point.y))
        lines.move(to: NSPoint(x: point.x, y: bottom))
        lines.line(to: NSPoint(x: point.x, y: top))
        lines.lineWidth = 1
        lines.stroke()

        let boxRect = NSRect(x: left, y: bottom, width: right - left, height: top - bottom)
        let outline = NSBezierPath(rect: boxRect)
        outline.setLineDash([4, 3], count: 2, phase: 0)
        outline.lineWidth = 1
        outline.stroke()

        lastBoxText = "\(span.left + span.right + 1) × \(span.up + span.down + 1)"
        drawBadge("\(lastBoxText) px", near: NSPoint(x: point.x + 14, y: point.y + 14))
    }

    private func drawManualMeasure(from start: NSPoint, to end: NSPoint) {
        NSColor.systemRed.setStroke()
        let line = NSBezierPath()
        line.move(to: start)
        line.line(to: end)
        line.lineWidth = 1.5
        line.stroke()

        let dx = abs(end.x - start.x) * scale
        let dy = abs(end.y - start.y) * scale
        let distance = Int(hypot(dx, dy).rounded())
        drawBadge(
            "\(distance) px  (\(Int(dx.rounded())) × \(Int(dy.rounded())))",
            near: NSPoint(x: end.x + 14, y: end.y + 14))
    }

    private func drawBadge(_ text: String, near point: NSPoint) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        var origin = point
        if origin.x + size.width + 12 > bounds.maxX { origin.x = point.x - size.width - 28 }
        if origin.y + size.height + 8 > bounds.maxY { origin.y = point.y - size.height - 28 }
        let badge = NSRect(
            x: origin.x - 5, y: origin.y - 3,
            width: size.width + 10, height: size.height + 6)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: badge, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }

    private func drawHint() {
        drawBadge(
            "hover: element size · drag: measure · click: copy · esc: exit",
            near: NSPoint(x: bounds.midX - 190, y: bounds.maxY - 36))
    }
}
