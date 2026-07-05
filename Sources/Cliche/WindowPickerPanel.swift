import AppKit
import ClicheKit
import ScreenCaptureKit
import SwiftUI

/// Multi-window combined capture: pick several on-screen windows, Cliché
/// captures just those (everything else excluded) cropped to their union.
enum WindowPickerPanel {
    private static var window: NSWindow?

    static func show(onCapture: @escaping (CGImage) -> Void) {
        window?.close()
        Task { @MainActor in
            guard let content = try? await SCShareableContent
                .excludingDesktopWindows(true, onScreenWindowsOnly: true)
            else { return }
            let ownPID = pid_t(ProcessInfo.processInfo.processIdentifier)
            let candidates = content.windows.filter { w in
                w.windowLayer == 0
                    && w.frame.width >= 80 && w.frame.height >= 80
                    && w.owningApplication?.processID != ownPID
            }
            guard !candidates.isEmpty else {
                InfoHUD.show("No capturable windows found")
                return
            }
            let view = WindowPickerView(
                windows: candidates,
                onCancel: { window?.close(); window = nil },
                onCapture: { selected in
                    window?.close()
                    window = nil
                    // All selected windows must be on one display; use the
                    // display containing the first window's center.
                    let center = CGPoint(
                        x: selected[0].frame.midX, y: selected[0].frame.midY)
                    guard let display = content.displays.first(
                        where: { $0.frame.contains(center) })
                        ?? content.displays.first
                    else { return }
                    let scale = NSScreen.screens.first {
                        $0.displayID == display.displayID
                    }?.backingScaleFactor ?? 2
                    Task { @MainActor in
                        if let image = try? await ScreenshotEngine.captureWindows(
                            selected, display: display, scale: scale) {
                            onCapture(image)
                        } else {
                            InfoHUD.show("Multi-window capture failed")
                        }
                    }
                })

            let picker = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 420),
                styleMask: [.titled, .closable, .utilityWindow],
                backing: .buffered, defer: false)
            picker.title = "Capture Windows Together"
            picker.isReleasedWhenClosed = false
            picker.level = .floating
            picker.contentViewController = NSHostingController(rootView: view)
            picker.center()
            picker.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            window = picker
        }
    }
}

private struct WindowPickerView: View {
    let windows: [SCWindow]
    let onCancel: () -> Void
    let onCapture: ([SCWindow]) -> Void

    @State private var selectedIDs: Set<CGWindowID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Pick the windows to combine into one screenshot.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(windows, id: \.windowID) { w in
                        Toggle(isOn: Binding(
                            get: { selectedIDs.contains(w.windowID) },
                            set: { on in
                                if on { selectedIDs.insert(w.windowID) }
                                else { selectedIDs.remove(w.windowID) }
                            })) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(w.owningApplication?.applicationName ?? "App")
                                    .font(.system(size: 12, weight: .semibold))
                                Text(w.title?.isEmpty == false ? w.title! : "Untitled")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                    }
                }
                .padding(.vertical, 6)
            }
            Divider()
            HStack {
                Text("\(selectedIDs.count) selected")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Capture") {
                    onCapture(windows.filter { selectedIDs.contains($0.windowID) })
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedIDs.isEmpty)
            }
            .padding(12)
        }
    }
}
