import AppKit
import ClicheKit
import SwiftUI

/// Full-screen region picker over a FROZEN frame of the display: the screen
/// stops moving while you select, a magnifier loupe follows the cursor, the
/// live size label shows pixel dimensions, and holding Shift locks the
/// selection to a square. Esc cancels.
///
/// Completion delivers the selection as a PIXEL rect (top-left origin,
/// display-relative — ready for `CGImage.cropping(to:)` on the frozen frame).
final class RegionSelector {
    private static var active: RegionSelector?

    private var window: NSWindow?
    private let completion: (CGRect?) -> Void

    static func begin(
        frozen: CGImage, on screen: NSScreen, completion: @escaping (CGRect?) -> Void
    ) {
        guard active == nil else {
            completion(nil)
            return
        }
        let selector = RegionSelector(completion: completion)
        active = selector
        selector.show(frozen: frozen, on: screen)
    }

    // MARK: All-in-one variant

    private var mode: AllInOneMode = .region
    private var onSelectMode: ((CGRect, AllInOneMode) -> Void)?
    private var onSwitchAway: ((AllInOneMode) -> Void)?
    private var onCancelAllInOne: (() -> Void)?
    private var stripHost: NSHostingView<ModeStripView>?
    private var isAllInOne: Bool { onSelectMode != nil }

    /// All-in-one variant: same frozen-frame picker plus a mode strip.
    /// Region/OCR select in place; Window/Full Screen call `onSwitchAway`
    /// after the overlay is dismissed. Esc calls `onCancel`.
    static func begin(
        frozen: CGImage, on screen: NSScreen,
        allInOne initialMode: AllInOneMode,
        onSelect: @escaping (CGRect, AllInOneMode) -> Void,
        onSwitchAway: @escaping (AllInOneMode) -> Void,
        onCancel: @escaping () -> Void
    ) {
        guard active == nil else {
            onCancel()
            return
        }
        let selector = RegionSelector(completion: { _ in })
        selector.mode = initialMode
        selector.onSelectMode = onSelect
        selector.onSwitchAway = onSwitchAway
        selector.onCancelAllInOne = onCancel
        active = selector
        selector.show(frozen: frozen, on: screen)
        selector.installStrip()
    }

    private func installStrip() {
        guard isAllInOne, let window, let contentView = window.contentView else { return }
        let host = NSHostingView(rootView: ModeStripView(
            current: mode, onPick: { [weak self] in self?.switchMode(to: $0) }))
        host.frame.size = host.fittingSize
        host.frame.origin = NSPoint(
            x: (contentView.bounds.width - host.frame.width) / 2,
            y: contentView.bounds.height - host.frame.height - 24)
        contentView.addSubview(host)
        stripHost = host
        (contentView as? SelectionView)?.onModeKey = { [weak self] key in
            guard let mode = AllInOneMode.mode(forKey: key) else { return false }
            self?.switchMode(to: mode)
            return true
        }
    }

    private func switchMode(to newMode: AllInOneMode) {
        guard newMode != mode else { return }
        if newMode.switchesInPlace {
            mode = newMode
            stripHost?.rootView = ModeStripView(
                current: newMode, onPick: { [weak self] in self?.switchMode(to: $0) })
        } else {
            let handler = onSwitchAway
            teardown()
            handler?(newMode)
        }
    }

    private func teardown() {
        window?.orderOut(nil)
        window = nil
        Self.active = nil
    }

    private init(completion: @escaping (CGRect?) -> Void) {
        self.completion = completion
    }

    private func show(frozen: CGImage, on screen: NSScreen) {
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

        let view = SelectionView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            frozen: frozen)
        view.onFinish = { [weak self] pixelRect in
            self?.finish(pixelRect)
        }
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(view)
        self.window = window
    }

    private func finish(_ pixelRect: CGRect?) {
        let selectHandler = onSelectMode
        let cancelHandler = onCancelAllInOne
        let currentMode = mode
        let wasAllInOne = isAllInOne
        teardown()
        if let rect = pixelRect, rect.width >= 4, rect.height >= 4 {
            if wasAllInOne {
                selectHandler?(rect.integral, currentMode)
            } else {
                completion(rect.integral)
            }
        } else {
            if wasAllInOne {
                cancelHandler?()
            } else {
                completion(nil)
            }
        }
    }
}

private final class SelectionView: NSView {
    var onFinish: ((CGRect?) -> Void)?
    /// All-in-one mode keys (1–4); returns true if the key was handled.
    var onModeKey: ((String) -> Bool)?

    private let frozen: CGImage
    private let frozenNSImage: NSImage
    /// Pixels per view point.
    private var pixelScale: CGFloat { CGFloat(frozen.width) / bounds.width }

    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?
    private var hoverPoint: NSPoint = .zero

