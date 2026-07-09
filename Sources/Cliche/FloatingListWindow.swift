import AppKit
import SwiftUI

/// Maccy-style floating panel: summoned from the menu bar or a hotkey,
/// keyboard-first (search is focused), closes on Esc or when it loses focus.
enum FloatingListWindow {
    private static var panel: NSPanel?
    private static var keyMonitor: Any?
    private static var focusObserver: NSObjectProtocol?
    private static var shownLayout: PanelLayout?

    static var isVisible: Bool { panel != nil }

    static func isShowing(layout: PanelLayout) -> Bool {
        panel != nil && shownLayout == layout
    }

    static func show<Content: View>(
        content: Content,
        size: NSSize,
        appearance: NSAppearance,
        layout: PanelLayout,
        anchor: NSView? = nil
    ) {
        close()

        let listPanel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        listPanel.level = .floating
        listPanel.backgroundColor = .clear
        listPanel.isOpaque = false
        listPanel.hasShadow = true
        listPanel.isReleasedWhenClosed = false
        listPanel.isMovableByWindowBackground = true
        listPanel.appearance = appearance
        listPanel.contentView = NSHostingView(
            rootView: content
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.2))))

        let origin = panelOrigin(size: size, anchor: anchor)
        listPanel.setFrameOrigin(origin)
        listPanel.orderFrontRegardless()
        listPanel.makeKey()
        panel = listPanel
        shownLayout = layout

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53, panel?.isKeyWindow == true {  // Esc
                close()
                return nil
            }
            return event
        }
        focusObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: listPanel, queue: .main
        ) { _ in
            DispatchQueue.main.async {
                let newKey = NSApp.keyWindow
                if newKey === panel { return }
                if newKey?.isSheet == true { return }
                if SettingsWindow.isVisible { return }
                close()
            }
        }
    }

    static func close() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        if let focusObserver {
            NotificationCenter.default.removeObserver(focusObserver)
        }
        focusObserver = nil
        panel?.orderOut(nil)
        panel = nil
        shownLayout = nil
    }

    /// Below the menu-bar icon when anchored; otherwise at the mouse.
    private static func panelOrigin(size: NSSize, anchor: NSView?) -> NSPoint {
        if let anchor, let window = anchor.window {
            let buttonRect = anchor.convert(anchor.bounds, to: nil)
            let screenRect = window.convertToScreen(buttonRect)
            let screen = window.screen ?? NSScreen.main ?? NSScreen.screens[0]
            let visible = screen.visibleFrame
            let x = min(
                max(screenRect.midX - size.width / 2, visible.minX + 8),
                visible.maxX - size.width - 8)
            let y = min(
                max(screenRect.minY - size.height - 4, visible.minY + 8),
                visible.maxY - size.height - 8)
            return NSPoint(x: x, y: y)
        }

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        return NSPoint(
            x: min(max(mouse.x - size.width / 2, visible.minX + 8),
                   visible.maxX - size.width - 8),
            y: min(max(mouse.y - size.height, visible.minY + 8),
                   visible.maxY - size.height - 8))
    }
}
