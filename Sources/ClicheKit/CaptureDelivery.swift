import AppKit

/// Shared "what happens after a screenshot exists" step: a file on the
/// Desktop plus (optionally) the image on the clipboard. Both the CLI and
/// ScreenCaptureKit paths end here.
public enum CaptureDelivery {
    public static func pngData(from image: CGImage) -> Data? {
        encode(image, as: .png)
    }

    public static func encode(_ image: CGImage, as format: AppSettings.ImageFormat) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        switch format {
        case .png:
            return rep.representation(using: .png, properties: [:])
        case .jpeg:
            return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        }
    }

    /// Returns the Desktop file URL, or nil if encoding/writing failed.
    @discardableResult
    public static func deliver(
        _ image: CGImage,
        format: AppSettings.ImageFormat = .png,
        copyToClipboard: Bool = true
    ) -> URL? {
        guard let data = encode(image, as: format) else { return nil }
        let url = CaptureService.outputURL(fileExtension: format.fileExtension)
        do {
            try data.write(to: url)
        } catch {
            NSLog("Cliche: failed to write capture: \(error)")
            return nil
        }
        if copyToClipboard {
            ClipboardWriter.writeImage(pngData: data)
        }
        return url
    }
}
