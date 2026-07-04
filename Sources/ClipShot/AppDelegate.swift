import AppKit
import Carbon.HIToolbox
import ClipShotKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()

    private var store: HistoryStore!
    private var capturesStore: CapturesStore!
    private var monitor: ClipboardMonitor!
    private let captureService = CaptureService()
    private let ocrService = OCRService()
    private let hotkeys = HotkeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipShot", isDirectory: true)
        let ignoreRulesURL = appSupport.appendingPathComponent("ignore-rules.json")

        store = HistoryStore(directory: appSupport)
        capturesStore = CapturesStore(directory: appSupport)
        monitor = ClipboardMonitor(
            store: store,
            ignoreRules: IgnoreRules.load(from: ignoreRulesURL))
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
                capturesStore: capturesStore,
                ignoreRulesURL: ignoreRulesURL,
                onCopy: { [weak self] item in
                    self?.monitor.copyToPasteboard(item)
                    self?.popover.performClose(nil)
                },
                onCapture: { [weak self] mode in self?.capture(mode) },
                onCaptureText: { [weak self] in self?.captureText() },
                onQuit: { NSApp.terminate(nil) }
            ))

        // ⌃⌥⌘C toggle panel, ⌃⌥⌘4 region, ⌃⌥⌘5 window, ⌃⌥⌘6 OCR
        hotkeys.register(keyCode: kVK_ANSI_C) { [weak self] in self?.togglePopover() }
        hotkeys.register(keyCode: kVK_ANSI_4) { [weak self] in self?.capture(.region) }
        hotkeys.register(keyCode: kVK_ANSI_5) { [weak self] in self?.capture(.window) }
        hotkeys.register(keyCode: kVK_ANSI_6) { [weak self] in self?.captureText() }
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func captureText() {
        popover.performClose(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [ocrService] in
            ocrService.captureText()
        }
    }

    private func capture(_ mode: CaptureMode) {
        // Close the panel first so it isn't part of the screenshot.
        popover.performClose(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            [captureService, capturesStore] in
            captureService.capture(mode) { url in
                capturesStore?.add(path: url.path)
            }
        }
    }
}
