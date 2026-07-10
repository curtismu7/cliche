import AppKit
import ClicheKit
import SwiftUI

/// Standalone settings window. A sheet inside the transient menu-bar popover or
/// the focus-closing floating panel dismisses instantly; a real window stays up.
enum SettingsWindow {
    private static var window: NSWindow?
    private static var delegate: WindowDelegate?

    static var isVisible: Bool { window != nil }

    static var placementWindow: NSWindow? { window }

    static func show(
        settings: AppSettings,
        ignoreRulesURL: URL,
        historyStore: HistoryStore?
    ) {
        FloatingListWindow.suspendAutoClose = true

        if let window {
            let screen = window.screen ?? NSScreen.main ?? NSScreen.screens[0]
            let height = PanelMetrics.maxPanelHeight(on: screen)
            window.setContentSize(NSSize(width: 440, height: height))
            placeBesideOnboardingIfNeeded(settingsWindow: window, on: screen)
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
            contentRect: NSRect(x: 0, y: 0, width: 440, height: height),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false)
        settingsWindow.title = "Cliché Settings"
        settingsWindow.minSize = NSSize(width: 400, height: PanelMetrics.minHeight)
        settingsWindow.isReleasedWhenClosed = false
        settingsWindow.canHide = false
        settingsWindow.contentViewController = NSHostingController(rootView: view)

        let windowDelegate = WindowDelegate { close() }
        settingsWindow.delegate = windowDelegate
        delegate = windowDelegate

        window = settingsWindow
        placeBesideOnboardingIfNeeded(settingsWindow: settingsWindow, on: screen)
        settingsWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func placeBesideOnboardingIfNeeded(settingsWindow: NSWindow, on screen: NSScreen) {
        guard let welcome = OnboardingWindow.placementWindow, welcome.isVisible else {
            WindowPlacement.center(settingsWindow, on: screen)
            return
        }
        WindowPlacement.placeSideBySide(welcome, settingsWindow, on: screen)
        welcome.orderFront(nil)
    }

    static func close() {
        window?.orderOut(nil)
        window = nil
        delegate = nil
        if !OnboardingWindow.isVisible {
            FloatingListWindow.suspendAutoClose = false
        }
    }

    private final class WindowDelegate: NSObject, NSWindowDelegate {
        let onClose: () -> Void
        init(onClose: @escaping () -> Void) { self.onClose = onClose }
        func windowShouldClose(_ sender: NSWindow) -> Bool { true }
        func windowWillClose(_ notification: Notification) { onClose() }
    }
}
