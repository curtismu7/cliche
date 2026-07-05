import AppKit
import SwiftUI

/// Maccy-style floating clipboard list: summoned by hotkey at the mouse
/// position, keyboard-first (search is focused), closes on Esc or when it
/// loses focus.
enum FloatingListWindow {
    private static var panel: NSPanel?
    private static var keyMonitor: Any?
    private static var focusObserver: NSObjectProtocol?

    static var isVisible: Bool { panel != nil }

    static func show<Content: View>(content: Content) {
        close()

        let size = NSSize(width: 340, height: 490)
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
        listPanel.appearance = NSAppearance(named: .aqua)
        listPanel.contentView = NSHostingView(
            rootView: content
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.black.opacity(0.2))))

        // Appear at the mouse, clamped onto the screen.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: min(max(mouse.x - size.width / 2, visible.minX + 8),
                   visible.maxX - size.width - 8),
            y: min(max(mouse.y - size.height, visible.minY + 8),
                   visible.maxY - size.height - 8))
        listPanel.setFrameOrigin(origin)
        listPanel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel = listPanel

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
            // Don't close under our own sheets (settings/help/edit).
            DispatchQueue.main.async {
                let newKey = NSApp.keyWindow
                if newKey == nil || (newKey !== panel && newKey?.isSheet != true) {
                    close()
                }
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
    }
}