    init(frame: NSRect, frozen: CGImage) {
        self.frozen = frozen
        self.frozenNSImage = NSImage(
            cgImage: frozen, size: frame.size)
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { nil }

    private var selectionRect: NSRect? {
        guard let start = startPoint, var current = currentPoint else { return nil }
        if NSEvent.modifierFlags.contains(.shift) {
            // Square lock: take the larger drag axis, preserve direction.
            let side = max(abs(current.x - start.x), abs(current.y - start.y))
            current = NSPoint(
                x: start.x + (current.x >= start.x ? side : -side),
                y: start.y + (current.y >= start.y ? side : -side))
        }
        return NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(start.x - current.x),
            height: abs(start.y - current.y))
    }

    /// View rect (bottom-left origin, points) → image pixels (top-left origin).
    private func pixelRect(from viewRect: NSRect) -> CGRect {
        let scale = pixelScale
        return CGRect(
            x: viewRect.minX * scale,
            y: (bounds.height - viewRect.maxY) * scale,
            width: viewRect.width * scale,
            height: viewRect.height * scale)
    }

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hoverPoint = convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)
    }

    override func mouseMoved(with event: NSEvent) {
        hoverPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        hoverPoint = currentPoint!
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        onFinish?(selectionRect.map(pixelRect(from:)))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {  // Esc
            onFinish?(nil)
            return
        }
        if let characters = event.charactersIgnoringModifiers,
           onModeKey?(characters) == true {
            return
        }
    }

    override func flagsChanged(with event: NSEvent) {
        needsDisplay = true  // live square-lock preview when Shift toggles
    }

    override func draw(_ dirtyRect: NSRect) {
        // Frozen frame as the backdrop, dimmed.
        frozenNSImage.draw(in: bounds)
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()

        if let rect = selectionRect {
            // Re-draw the selected area crisp (undimmed) from the frozen frame.
            frozenNSImage.draw(in: rect, from: rect, operation: .copy, fraction: 1)
            NSColor.white.setStroke()
            let outline = NSBezierPath(rect: rect)
            outline.lineWidth = 1
            outline.stroke()
            drawSizeLabel(for: rect)
        }
        drawLoupe(at: hoverPoint)
    }

    private func drawSizeLabel(for rect: NSRect) {
        let pixels = pixelRect(from: rect)
        let text = "\(Int(pixels.width)) × \(Int(pixels.height)) px"
            + (NSEvent.modifierFlags.contains(.shift) ? "  ▣" : "")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        var origin = NSPoint(x: rect.minX, y: rect.minY - size.height - 6)
        if origin.y < 4 { origin.y = rect.minY + 6 }
        let badge = NSRect(
            x: origin.x - 5, y: origin.y - 3,
            width: size.width + 10, height: size.height + 6)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: badge, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }

    private func drawLoupe(at point: NSPoint) {
        let loupeSize: CGFloat = 110
        let sourceSide: CGFloat = 15  // view points magnified into the loupe

        var origin = NSPoint(x: point.x + 24, y: point.y + 24)
        if origin.x + loupeSize > bounds.maxX { origin.x = point.x - 24 - loupeSize }
        if origin.y + loupeSize > bounds.maxY { origin.y = point.y - 24 - loupeSize }
        let loupeRect = NSRect(x: origin.x, y: origin.y, width: loupeSize, height: loupeSize)
        let sourceRect = NSRect(
            x: point.x - sourceSide / 2, y: point.y - sourceSide / 2,
            width: sourceSide, height: sourceSide)

        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(roundedRect: loupeRect, xRadius: 6, yRadius: 6).addClip()
        NSGraphicsContext.current?.imageInterpolation = .none
        frozenNSImage.draw(in: loupeRect, from: sourceRect, operation: .copy, fraction: 1)
        NSGraphicsContext.current?.restoreGraphicsState()

        // Crosshair in the loupe + border.
        NSColor.white.withAlphaComponent(0.8).setStroke()
        let cross = NSBezierPath()
        cross.move(to: NSPoint(x: loupeRect.midX, y: loupeRect.minY))
        cross.line(to: NSPoint(x: loupeRect.midX, y: loupeRect.maxY))
        cross.move(to: NSPoint(x: loupeRect.minX, y: loupeRect.midY))
        cross.line(to: NSPoint(x: loupeRect.maxX, y: loupeRect.midY))
        cross.lineWidth = 1
        cross.stroke()
        let border = NSBezierPath(roundedRect: loupeRect, xRadius: 6, yRadius: 6)
        border.lineWidth = 1.5
        border.stroke()
    }
}
