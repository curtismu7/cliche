import AppKit
import ClicheKit

/// Drives a region recording: floating HUD with elapsed time, a GIF toggle,
/// and Stop. Output lands on the Desktop (+ optional GIF) and in the
/// captures index.
final class RecordingController {
    private static var active: RecordingController?

    private let recorder = ScreenRecorder()
    private let onFinished: (URL) -> Void

    private var hud: NSPanel?
    private var timeLabel: NSTextField?
    private var gifCheckbox: NSButton?
    private var ticker: Timer?
    private var startedAt = Date()

    static var isRecording: Bool { active != nil }

    static func begin(
        displayID: CGDirectDisplayID,
        pixelRect: CGRect?,
        scale: CGFloat,
        showsCursor: Bool,
        on screen: NSScreen,
        onFinished: @escaping (URL) -> Void
    ) {
        guard active == nil else { return }
        let controller = RecordingController(onFinished: onFinished)
        active = controller
        controller.start(
            displayID: displayID, pixelRect: pixelRect, scale: scale,
            showsCursor: showsCursor, on: screen)
    }

    private init(onFinished: @escaping (URL) -> Void) {
        self.onFinished = onFinished
    }

    private func start(
        displayID: CGDirectDisplayID, pixelRect: CGRect?, scale: CGFloat,
        showsCursor: Bool, on screen: NSScreen
    ) {
        let outputURL = CaptureService.outputURL(fileExtension: "mp4")
        let pointRect = pixelRect.map {
            CGRect(x: $0.minX / scale, y: $0.minY / scale,
                   width: $0.width / scale, height: $0.height / scale)
        }
        Task { @MainActor in
            do {
                try await recorder.start(
                    displayID: displayID, sourceRect: pointRect, scale: scale,
                    showsCursor: showsCursor, outputURL: outputURL)
                startedAt = Date()
                showHUD(on: screen)
            } catch {
                NSLog("Cliche: recording failed to start: \(error)")
                InfoHUD.show("Recording could not start (check Screen Recording permission)")
                Self.active = nil
            }
        }
    }

    private func showHUD(on screen: NSScreen) {
        let size = NSSize(width: 300, height: 56)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true

        let background = NSView(frame: NSRect(origin: .zero, size: size))
        background.wantsLayer = true
        background.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.8).cgColor
        background.layer?.cornerRadius = 12

        let dot = NSTextField(labelWithString: "●")
        dot.textColor = .systemRed
        dot.font = .systemFont(ofSize: 14)
        dot.frame = NSRect(x: 12, y: 31, width: 18, height: 18)

        let label = NSTextField(labelWithString: "Recording 0:00")
        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.frame = NSRect(x: 32, y: 31, width: 250, height: 18)

        let stop = NSButton(title: "Stop", target: self, action: #selector(stopTapped))
        stop.bezelStyle = .rounded
        stop.frame = NSRect(x: 12, y: 4, width: 80, height: 24)

        let gif = NSButton(checkboxWithTitle: "Also save GIF", target: nil, action: nil)
        gif.frame = NSRect(x: 100, y: 8, width: 150, height: 18)
        gif.contentTintColor = .white
        (gif.cell as? NSButtonCell)?.attributedTitle = NSAttributedString(
            string: "Also save GIF",
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 12),
            ])

        background.addSubview(dot)
        background.addSubview(label)
        background.addSubview(stop)
        background.addSubview(gif)
        panel.contentView = background
        panel.setFrameOrigin(NSPoint(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.minY + 24))
        panel.orderFrontRegardless()

        hud = panel
        timeLabel = label
        gifCheckbox = gif
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let elapsed = Int(Date().timeIntervalSince(self.startedAt))
            self.timeLabel?.stringValue = String(
                format: "Recording %d:%02d", elapsed / 60, elapsed % 60)
        }
    }

    @objc private func stopTapped() {
        let wantsGIF = gifCheckbox?.state == .on
        ticker?.invalidate()
        hud?.orderOut(nil)
        Task { @MainActor in
            let url = await recorder.stop()
            Self.active = nil
            guard let url else {
                InfoHUD.show("Recording failed")
                return
            }
            onFinished(url)
            if wantsGIF {
                InfoHUD.show("Converting to GIF…")
                let gifURL = url.deletingPathExtension().appendingPathExtension("gif")
                if let data = await VideoGIF.gifData(from: url) {
                    try? data.write(to: gifURL)
                    InfoHUD.show("GIF saved to Desktop")
                } else {
                    InfoHUD.show("GIF conversion failed")
                }
            }
        }
    }
}
