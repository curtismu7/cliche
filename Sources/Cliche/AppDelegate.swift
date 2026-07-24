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

    /// Locked when the panel opens — ⌘1–9 paste back here, not the panel.
    private var pasteTargetApp: NSRunningApplication?

    private let captureService = CaptureService()
    private let ocrService = OCRService()
    private let hotkeys = HotkeyManager()

    func applicationWillFinishLaunching(_ notification: Notification) {
        // The launch-triggering GetURL event arrives BEFORE
        // applicationDidFinishLaunching — register here or cold-launch
        // cliche:// URLs are silently dropped.
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleURLEvent(_:with:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        applyPanelAppearance()
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
            forName: AppSettings.panelAppearanceChanged, object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.applyPanelAppearance()
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
        applyMacScreenshotShortcutSetting()
        FrontmostAppTracker.startMonitoring()
        ScreenCapturePermission.warnAboutDuplicateInstallsIfNeeded()
        NotificationCenter.default.addObserver(
            forName: AppSettings.hotkeysChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.registerHotkeys()
        }
        NotificationCenter.default.addObserver(
            forName: AppSettings.macScreenshotShortcutsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyMacScreenshotShortcutSetting()
        }
        NotificationCenter.default.addObserver(
            forName: PasteService.pasteRequiresAccessibilityNotification, object: nil, queue: .main
        ) { _ in
            InfoHUD.show(
                "Copied — click where you want to paste, then press ⌘V. "
                    + "Enable Accessibility in Cliché Settings for automatic paste.")
        }
        NotificationCenter.default.addObserver(
            forName: PasteService.pasteFailedNotification, object: nil, queue: .main
        ) { _ in
            InfoHUD.show("Could not find the app to paste into — click in the target field first.")
        }

        DispatchQueue.main.async { [weak self] in
            self?.presentOnboardingIfNeeded()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.presentOnboardingIfNeeded()
        }
    }

    /// Welcome stays up until the user clicks Get Started — closing the window
    /// or quitting to flip permissions in System Settings should not dismiss it.
    private func presentOnboardingIfNeeded() {
        guard !settings.hasCompletedOnboarding else { return }
        Task { @MainActor in
            OnboardingWindow.show(
                settings: settings,
                ignoreRulesURL: ignoreRulesURL,
                historyStore: store)
        }
    }

    private func applyMacScreenshotShortcutSetting() {
        MacScreenshotShortcuts.apply(
            disabled: settings.disableMacScreenshotShortcuts,
            settingsDefaults: UserDefaults.standard)
    }

    /// (Re)binds every global hotkey from settings.
    private func registerHotkeys() {
        hotkeys.unregisterAll()
        for action in HotkeyAction.allCases {
            let combo = settings.combo(for: action)
            hotkeys.register(
                keyCode: Int(combo.keyCode), modifiers: combo.carbonModifiers
            ) { [weak self] in
                // Carbon delivers hotkeys off the main thread; UI must run on main.
                DispatchQueue.main.async {
                    self?.perform(action)
                }
            }
        }
        registerQuickPasteHotkeys()
    }

    /// ⌃⌥1–9 paste a history slot without opening the panel (stay in the browser).
    private func registerQuickPasteHotkeys() {
        for slot in 1...9 {
            let keyCode = Int(kVK_ANSI_1) + (slot - 1)
            hotkeys.register(
                keyCode: keyCode,
                modifiers: UInt32(controlKey) | UInt32(optionKey)
            ) { [weak self] in
                DispatchQueue.main.async { self?.quickPaste(slot: slot) }
            }
        }
    }

    /// Paste history slot N into the app that is frontmost right now.
    private func quickPaste(slot: Int) {
        if FloatingListWindow.isVisible {
            return
        }
        FrontmostAppTracker.captureNow()
        pasteTargetApp = FrontmostAppTracker.lastApplication
        previousApp = pasteTargetApp
        let items = visibleTextItems()
        let index = slot - 1
        guard items.indices.contains(index) else { return }
        paste { monitor.copyToPasteboard(items[index]) }
    }

    /// Text items in panel order (pinned first) — matches ⌘1–9 in the list.
    private func visibleTextItems() -> [ClipItem] {
        let filtered = store.items
        let pinned = filtered.filter(\.pinned)
        let recent = filtered.filter { !$0.pinned }
        return (pinned + recent).filter {
            if case .text = $0.kind { return true }
            return false
        }
    }

    private func perform(_ action: HotkeyAction) {
        switch action {
        case .togglePanel: toggleFloatingList()
        case .toggleCapturePanel: toggleCapturePanel()
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
        case .permissions:
            Task { @MainActor in self.requestPermissions() }
        }
    }

    /// Registers Cliché with Screen Recording and Accessibility (macOS adds
    /// the app to each privacy list when these run).
    @MainActor
    private func requestPermissions() {
        _ = ScreenCapturePermission.requestAccessUserInitiated()
        _ = PasteService.requestTrust()
        if !ScreenCapturePermission.isGranted {
            ScreenCapturePermission.openSettings()
        }
        if !PasteService.isTrusted {
            PasteService.openSettings()
        }
    }

    /// Maccy-style floating clipboard list at the mouse position.
    private func toggleFloatingList() {
        let layout = PanelLayout.clipboardOnly
        if FloatingListWindow.isShowing(layout: layout) {
            FloatingListWindow.close()
            return
        }
        rememberPasteTarget()
        closeAllPopovers()
        showFloatingPanel(layout: layout, anchor: nil)
    }

    private func showFloatingPanel(layout: PanelLayout, anchor: NSView?) {
        let screen = anchor?.window?.screen ?? Self.screenUnderMouse()
        let size = panelSize(for: layout, on: screen)
        FloatingListWindow.show(
            content: makeHistoryView(layout: layout),
            size: size,
            appearance: PanelTheme.nsAppearance(settings),
            layout: layout,
            anchor: anchor)
    }

    private func applyPanelAppearance() {
        let appearance = PanelTheme.nsAppearance(settings)
        popover.appearance = appearance
        capturePopover.appearance = appearance
    }

    // MARK: Menu bar

    /// Builds the status item(s) for the current menu bar style. Called at
    /// launch and whenever the setting changes.
    private func configureMenuBar() {
        [clipboardItem, captureItem].compactMap { $0 }
            .forEach(NSStatusBar.system.removeStatusItem)
        clipboardItem = nil
        captureItem = nil

        guard settings.showMenuBarIcons else { return }

        // Explicit contentSize matching HistoryView — without it NSPopover
        // under-allocates and clips the top of the SwiftUI content.
        switch settings.menuBarStyle {
        case .combined:
            popover.contentViewController = NSHostingController(
                rootView: makeHistoryView(layout: .full))
            popover.contentSize = panelSize(for: .full)
            clipboardItem = makeStatusItem(
                symbol: "scissors.badge.ellipsis", description: "Cliché",
                action: #selector(togglePopover))
        case .split:
            popover.contentViewController = NSHostingController(
                rootView: makeHistoryView(layout: .clipboardOnly))
            popover.contentSize = panelSize(for: .clipboardOnly)
            capturePopover.contentViewController = NSHostingController(
                rootView: makeHistoryView(layout: .captureOnly))
            capturePopover.contentSize = panelSize(for: .captureOnly)
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
        item.button?.image = Self.menuBarImage(symbol: symbol, description: description)
        item.button?.imagePosition = .imageOnly
        item.button?.action = action
        item.button?.target = self
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        if #available(macOS 13.0, *) {
            item.isVisible = true
        }
        return item
    }

    /// Status bar icons must be template images at ~18pt or they render invisible.
    private static func menuBarImage(symbol: String, description: String) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        if let base = NSImage(systemSymbolName: symbol, accessibilityDescription: description) {
            let image = base.withSymbolConfiguration(config) ?? base
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            return image
        }
        if let bundled = bundledMenuBarIcon() { return bundled }
        return emptyMenuBarIcon()
    }

    /// Bundled PNG — reliable on every macOS version and menu bar theme.
    private static func bundledMenuBarIcon() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }

    private static func emptyMenuBarIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.isTemplate = true
        return image
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
            onMultiWindow: { [weak self] in self?.startMultiWindowCapture() },
            onRunPreset: { [weak self] preset in self?.runPreset(preset) },
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

    private func panelSize(for layout: PanelLayout, on screen: NSScreen? = nil) -> NSSize {
        let tab: PanelMetrics.Tab = layout == .captureOnly ? .captures : .clipboard
        return HistoryView.preferredPanelSize(
            layout: layout,
            tab: tab,
            items: store.items,
            captureCount: capturesStore.captures.count,
            snippetCount: snippetsStore.snippets.count,
            screen: screen)
    }

    private func refreshPopoverSize(_ popover: NSPopover, layout: PanelLayout, anchor: NSView?) {
        let screen = anchor?.window?.screen ?? NSScreen.main
        popover.contentSize = panelSize(for: layout, on: screen)
    }

    private func closeAllPopovers() {
        popover.performClose(nil)
        capturePopover.performClose(nil)
        FloatingListWindow.close()
    }

    @objc private func togglePopover() {
        let layout: PanelLayout = settings.menuBarStyle == .combined ? .full : .clipboardOnly
        if FloatingListWindow.isShowing(layout: layout) {
            FloatingListWindow.close()
            return
        }
        rememberPasteTarget()
        closeAllPopovers()
        if let button = clipboardItem?.button {
            showFloatingPanel(layout: layout, anchor: button)
        }
    }

    @objc private func toggleCapturePopover() {
        let layout = PanelLayout.captureOnly
        if FloatingListWindow.isShowing(layout: layout) {
            FloatingListWindow.close()
            return
        }
        closeAllPopovers()
        if let button = captureItem?.button {
            showFloatingPanel(layout: layout, anchor: button)
        }
    }

    /// ⌥2 — capture panel from the menu bar; falls back to cursor if the icon
    /// is hidden (notched MacBooks).
    private func toggleCapturePanel() {
        FloatingListWindow.close()
        let layout = PanelLayout.captureOnly
        if settings.menuBarStyle == .split {
            if let button = captureItem?.button, button.window != nil {
                showFloatingPanel(layout: layout, anchor: button)
            } else {
                showCapturePanelAtCursor()
            }
            return
        }
        if let button = clipboardItem?.button, button.window != nil {
            rememberPasteTarget()
            let panelLayout: PanelLayout = .full
            showFloatingPanel(layout: panelLayout, anchor: button)
        } else {
            showCapturePanelAtCursor()
        }
    }

    /// Floating capture panel when the menu bar icon is unavailable.
    private func showCapturePanelAtCursor() {
        closeAllPopovers()
        previousApp = NSWorkspace.shared.frontmostApplication
        showFloatingPanel(layout: .captureOnly, anchor: nil)
    }

    // MARK: Paste

    /// Puts content on the clipboard, then pastes into the field that was
    /// focused before the panel opened (HTML inputs, password fields, etc.).
    private func paste(_ populateClipboard: () -> Void) {
        previousApp = pasteTargetApp ?? FrontmostAppTracker.lastApplication ?? previousApp

        populateClipboard()
        popover.performClose(nil)
        FloatingListWindow.close()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            if let text = NSPasteboard.general.string(forType: .string),
               NSPasteboard.general.data(forType: .png) == nil,
               NSPasteboard.general.data(forType: .tiff) == nil,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                PasteService.pasteText(
                    text, into: self.previousApp,
                    useFocusedField: self.settings.pasteIntoFocusedField)
                return
            }

            PasteService.pasteClipboard(into: self.previousApp)
        }
    }

    /// Records the frontmost app and its focused field before the panel opens.
    private func rememberPasteTarget() {
        FrontmostAppTracker.captureNow()
        pasteTargetApp = FrontmostAppTracker.lastApplication
        previousApp = pasteTargetApp
        if settings.pasteIntoFocusedField {
            PasteService.capturePasteTarget(from: previousApp, appOnly: true)
        } else {
            PasteService.clearPasteTarget()
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
        if mode == .fullScreen, settings.timerSeconds > 0 {
            CaptureBoundsOverlay.show(
                pixelRect: nil, on: screen, label: "Capturing full screen")
        }
        CountdownPanel.show(seconds: settings.timerSeconds, on: screen) { [weak self] in
            CaptureBoundsOverlay.hide()
            self?.performCapture(mode, on: screen)
        }
    }

    /// Gate ScreenCaptureKit paths so macOS doesn't loop opening Settings
    /// when permission was granted to a different copy of the app.
    ///
    /// `ensureGranted()` only shows the full help alert / Settings prompt the
    /// first time in a session; on later attempts it fails quietly, so give a
    /// quick reminder here instead of leaving the hotkey feel like a no-op.
    @MainActor
    private func guardScreenCaptureAccess() -> Bool {
        if ScreenCapturePermission.ensureGranted() { return true }
        InfoHUD.show("Screen Recording permission needed — enable it in Cliché Settings")
        return false
    }

    private func performCapture(_ mode: CaptureMode, on screen: NSScreen) {
        switch mode {
        case .fullScreen:
            if settings.timerSeconds == 0 {
                CaptureBoundsOverlay.show(
                    pixelRect: nil, on: screen, label: "Capturing full screen",
                    duration: 0.35
                ) { [weak self] in
                    self?.captureWithEngine(
                        screen: screen, rect: nil, cliFallback: .fullScreen)
                }
            } else {
                captureWithEngine(screen: screen, rect: nil, cliFallback: .fullScreen)
            }
        case .region:
            startRegionCapture(on: screen)
        case .window:
            // ScreenCaptureKit has no window-picker UI; keep the native one.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.captureWithCLI(.window)
            }
        }
    }

    /// One-click capture with a preset's bundled mode/format/destination.
    func runPreset(_ preset: CapturePreset) {
        closeAllPopovers()
        let screen = Self.screenUnderMouse()
        switch preset.mode {
        case .fullScreen:
            CaptureBoundsOverlay.show(
                pixelRect: nil, on: screen, label: "Capturing full screen",
                duration: 0.35
            ) { [weak self] in
                self?.captureWithEngine(
                    screen: screen, rect: nil,
                    cliFallback: .fullScreen, preset: preset)
            }
        case .region:
            startRegionCapture(on: screen, preset: preset)
        case .window:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.captureWithCLI(.window, preset: preset)
            }
        }
    }

    /// Region capture: freeze the display first, select on the frozen frame,
    /// then crop the selection out of it — instant and exactly what was seen.
    private func startRegionCapture(on screen: NSScreen, preset: CapturePreset? = nil) {
        guard let displayID = screen.displayID else {
            captureWithCLI(.region)
            return
        }
        let scale = screen.backingScaleFactor
        Task { @MainActor in
            guard guardScreenCaptureAccess() else { return }
            do {
                let frozen = try await ScreenshotEngine.captureImage(
                    displayID: displayID, scale: scale,
                    showsCursor: settings.showCursor,
                    hideDesktopIcons: settings.hideDesktopIcons)
                RegionSelector.begin(frozen: frozen, on: screen) { [weak self] pixelRect in
                    guard let self, let pixelRect else { return }
                    self.settings.lastRegion = (pixelRect, displayID)
                    if let cropped = frozen.cropping(to: pixelRect) {
                        self.deliver(
                            cropped, preset: preset,
                            flashPixelRect: pixelRect, on: screen)
                    }
                }
            } catch {
                NSLog("Cliche: freeze capture failed (\(error)); using CLI")
                self.captureWithCLI(.region, preset: preset)
            }
        }
    }

    /// ⌘⇧3 — frozen overlay with the Region/Window/Full Screen/OCR strip.
    private func startAllInOne() {
        closeAllPopovers()
        let screen = Self.screenUnderMouse()
        guard let displayID = screen.displayID else {
            captureWithCLI(.region)
            return
        }
        let scale = screen.backingScaleFactor
        Task { @MainActor in
            guard guardScreenCaptureAccess() else { return }
            do {
                let frozen = try await ScreenshotEngine.captureImage(
                    displayID: displayID, scale: scale,
                    showsCursor: settings.showCursor,
                    hideDesktopIcons: settings.hideDesktopIcons)
                RegionSelector.begin(
                    frozen: frozen, on: screen, allInOne: .region,
                    onSelect: { [weak self] pixelRect, mode in
                        guard let self, let cropped = frozen.cropping(to: pixelRect)
                        else { return }
                        switch mode {
                        case .region:
                            self.settings.lastRegion = (pixelRect, displayID)
                            self.deliver(
                                cropped, flashPixelRect: pixelRect, on: screen)
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
                        case .window:
                            let target = NSScreen.screens.first { $0.displayID == displayID }
                                ?? NSScreen.main!
                            self.performCapture(.window, on: target)
                        case .fullScreen:
                            // Slight delay so the overlay is fully gone.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                let target = NSScreen.screens.first { $0.displayID == displayID }
                                    ?? NSScreen.main!
                                self.performCapture(.fullScreen, on: target)
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

    /// Multi-window combined capture: picker panel → SCK include-filter.
    private func startMultiWindowCapture() {
        closeAllPopovers()
        WindowPickerPanel.show { [weak self] image in
            self?.deliver(image)
        }
    }

    /// ⌘⇧7 — recapture the exact previous region with no UI.
    private func repeatLastRegion() {
        guard let last = settings.lastRegion else {
            InfoHUD.show("No previous region — use ⌘⇧6 first")
            return
        }
        let screen = NSScreen.screens.first { $0.displayID == last.displayID }
            ?? Self.screenUnderMouse()
        Task { @MainActor in
            guard guardScreenCaptureAccess() else { return }
            do {
                let frozen = try await ScreenshotEngine.captureImage(
                    displayID: last.displayID, scale: screen.backingScaleFactor,
                    showsCursor: settings.showCursor,
                    hideDesktopIcons: settings.hideDesktopIcons)
                CaptureBoundsOverlay.show(
                    pixelRect: last.rect, on: screen, frozen: frozen,
                    duration: 0.45
                ) { [weak self] in
                    guard let self else { return }
                    if let cropped = frozen.cropping(to: last.rect) {
                        self.deliver(
                            cropped, flashPixelRect: last.rect, on: screen)
                    }
                }
            } catch {
                NSLog("Cliche: repeat-area capture failed: \(error)")
            }
        }
    }

    private func captureWithEngine(
        screen: NSScreen, rect: CGRect?, cliFallback: CaptureMode,
        preset: CapturePreset? = nil
    ) {
        guard let displayID = screen.displayID else {
            captureWithCLI(cliFallback, preset: preset)
            return
        }
        let scale = screen.backingScaleFactor
        Task { @MainActor in
            guard guardScreenCaptureAccess() else { return }
            do {
                let image = try await ScreenshotEngine.captureImage(
                    displayID: displayID, sourceRect: rect, scale: scale,
                    showsCursor: settings.showCursor,
                    hideDesktopIcons: settings.hideDesktopIcons)
                self.deliver(image, preset: preset, flashPixelRect: nil, on: screen)
            } catch {
                NSLog("Cliche: ScreenCaptureKit failed (\(error)); using screencapture CLI")
                guard ScreenCapturePermission.isGranted else { return }
                self.captureWithCLI(cliFallback, preset: preset)
            }
        }
    }

    private func captureWithCLI(_ mode: CaptureMode, preset: CapturePreset? = nil) {
        guard ScreenCapturePermission.isGranted else {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.guardScreenCaptureAccess() else { return }
                self.captureWithCLI(mode, preset: preset)
            }
            return
        }
        let format = preset?.format ?? settings.captureFormat
        let saveToDisk = preset != nil || settings.saveCapturesToDisk
        let directory = preset?.destinationURL ?? settings.captureSaveDirectoryURL
        var explicitURL: URL?
        if saveToDisk {
            if let preset {
                try? FileManager.default.createDirectory(
                    at: preset.destinationURL, withIntermediateDirectories: true)
                explicitURL = CaptureNaming.uniqueOutputURL(
                    directory: preset.destinationURL,
                    pattern: preset.filenamePattern,
                    fileExtension: format.fileExtension)
            } else {
                try? FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: true)
                explicitURL = CaptureNaming.uniqueOutputURL(
                    directory: directory,
                    pattern: CaptureNaming.defaultPattern,
                    fileExtension: format.fileExtension)
            }
        } else {
            explicitURL = CaptureNaming.uniqueOutputURL(
                directory: FileManager.default.temporaryDirectory,
                pattern: "cliche-temp",
                fileExtension: format.fileExtension)
        }
        captureService.capture(
            mode,
            format: format,
            copyToClipboard: preset?.copyToClipboard ?? settings.copyCapturesToClipboard,
            showCursor: settings.showCursor,
            windowShadow: settings.windowShadow,
            directory: directory,
            outputURL: explicitURL
        ) { [weak self] url in
            guard let self else { return }
            if saveToDisk {
                self.capturesStore.add(path: url.path)
                let image = NSImage(contentsOf: url)?
                    .cgImage(forProposedRect: nil, context: nil, hints: nil)
                self.showOverlay(for: url, image: image)
                InfoHUD.show("Saved to \(url.deletingLastPathComponent().lastPathComponent)/\(url.lastPathComponent)")
            } else {
                try? FileManager.default.removeItem(at: url)
                if self.settings.copyCapturesToClipboard {
                    InfoHUD.show("Copied to clipboard")
                }
            }
        }
    }

    /// Common post-capture step: file + clipboard already handled; index it,
    /// scan for QR codes, and show the Quick Access Overlay. A preset
    /// overrides format, clipboard behavior, destination, and naming.
    private func deliver(
        _ image: CGImage,
        preset: CapturePreset? = nil,
        flashPixelRect: CGRect? = nil,
        on screen: NSScreen? = nil
    ) {
        let saveToDisk = preset != nil || settings.saveCapturesToDisk
        let directory = preset?.destinationURL ?? settings.captureSaveDirectoryURL
        let url = CaptureDelivery.deliver(
            image,
            format: preset?.format ?? settings.captureFormat,
            copyToClipboard: preset?.copyToClipboard ?? settings.copyCapturesToClipboard,
            saveToDisk: saveToDisk,
            directory: directory,
            pattern: preset?.filenamePattern ?? CaptureNaming.defaultPattern)
        if let url {
            capturesStore.add(path: url.path)
            showOverlay(for: url, image: image)
            InfoHUD.show("Saved to \(url.deletingLastPathComponent().lastPathComponent)/\(url.lastPathComponent)")
        } else if settings.copyCapturesToClipboard || preset?.copyToClipboard == true {
            InfoHUD.show("Copied to clipboard")
        }
        let flashScreen = screen ?? Self.screenUnderMouse()
        CaptureBoundsOverlay.flash(pixelRect: flashPixelRect, on: flashScreen)
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
            guard guardScreenCaptureAccess() else { return }
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
            guard guardScreenCaptureAccess() else { return }
            guard let frozen = try? await ScreenshotEngine.captureImage(
                displayID: displayID, scale: scale) else {
                InfoHUD.show("Scrolling capture needs the Screen Recording permission")
                return
            }
            RegionSelector.begin(frozen: frozen, on: screen) { [weak self] pixelRect in
                guard let self, let pixelRect else { return }
                ScrollingCapture.begin(
                    displayID: displayID, pixelRect: pixelRect, scale: scale,
                    showsCursor: false,
                    hideDesktopIcons: self.settings.hideDesktopIcons, on: screen
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
            guard guardScreenCaptureAccess() else { return }
            guard let frozen = try? await ScreenshotEngine.captureImage(
                displayID: displayID, scale: scale) else {
                InfoHUD.show("Recording needs the Screen Recording permission")
                return
            }
            RegionSelector.begin(frozen: frozen, on: screen) { [weak self] pixelRect in
                guard let self, let pixelRect else { return }
                RecordingController.begin(
                    displayID: displayID, pixelRect: pixelRect, scale: scale,
                    showsCursor: self.settings.showCursor,
                    hideDesktopIcons: self.settings.hideDesktopIcons, on: screen
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
