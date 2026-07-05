import AppKit
import SwiftUI

/// Big centered countdown before a timed capture.
enum CountdownPanel {
    private static var panel: NSPanel?
    private static var timer: Timer?

    static func show(seconds: Int, on screen: NSScreen, completion: @escaping () -> Void) {
        hide()
        guard seconds > 0 else {
            completion()
            return
        }
        let size = NSSize(width: 140, height: 140)
        let countdownPanel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        countdownPanel.level = .screenSaver
        countdownPanel.backgroundColor = .clear
        countdownPanel.isOpaque = false
        countdownPanel.hasShadow = false
        countdownPanel.isReleasedWhenClosed = false
        countdownPanel.ignoresMouseEvents = true
        countdownPanel.setFrameOrigin(NSPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.midY - size.height / 2))

        var remaining = seconds
        let label = NSTextField(labelWithString: "\(remaining)")
        label.font = .monospacedDigitSystemFont(ofSize: 72, weight: .bold)
        label.textColor = .white
        label.alignment = .center

        let background = NSView(frame: NSRect(origin: .zero, size: size))
        background.wantsLayer = true
        background.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        background.layer?.cornerRadius = 20
        label.frame = background.bounds.insetBy(dx: 0, dy: 25)
        background.addSubview(label)
        countdownPanel.contentView = background
        countdownPanel.orderFrontRegardless()
        panel = countdownPanel

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            remaining -= 1
            if remaining <= 0 {
                hide()
                completion()
            } else {
                label.stringValue = "\(remaining)"
            }
        }
    }

    private static func hide() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

/// Small transient text HUD (bottom-center), e.g. contrast-checker results.
enum InfoHUD {
    private static var panel: NSPanel?
    private static var timer: Timer?

    static func show(_ text: String) {
        hidePanel()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let size = NSSize(width: textSize.width + 36, height: 38)

        let hud = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        hud.level = .statusBar
        hud.backgroundColor = .clear
        hud.isOpaque = false
        hud.isReleasedWhenClosed = false
        hud.ignoresMouseEvents = true

        let label = NSTextField(labelWithString: text)
        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.alignment = .center

        let background = NSView(frame: NSRect(origin: .zero, size: size))
        background.wantsLayer = true
        background.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        background.layer?.cornerRadius = 10
        label.frame = background.bounds.insetBy(dx: 8, dy: 9)
        background.addSubview(label)
        hud.contentView = background

        let screen = NSScreen.main ?? NSScreen.screens[0]
        hud.setFrameOrigin(NSPoint(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.minY + 60))
        hud.orderFrontRegardless()
        panel = hud
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { _ in
            hidePanel()
        }
    }

    private static func hidePanel() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
    }
}
