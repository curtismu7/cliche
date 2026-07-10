import AppKit
import ClicheKit
import SwiftUI

/// First-run walkthrough: permissions and where to find settings.
enum OnboardingWindow {
    private static var window: NSWindow?
    private static var delegate: WindowDelegate?
    private static var appSettings: AppSettings?

    static var isVisible: Bool { window?.isVisible == true }

    @MainActor
    static func show(
        settings: AppSettings,
        ignoreRulesURL: URL,
        historyStore: HistoryStore?
    ) {
        appSettings = settings
        FloatingListWindow.suspendAutoClose = true
        NSApp.setActivationPolicy(.regular)
        if !settings.showMenuBarIcons {
            settings.showMenuBarIcons = true
        }

        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = OnboardingView(
            settings: settings,
            onOpenSettings: {
                SettingsWindow.show(
                    settings: settings,
                    ignoreRulesURL: ignoreRulesURL,
                    historyStore: historyStore)
            },
            onComplete: {
                settings.hasCompletedOnboarding = true
                close()
            })

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let maxHeight = PanelMetrics.maxPanelHeight(on: screen)
        let height = min(580, max(480, maxHeight))

        let onboardingWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: height),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false)
        onboardingWindow.title = "Welcome to Cliché"
        onboardingWindow.minSize = NSSize(width: 400, height: 480)
        onboardingWindow.isReleasedWhenClosed = false
        onboardingWindow.canHide = false
        onboardingWindow.level = .floating
        onboardingWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let hosting = NSHostingController(rootView: view)
        hosting.view.autoresizingMask = [.width, .height]
        onboardingWindow.contentViewController = hosting

        let windowDelegate = WindowDelegate { close() }
        onboardingWindow.delegate = windowDelegate
        delegate = windowDelegate

        window = onboardingWindow
        onboardingWindow.center()
        onboardingWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func close() {
        window?.orderOut(nil)
        window = nil
        delegate = nil
        if !SettingsWindow.isVisible {
            FloatingListWindow.suspendAutoClose = false
        }
        if appSettings?.hasCompletedOnboarding == true {
            NSApp.setActivationPolicy(.accessory)
            appSettings = nil
        }
    }

    private final class WindowDelegate: NSObject, NSWindowDelegate {
        let onClose: () -> Void
        init(onClose: @escaping () -> Void) { self.onClose = onClose }
        func windowShouldClose(_ sender: NSWindow) -> Bool { false }
        func windowWillClose(_ notification: Notification) { onClose() }
    }
}

private struct OnboardingView: View {
    @Bindable var settings: AppSettings
    let onOpenSettings: () -> Void
    let onComplete: () -> Void

    @State private var screenGranted = ScreenCapturePermission.isGranted
    @State private var accessibilityGranted = PasteService.isTrusted
    @State private var accessibilitySetupStarted = false

    private var accessibilityNeedsRestart: Bool {
        accessibilitySetupStarted && !accessibilityGranted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to Cliché")
                    .font(.title2.bold())
                Text("Clipboard history and screen capture in one place. Two quick permissions get you started.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    permissionCard(
                        title: "Screen Recording",
                        required: true,
                        granted: screenGranted,
                        detail: "Required for screenshots and region capture. In System Settings, turn Cliché OFF then ON if it already appears in the list.",
                        onEnable: {
                            _ = ScreenCapturePermission.requestAccessUserInitiated()
                            screenGranted = ScreenCapturePermission.isGranted
                        },
                        onOpenSettings: ScreenCapturePermission.openSettings)

                    if settings.pasteIntoFocusedField {
                        permissionCard(
                            title: "Accessibility",
                            required: false,
                            granted: accessibilityGranted,
                            pendingRestart: accessibilityNeedsRestart,
                            detail: accessibilityDetail,
                            onEnable: {
                                accessibilitySetupStarted = true
                                _ = PasteService.requestTrust()
                                refreshPermissionState()
                                if !accessibilityGranted {
                                    PasteService.openSettings()
                                }
                            },
                            onOpenSettings: {
                                accessibilitySetupStarted = true
                                PasteService.openSettings()
                            })
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Red gear icon = Settings", systemImage: "gearshape.fill")
                                .foregroundStyle(PanelTheme.settingsIcon)
                                .font(.system(size: 13, weight: .semibold))
                            Text("⌥1 opens clipboard history · ⌥2 opens capture · ⌘⇧6 captures a region")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Cliché appears in the Dock while you finish setup.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(menuBarHint)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack {
                Button("Open Settings") { onOpenSettings() }
                Spacer()
                Text("Click Get Started when permissions are set")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Button("Get Started") { onComplete() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 440)
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { refreshPermissionState() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionState()
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            refreshPermissionState()
        }
    }

    private var accessibilityDetail: String {
        if accessibilityGranted {
            return "Direct paste into the focused field is active."
        }
        if accessibilityNeedsRestart {
            return "Cliché is ON in System Settings. Quit Cliché completely (⌘Q) and reopen — macOS applies Accessibility on restart."
        }
        return "Optional — lets Cliché paste directly into the field you were typing in. Click + in Accessibility and choose /Applications/Cliche.app if it is missing."
    }

    private func refreshPermissionState() {
        screenGranted = ScreenCapturePermission.isGranted
        accessibilityGranted = PasteService.isTrusted
        if accessibilityGranted {
            accessibilitySetupStarted = false
        }
    }

    private var menuBarHint: String {
        let overflow = "On notched MacBooks, icons may hide under ◂ in the menu bar."
        switch settings.menuBarStyle {
        case .combined:
            return "Look for the scissors icon in the menu bar (top right). \(overflow)"
        case .split:
            return "Look for the clipboard and camera icons in the menu bar (top right). \(overflow)"
        }
    }

    private func permissionCard(
        title: String,
        required: Bool,
        granted: Bool,
        pendingRestart: Bool = false,
        detail: String,
        onEnable: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    if required {
                        Text("Required")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .clipShape(Capsule())
                    }
                    Spacer()
                    if granted {
                        Label("Enabled", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 12))
                    } else if pendingRestart {
                        Label("Quit & reopen", systemImage: "arrow.clockwise.circle")
                            .foregroundStyle(.orange)
                            .font(.system(size: 12))
                    }
                }
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    if !granted {
                        Button("Enable…", action: onEnable)
                    }
                    Button("Open System Settings", action: onOpenSettings)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }
}
