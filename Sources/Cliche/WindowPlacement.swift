import AppKit

/// Positions two windows side by side, centered as a pair on the given screen.
enum WindowPlacement {
    static func placeSideBySide(_ leading: NSWindow, _ trailing: NSWindow, on screen: NSScreen? = nil) {
        let screen = screen ?? leading.screen ?? trailing.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let gap: CGFloat = 16
        let pairWidth = leading.frame.width + trailing.frame.width + gap
        let height = min(
            max(leading.frame.height, trailing.frame.height),
            visible.height - 24)
        var originX = visible.midX - pairWidth / 2
        originX = max(visible.minX + 8, min(originX, visible.maxX - pairWidth - 8))
        let originY = visible.midY - height / 2

        leading.setFrame(
            NSRect(x: originX, y: originY, width: leading.frame.width, height: height),
            display: true)
        trailing.setFrame(
            NSRect(
                x: originX + leading.frame.width + gap,
                y: originY,
                width: trailing.frame.width,
                height: height),
            display: true)
    }

    static func center(_ window: NSWindow, on screen: NSScreen? = nil) {
        let screen = screen ?? window.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        var frame = window.frame
        frame.origin.x = visible.midX - frame.width / 2
        frame.origin.y = visible.midY - frame.height / 2
        frame.origin.x = max(visible.minX + 8, min(frame.origin.x, visible.maxX - frame.width - 8))
        frame.origin.y = max(visible.minY + 8, min(frame.origin.y, visible.maxY - frame.height - 8))
        window.setFrame(frame, display: true)
    }
}
