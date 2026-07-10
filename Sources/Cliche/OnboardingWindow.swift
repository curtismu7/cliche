import AppKit
import ClicheKit
import SwiftUI

/// First-run walkthrough: permissions and where to find settings.
enum OnboardingWindow {
    private static var window: NSWindow?
    private static var delegate: WindowDelegate?

    static var isVisible: Bool { window != nil }

    @MainActor
    static func show(
        settings: AppSettings,
        ignoreRulesURL: URL,
        historyStore: HistoryStore?
    ) {
        FloatingListWindow.suspendAutoClose = true

        if let window, window.isVisible {
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
        let height = PanelMetrics.maxPanelHeight(on: screen)

        let onboardingWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        onboardingWindow.title = "Welcome to Cliché"
        onboardingWindow.minSize = NSSize(width: 400, height: 420)
        onboardingWindow.isReleasedWhenClosed = false
        onboardingWindow.contentViewController = NSHostingController(rootView: view)

        let windowDelegate = WindowDelegate {
            settings.hasCompletedOnboarding = true
            close()
        }
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
    }

    private final class WindowDelegate: NSObject, NSWindowDelegate {
        let onClose: () -> Void
        init(onClose: @escaping () -> Void) { self.onClose = onClose }
        func windowWillClose(_ notification: Notification) { onClose() }
    }
}

private struct OnboardingView: View {
    @Bindable var settings: AppSettings
    let onOpenSettings: () -> Void
    let onComplete: () -> Void

    @State private var screenGranted = ScreenCapturePermission.isGranted
    @State private var accessibilityGranted = PasteService.isTrusted

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to Cliché")
                    .font(.title2.bold())
                Text("Clipboard history and screen capture in one place. Two quick permissions get you started.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
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
                            detail: "Optional — lets Cliché paste directly into the field you were typing in. Click + in Accessibility and choose /Applications/Cliche.app if it is missing.",
                            onEnable: {
                                _ = PasteService.requestTrust()
                                accessibilityGranted = PasteService.isTrusted
                                if !accessibilityGranted {
                                    PasteService.openSettings()
                                }
                            },
                            onOpenSettings: PasteService.openSettings)
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Red gear icon = Settings", systemImage: "gearshape.fill")
                                .foregroundStyle(PanelTheme.settingsIcon)
                                .font(.system(size: 13, weight: .semibold))
                            Text("⌥1 opens clipboard history · ⌥2 opens capture · ⌘⇧6 captures a region")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Text("Look for the scissors icon in the menu bar (top right). On notched MacBooks it may hide under ◂ — hotkeys still work.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                    }
                }
                .padding(16)
            }

            Divider()

            HStack {
                Button("Open Settings") { onOpenSettings() }
                Spacer()
                Button("Get Started") { onComplete() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 440)
        .onAppear {
            screenGranted = ScreenCapturePermission.isGranted
            accessibilityGranted = PasteService.isTrusted
        }
    }

    private func permissionCard(
        title: String,
        required: Bool,
        granted: Bool,
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
                    }
                }
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
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
