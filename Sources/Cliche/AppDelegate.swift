import AppKit
import Carbon.HIToolbox
import ClicheKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var clipboardItem: NSStatusItem?
    private var captureItem: NSStatusItem?
    private let popover = NSPopover()          // full or clipboard-only panel
    private let capturePopover = NSPopover()   // split mode: capture panel
    private var ignoreRulesURL: URL!

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
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleURLEvent(_:with:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL))
        let supportBase = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appSupport = supportBase.appendingPathComponent("Cliche", isDirectory: true)
        // One-time migration from the app's previous name.
        let legacySupport = supportBase.appendingPathComponent("ClipShot", isDirectory: true)
        if !FileManager.default.fileExists(atPath: appSupport.path),
           FileManager.default.fileExists(atPath: legacySupport.path) {
            try? FileManager.default.moveItem(at: legacySupport, to: appSupport)
        }
        ignoreRulesURL = appSupport.appendingPathComponent("ignore-rules.json")

        store = HistoryStore(
            directory: appSupport,
            maxTexts: settings.maxTextEntries,
            maxImages: settings.maxImageEntries)
        capturesStore = CapturesStore(directory: appSupport)
        snippetsStore = SnippetsStore(directory: appSupport)
        monitor = ClipboardMonitor(
            store: store,
            ignoreRules: IgnoreRules.load(from: ignoreRulesURL))
        monitor.start()

        popover.behavior = .transient
        capturePopover.behavior = .transient
        // White panels regardless of system dark mode.
        popover.appearance = NSAppearance(named: .aqua)
        capturePopover.appearance = NSAppearance(named: .aqua)
        configureMenuBar()
        NotificationCenter.default.addObserver(
            forName: AppSettings.menuBarStyleChanged, object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.closeAllPopovers()
                self?.configureMenuBar()
            }
        }

        NotificationCenter.default.addObserver(
            forName: AppSettings.historyLimitsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.store.setLimits(
                maxTexts: self.settings.maxTextEntries,
                maxImages: self.settings.maxImageEntries)
        }

        registerHotkeys()
        NotificationCenter.default.addObserver(
            forName: AppSettings.hotkeysChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.registerHotkeys()
        }
    }

    /// (Re)binds every global hotkey from settings.
    private func registerHotkeys() {
        hotkeys.unregisterAll()
        for action in HotkeyAction.allCases {
            let combo = settings.combo(for: action)
            hotkeys.register(
                keyCode: Int(combo.keyCode), modifiers: combo.carbonModifiers
            ) { [weak self] in
                self?.perform(action)
            }
        }
    }

    private func perform(_ action: HotkeyAction) {
        switch action {
        case .togglePanel: togglePopover()
        case .captureRegion: capture(.region)
        case .captureWindow: capture(.window)
        case .captureText: captureText()
        case .repeatRegion: repeatLastRegion()
        case .floatingList: toggleFloatingList()
        case .allInOne: startAllInOne()
        }
    }

    /// cliche:// automation entry point (Raycast, Shortcuts, `open`).
    @objc private func handleURLEvent(
        _ event: NSAppleEventDescriptor, with reply: NSAppleEventDescriptor
    ) {
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: string),
              let command = URLCommand.parse(url)
        else {
            NSSound.beep()
            return
        }
        switch command {
        case .captureRegion: capture(.region)
        case .captureWindow: capture(.window)
        case .captureFullScreen: capture(.fullScreen)
        case .allInOne: startAllInOne()
        case .ocr: captureText()
        case .repeatRegion: repeatLastRegion()
        case .panel: togglePopover()
        }
    }

    /// Maccy-style floating clipboard list at the mouse position.
    private func toggleFloatingList() {
        if FloatingListWindow.isVisible {
            FloatingListWindow.close()
            return
        }
        closeAllPopovers()
        previousApp = NSWorkspace.shared.frontmostApplication
        FloatingListWindow.show(content: makeHistoryView(layout: .clipboardOnly))
    }

    // MARK: Menu bar

    /// Builds the status item(s) for the current menu bar style. Called at
    /// launch and whenever the setting changes.
    private func configureMenuBar() {
        [clipboardItem, captureItem].compactMap { $0 }
            .forEach(NSStatusBar.system.removeStatusItem)
        clipboardItem = nil
        captureItem = nil

        // Explicit contentSize matching each HistoryView frame — without it
        // NSPopover under-allocates and clips the top of the SwiftUI content.
        switch settings.menuBarStyle {
        case .combined:
            popover.contentViewController = NSHostingController(
                rootView: makeHistoryView(layout: .full))
            popover.contentSize = NSSize(width: 340, height: 530)
            clipboardItem = makeStatusItem(
                symbol: "scissors.badge.ellipsis", description: "Cliché",
                action: #selector(togglePopover))
        case .split:
            popover.contentViewController = NSHostingController(
                rootView: makeHistoryView(layout: .clipboardOnly))
            popover.contentSize = NSSize(width: 340, height: 490)
            capturePopover.contentViewController = NSHostingController(
                rootView: makeHistoryView(layout: .captureOnly))
            capturePopover.contentSize = NSSize(width: 340, height: 455)
            // Items added later sit further left; add capture first so the
            // clipboard icon stays in the accustomed spot.
            captureItem = makeStatusItem(
                symbol: "camera.viewfinder", description: "Cliché Image Capture",
                action: #selector(toggleCapturePopover))
            clipboardItem = makeStatusItem(
                symbol: "doc.on.clipboard", description: "Cliché Clipboard",
                action: #selector(togglePopover))
        }
    }

    private func makeStatusItem(
        symbol: String, description: String, action: Selector
    ) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: symbol, accessibilityDescription: description)
        item.button?.action = action
        item.button?.target = self
        return item
    }

    private func makeHistoryView(layout: PanelLayout) -> HistoryView {
        HistoryView(
            layout: layout,
            store: store,
            capturesStore: capturesStore,
            snippetsStore: snippetsStore,
            settings: settings,
            ignoreRulesURL: ignoreRulesURL,
            onCopy: { [weak self] item in
                self?.monitor.copyToPasteboard(item)
                self?.popover.performClose(nil)
                FloatingListWindow.close()
            },
            onPaste: { [weak self] item in
                self?.paste { self?.monitor.copyToPasteboard(item) }
            },
            onCopySnippet: { [weak self] snippet in
                guard let self else { return }
                self.setPasteboardString(self.snippetsStore.render(snippet))
                self.popover.performClose(nil)
                FloatingListWindow.close()
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
            onAllInOne: { [weak self] in self?.startAllInOne() },
            onPickColor: { [weak self] in self?.pickColor() },
            onRepeatRegion: { [weak self] in
                self?.closeAllPopovers()
                self?.repeatLastRegion()
            },
            onRuler: { [weak self] in self?.startRuler() },
            onScrollCapture: { [weak self] in self?.startScrollingCapture() },
            onRecord: { [weak self] in self?.startRecording() },
            onQuit: { NSApp.terminate(nil) }
        )
    }

    private func closeAllPopovers() {
        popover.performClose(nil)
        capturePopover.performClose(nil)
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = clipboardItem?.button {
            previousApp = NSWorkspace.shared.frontmostApplication
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc private func toggleCapturePopover() {
        if capturePopover.isShown {
            capturePopover.performClose(nil)
        } else if let button = captureItem?.button {
            capturePopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    // MARK: Paste

    /// Puts content on the clipboard, then synthesizes ⌘V in the app that was
    /// frontmost before the panel opened. Requests the Accessibility
    /// permission lazily on first use.
    private func paste(_ populateClipboard: () -> Void) {
        populateClipboard()
        popover.performClose(nil)
        FloatingListWindow.close()
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
        // Close the panels first so they aren't part of the screenshot.
        closeAllPopovers()
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
                NSLog("Cliche: freeze capture failed (\(error)); using CLI")
                self.captureWithCLI(.region)
            }
        }
    }

    /// ⌃⌥⌘3 — frozen overlay with the Region/Window/Full Screen/OCR strip.
    private func startAllInOne() {
        closeAllPopovers()
        let screen = Self.screenUnderMouse()
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
                RegionSelector.begin(
                    frozen: frozen, on: screen, allInOne: .region,
                    onSelect: { [weak self] pixelRect, mode in
                        guard let self, let cropped = frozen.cropping(to: pixelRect)
                        else { return }
                        switch mode {
                        case .region:
                            self.settings.lastRegion = (pixelRect, displayID)
                            self.deliver(cropped)
                        case .ocr:
                            let text = (try? OCRService.recognizeText(in: cropped)) ?? ""
                            if text.isEmpty {
                                NSSound.beep()
                            } else {
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.setString(text, forType: .string)
                                InfoHUD.show("Text copied")
                            }
                        case .window, .fullScreen:
                            break  // not in-place modes; routed via onSwitchAway
                        }
                    },
                    onSwitchAway: { [weak self] mode in
                        guard let self else { return }
                        switch mode {
                        case .window: self.performCapture(.window, on: screen)
                        case .fullScreen:
                            // Slight delay so the overlay is fully gone.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                self.performCapture(.fullScreen, on: screen)
                            }
                        case .region, .ocr: break
                        }
                    },
                    onCancel: { })
            } catch {
                NSLog("Cliche: all-in-one freeze failed (\(error)); using CLI region")
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
                NSLog("Cliche: repeat-area capture failed: \(error)")
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
                NSLog("Cliche: ScreenCaptureKit failed (\(error)); using screencapture CLI")
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
        closeAllPopovers()
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

    /// Pixel ruler over a frozen frame of the current display.
    private func startRuler() {
        closeAllPopovers()
        let screen = Self.screenUnderMouse()
        guard let displayID = screen.displayID else { return }
        Task { @MainActor in
            if let frozen = try? await ScreenshotEngine.captureImage(
                displayID: displayID, scale: screen.backingScaleFactor) {
                RulerOverlay.begin(frozen: frozen, on: screen)
            } else {
                InfoHUD.show("Ruler needs the Screen Recording permission")
            }
        }
    }

    /// Panoramic capture: select a region, scroll the content, Done stitches.
    private func startScrollingCapture() {
        closeAllPopovers()
        let screen = Self.screenUnderMouse()
        guard let displayID = screen.displayID else { return }
        let scale = screen.backingScaleFactor
        Task { @MainActor in
            guard let frozen = try? await ScreenshotEngine.captureImage(
                displayID: displayID, scale: scale) else {
                InfoHUD.show("Scrolling capture needs the Screen Recording permission")
                return
            }
            RegionSelector.begin(frozen: frozen, on: screen) { [weak self] pixelRect in
                guard let self, let pixelRect else { return }
                ScrollingCapture.begin(
                    displayID: displayID, pixelRect: pixelRect, scale: scale,
                    showsCursor: false, on: screen
                ) { stitched in
                    self.deliver(stitched)
                }
            }
        }
    }

    /// Region recording to MP4 (optional GIF), controlled by a floating HUD.
    private func startRecording() {
        closeAllPopovers()
        guard !RecordingController.isRecording else {
            InfoHUD.show("Already recording — use the Stop button")
            return
        }
        let screen = Self.screenUnderMouse()
        guard let displayID = screen.displayID else { return }
        let scale = screen.backingScaleFactor
        Task { @MainActor in
            guard let frozen = try? await ScreenshotEngine.captureImage(
                displayID: displayID, scale: scale) else {
                InfoHUD.show("Recording needs the Screen Recording permission")
                return
            }
            RegionSelector.begin(frozen: frozen, on: screen) { [weak self] pixelRect in
                guard let self, let pixelRect else { return }
                RecordingController.begin(
                    displayID: displayID, pixelRect: pixelRect, scale: scale,
                    showsCursor: self.settings.showCursor, on: screen
                ) { url in
                    self.capturesStore.add(path: url.path)
                    InfoHUD.show("Recording saved to Desktop")
                }
            }
        }
    }

    private func captureText() {
        closeAllPopovers()
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
