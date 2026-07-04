import AppKit

/// Shared "what happens after a screenshot exists" step: PNG on the Desktop
/// plus the image on the clipboard (both the CLI and ScreenCaptureKit paths
/// end here).
public enum CaptureDelivery {
    public static func pngData(from image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image)
            .representation(using: .png, properties: [:])
    }

    /// Returns the Desktop file URL, or nil if encoding/writing failed.
    @discardableResult
    public static func deliver(_ image: CGImage) -> URL? {
        guard let data = pngData(from: image) else { return nil }
        let url = CaptureService.outputURL()
        do {
            try data.write(to: url)
        } catch {
            NSLog("ClipShot: failed to write capture: \(error)")
            return nil
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .png)
        return url
    }
}
