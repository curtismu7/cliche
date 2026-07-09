import AppKit
import ClicheKit
import SwiftUI

/// Standalone settings window. A sheet inside the transient menu-bar popover or
/// the focus-closing floating panel dismisses instantly; a real window stays up.
enum SettingsWindow {
    private static var window: NSWindow?
    private static var delegate: WindowDelegate?

    static var isVisible: Bool { window != nil }

    static func show(
        settings: AppSettings,
        ignoreRulesURL: URL,
        historyStore: HistoryStore?
    ) {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView(
            settings: settings,
            ignoreRulesURL: ignoreRulesURL,
            historyStore: historyStore,
            onDone: { close() })

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let height = PanelMetrics.maxPanelHeight(on: screen)

        let settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: height),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false)
        settingsWindow.title = "Cliché Settings"
        settingsWindow.minSize = NSSize(width: 360, height: PanelMetrics.minHeight)
        settingsWindow.isReleasedWhenClosed = false
        settingsWindow.contentViewController = NSHostingController(rootView: view)

        let windowDelegate = WindowDelegate { close() }
        settingsWindow.delegate = windowDelegate
        delegate = windowDelegate

        settingsWindow.center()
        settingsWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = settingsWindow
    }

    static func close() {
        window?.orderOut(nil)
        window = nil
        delegate = nil
    }

    private final class WindowDelegate: NSObject, NSWindowDelegate {
        let onClose: () -> Void
        init(onClose: @escaping () -> Void) { self.onClose = onClose }
        func windowWillClose(_ notification: Notification) { onClose() }
    }
}
