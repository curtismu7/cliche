import AppKit
import Carbon.HIToolbox
import ClipShotKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()

    private var store: HistoryStore!
    private var monitor: ClipboardMonitor!
    private let captureService = CaptureService()
    private let hotkeys = HotkeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipShot", isDirectory: true)
        store = HistoryStore(directory: appSupport)
        monitor = ClipboardMonitor(store: store)
        monitor.start()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "scissors.badge.ellipsis",
            accessibilityDescription: "ClipShot")
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.target = self

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: HistoryView(
                store: store,
                onCopy: { [weak self] item in self?.monitor.copyToPasteboard(item) },
                onCapture: { [weak self] mode in self?.capture(mode) },
                onQuit: { NSApp.terminate(nil) }
            ))

        // ⌃⌥⌘C toggle panel, ⌃⌥⌘4 region, ⌃⌥⌘5 window
        hotkeys.register(keyCode: kVK_ANSI_C) { [weak self] in self?.togglePopover() }
        hotkeys.register(keyCode: kVK_ANSI_4) { [weak self] in self?.capture(.region) }
        hotkeys.register(keyCode: kVK_ANSI_5) { [weak self] in self?.capture(.window) }
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func capture(_ mode: CaptureMode) {
        // Close the panel first so it isn't part of the screenshot.
        popover.performClose(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [captureService] in
            captureService.capture(mode)
        }
    }
}
