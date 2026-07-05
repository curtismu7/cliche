import AppKit
import Carbon.HIToolbox
import ClipShotKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()

    private var store: HistoryStore!
    private var capturesStore: CapturesStore!
    private var snippetsStore: SnippetsStore!
    private let settings = AppSettings()
    private var monitor: ClipboardMonitor!
    /// The app that was frontmost when the panel opened — the paste target.
    private var previousApp: NSRunningApplication?
    /// Previous pick for the contrast checker.
    private var lastPickedColor: NSColor?

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
        snippetsStore = SnippetsStore(directory: appSupport)
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
                snippetsStore: snippetsStore,
                settings: settings,
                ignoreRulesURL: ignoreRulesURL,
                onCopy: { [weak self] item in
                    self?.monitor.copyToPasteboard(item)
                    self?.popover.performClose(nil)
                },
                onPaste: { [weak self] item in
                    self?.paste { self?.monitor.copyToPasteboard(item) }
                },
                onCopySnippet: { [weak self] snippet in
                    guard let self else { return }
                    self.setPasteboardString(self.snippetsStore.render(snippet))
                    self.popover.performClose(nil)
                },
                onPasteSnippet: { [weak self] snippet in
                    guard let self else { return }
                    // Render before paste() replaces the clipboard %CLIPBOARD%
                    // would otherwise read from.
                    let rendered = self.snippetsStore.render(snippet)
                    self.paste { self.setPasteboardString(rendered) }
                },
                onCapture: { [weak self] mode in self?.capture(mode) },
                onCaptureText: { [weak self] in self?.captureText() },
                onPickColor: { [weak self] in self?.pickColor() },
                onRepeatRegion: { [weak self] in
                    self?.popover.performClose(nil)
                    self?.repeatLastRegion()
                },
                onQuit: { NSApp.terminate(nil) }
            ))

        // ⌃⌥⌘: C panel, 4 region, 5 window, 6 OCR, R repeat last region
        hotkeys.register(keyCode: kVK_ANSI_C) { [weak self] in self?.togglePopover() }
        hotkeys.register(keyCode: kVK_ANSI_4) { [weak self] in self?.capture(.region) }
        hotkeys.register(keyCode: kVK_ANSI_5) { [weak self] in self?.capture(.window) }
        hotkeys.register(keyCode: kVK_ANSI_6) { [weak self] in self?.captureText() }
        hotkeys.register(keyCode: kVK_ANSI_R) { [weak self] in self?.repeatLastRegion() }
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            previousApp = NSWorkspace.shared.frontmostApplication
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: Paste

    /// Puts content on the clipboard, then synthesizes ⌘V in the app that was
    /// frontmost before the panel opened. Requests the Accessibility
    /// permission lazily on first use.
    private func paste(_ populateClipboard: () -> Void) {
        populateClipboard()
        popover.performClose(nil)
        guard PasteService.isTrusted else {
            PasteService.requestTrust()
            return
        }
        previousApp?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            PasteService.synthesizePaste()
        }
    }

    private func setPasteboardString(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: Capture

    private func capture(_ mode: CaptureMode) {
        // Close the panel first so it isn't part of the screenshot.
        popover.performClose(nil)
        let screen = Self.screenUnderMouse()
        CountdownPanel.show(seconds: settings.timerSeconds, on: screen) { [weak self] in
            self?.performCapture(mode, on: screen)
        }
    }

    private func performCapture(_ mode: CaptureMode, on screen: NSScreen) {
        switch mode {
        case .fullScreen:
            captureWithEngine(screen: screen, rect: nil, cliFallback: .fullScreen)
        case .region:
            startRegionCapture(on: screen)
        case .window:
            // ScreenCaptureKit has no window-picker UI; keep the native one.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.captureWithCLI(.window)
            }
        }
    }

    /// Region capture: freeze the display first, select on the frozen frame,
    /// then crop the selection out of it — instant and exactly what was seen.
    private func startRegionCapture(on screen: NSScreen) {
        guard let displayID = screen.displayID else {
            captureWithCLI(.region)
            return
        }
        let scale = screen.backingScaleFactor
        Task { @MainActor in
            do {
                let frozen = try await ScreenshotEngine.captureImage(
                    displayID: displayID, scale: scale,
                    showsCursor: settings.showCursor)
                RegionSelector.begin(frozen: frozen, on: screen) { [weak self] pixelRect in
                    guard let self, let pixelRect else { return }
                    self.settings.lastRegion = (pixelRect, displayID)
                    if let cropped = frozen.cropping(to: pixelRect) {
                        self.deliver(cropped)
                    }
                }
            } catch {
                NSLog("ClipShot: freeze capture failed (\(error)); using CLI")
                self.captureWithCLI(.region)
            }
        }
    }

    /// ⌃⌥⌘R — recapture the exact previous region with no UI.
    private func repeatLastRegion() {
        guard let last = settings.lastRegion else {
            InfoHUD.show("No previous region — use ⌃⌥⌘4 first")
            return
        }
        let screen = NSScreen.screens.first { $0.displayID == last.displayID }
            ?? Self.screenUnderMouse()
        Task { @MainActor in
            do {
                let frozen = try await ScreenshotEngine.captureImage(
                    displayID: last.displayID, scale: screen.backingScaleFactor,
                    showsCursor: settings.showCursor)
                if let cropped = frozen.cropping(to: last.rect) {
                    self.deliver(cropped)
                }
            } catch {
                NSLog("ClipShot: repeat-area capture failed: \(error)")
            }
        }
    }

    private func captureWithEngine(screen: NSScreen, rect: CGRect?, cliFallback: CaptureMode) {
        guard let displayID = screen.displayID else {
            captureWithCLI(cliFallback)
            return
        }
        let scale = screen.backingScaleFactor
        Task { @MainActor in
            do {
                let image = try await ScreenshotEngine.captureImage(
                    displayID: displayID, sourceRect: rect, scale: scale,
                    showsCursor: settings.showCursor)
                self.deliver(image)
            } catch {
                NSLog("ClipShot: ScreenCaptureKit failed (\(error)); using screencapture CLI")
                self.captureWithCLI(cliFallback)
            }
        }
    }

    private func captureWithCLI(_ mode: CaptureMode) {
        captureService.capture(
            mode,
            format: settings.captureFormat,
            copyToClipboard: settings.copyCapturesToClipboard,
            showCursor: settings.showCursor,
            windowShadow: settings.windowShadow
        ) { [weak self] url in
            self?.capturesStore.add(path: url.path)
            let image = NSImage(contentsOf: url)?
                .cgImage(forProposedRect: nil, context: nil, hints: nil)
            self?.showOverlay(for: url, image: image)
        }
    }

    /// Common post-capture step: file + clipboard already handled; index it,
    /// scan for QR codes, and show the Quick Access Overlay.
    private func deliver(_ image: CGImage) {
        guard let url = CaptureDelivery.deliver(
            image,
            format: settings.captureFormat,
            copyToClipboard: settings.copyCapturesToClipboard)
        else { return }
        capturesStore.add(path: url.path)
        showOverlay(for: url, image: image)
    }

    private func showOverlay(for url: URL, image: CGImage?) {
        let qrLink = image.flatMap(QRDetector.firstQRPayload(in:))
        CaptureOverlay.show(fileURL: url, qrLink: qrLink) {
            AnnotationEditor.open(fileURL: $0)
        }
    }

    // MARK: Tools

    /// Native magnifier loupe; hex code to clipboard. Consecutive picks also
    /// report the WCAG contrast ratio between the last two colors.
    private func pickColor() {
        popover.performClose(nil)
        NSColorSampler().show { [weak self] color in
            guard let self, let color, let hex = ColorUtil.hexString(color) else { return }
            self.setPasteboardString(hex)
            if let previous = self.lastPickedColor,
               let previousHex = ColorUtil.hexString(previous),
               let ratio = ColorUtil.contrastRatio(previous, color) {
                InfoHUD.show(String(
                    format: "%@ ▸ %@  contrast %.1f:1 — %@",
                    previousHex, hex, ratio, ColorUtil.wcagVerdict(ratio: ratio)))
            } else {
                InfoHUD.show("\(hex) copied — pick another color for contrast")
            }
            self.lastPickedColor = color
        }
    }

    private func captureText() {
        popover.performClose(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [ocrService] in
            ocrService.captureText()
        }
    }

    private static func screenUnderMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens[0]
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
            .uint32Value
    }
}
