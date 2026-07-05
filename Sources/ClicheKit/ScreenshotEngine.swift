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
        showsCursor: Bool = false
    ) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID })
        else { throw EngineError.displayNotFound }

        let ownPID = pid_t(ProcessInfo.processInfo.processIdentifier)
        let ownWindows = content.windows.filter {
            $0.owningApplication?.processID == ownPID
        }
        let filter = SCContentFilter(display: display, excludingWindows: ownWindows)

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
}
