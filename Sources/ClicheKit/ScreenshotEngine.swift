import AppKit
import ScreenCaptureKit

/// In-process screenshots via ScreenCaptureKit — no shell-out, no shutter
/// sound, and Cliche's own windows are excluded from the image.
public enum ScreenshotEngine {
    public enum EngineError: Error {
        case displayNotFound
    }

    /// Captures a display, optionally cropped to `sourceRect` (in points,
    /// top-left origin, display-relative). `scale` is the display's backing
    /// scale factor so Retina output keeps full resolution.
    public static func captureImage(
        displayID: CGDirectDisplayID,
        sourceRect: CGRect? = nil,
        scale: CGFloat,
        showsCursor: Bool = false,
        hideDesktopIcons: Bool = false
    ) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID })
        else { throw EngineError.displayNotFound }

        let excluded = DesktopClutter.exclusions(
            in: content.windows, hideDesktopIcons: hideDesktopIcons)
        let filter = SCContentFilter(display: display, excludingWindows: excluded)

        let rect = sourceRect
            ?? CGRect(x: 0, y: 0, width: display.width, height: display.height)
        let configuration = SCStreamConfiguration()
        if sourceRect != nil {
            configuration.sourceRect = rect
        }
        configuration.width = Int(rect.width * scale)
        configuration.height = Int(rect.height * scale)
        configuration.showsCursor = showsCursor

        return try await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: configuration)
    }

    // MARK: Multi-window combined capture

    /// Pixel crop covering all `frames` (screen points, global top-left
    /// origin) on the given display, with a margin. Nil when nothing of the
    /// union lands on the display.
    public static func unionPixelRect(
        frames: [CGRect], displayFrame: CGRect, scale: CGFloat,
        marginPoints: CGFloat = 12
    ) -> CGRect? {
        guard let first = frames.first else { return nil }
        var union = frames.dropFirst().reduce(first) { $0.union($1) }
        union = union.insetBy(dx: -marginPoints, dy: -marginPoints)
            .intersection(displayFrame)
        guard !union.isEmpty else { return nil }
        return CGRect(
            x: (union.minX - displayFrame.minX) * scale,
            y: (union.minY - displayFrame.minY) * scale,
            width: union.width * scale,
            height: union.height * scale).integral
    }

    /// Captures ONLY the given windows (everything else transparent falls
    /// away to the gradient-free backdrop of the display capture), cropped
    /// to their union.
    public static func captureWindows(
        _ windows: [SCWindow], display: SCDisplay, scale: CGFloat
    ) async throws -> CGImage {
        let filter = SCContentFilter(display: display, including: windows)
        let configuration = SCStreamConfiguration()
        configuration.width = Int(CGFloat(display.width) * scale)
        configuration.height = Int(CGFloat(display.height) * scale)
        let full = try await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: configuration)
        guard let crop = unionPixelRect(
            frames: windows.map(\.frame), displayFrame: display.frame, scale: scale),
              let cropped = full.cropping(to: crop)
        else { return full }
        return cropped
    }
}
