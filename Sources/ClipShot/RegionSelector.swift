import AppKit

/// Full-screen crosshair overlay for picking a capture region: dims the
/// screen, drag to select, Esc cancels. Completion delivers the chosen
/// screen and the selection in display coordinates (points, top-left origin,
/// ready for ScreenCaptureKit's sourceRect).
final class RegionSelector {
    private static var active: RegionSelector?

    private var window: NSWindow?
    private let completion: ((screen: NSScreen, rect: CGRect)?) -> Void

    static func begin(completion: @escaping ((screen: NSScreen, rect: CGRect)?) -> Void) {
        guard active == nil else {
            completion(nil)
            return
        }
        let selector = RegionSelector(completion: completion)
        active = selector
        selector.show()
    }

    private init(completion: @escaping ((screen: NSScreen, rect: CGRect)?) -> Void) {
        self.completion = completion
    }

    private func show() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens[0]

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false)
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.isReleasedWhenClosed = false

        let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.onFinish = { [weak self] localRect in
            self?.finish(screen: screen, localRect: localRect)
        }
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(view)
        self.window = window
    }

    private func finish(screen: NSScreen, localRect: CGRect?) {
        window?.orderOut(nil)
        window = nil
        Self.active = nil
        guard let rect = localRect, rect.width >= 2, rect.height >= 2 else {
            completion(nil)
            return
        }
        // View coordinates are bottom-left origin; ScreenCaptureKit wants
        // top-left origin relative to the display.
        let flipped = CGRect(
            x: rect.minX,
            y: screen.frame.height - rect.maxY,
            width: rect.width,
            height: rect.height)
        completion((screen, flipped))
    }
}

private final class SelectionView: NSView {
    var onFinish: ((CGRect?) -> Void)?

    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?

    private var selectionRect: NSRect? {
        guard let start = startPoint, let current = currentPoint else { return nil }
        return NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(start.x - current.x),
            height: abs(start.y - current.y))
    }

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        onFinish?(selectionRect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {  // Esc
            onFinish?(nil)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.25).setFill()
        bounds.fill()
        if let rect = selectionRect {
            // Punch a clear hole where the selection is.
            NSColor.clear.setFill()
            rect.fill(using: .copy)
            NSColor.white.setStroke()
            let outline = NSBezierPath(rect: rect)
            outline.lineWidth = 1
            outline.stroke()
        }
    }
}
