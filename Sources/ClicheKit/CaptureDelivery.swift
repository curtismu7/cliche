import AppKit

/// Shared "what happens after a screenshot exists" step: a file on disk
/// (configurable folder) plus (optionally) the image on the clipboard.
/// Both the CLI and ScreenCaptureKit paths end here.
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

    /// Returns the written file URL, or nil if saving was skipped or failed.
    @discardableResult
    public static func deliver(
        _ image: CGImage,
        format: AppSettings.ImageFormat = .png,
        copyToClipboard: Bool = true,
        saveToDisk: Bool = true,
        directory: URL? = nil,
        pattern: String = CaptureNaming.defaultPattern
    ) -> URL? {
        guard let data = encode(image, as: format) else { return nil }

        if copyToClipboard {
            ClipboardWriter.writeImage(pngData: data)
        }

        guard saveToDisk else { return nil }

        let folder = directory ?? defaultDesktopDirectory()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = CaptureNaming.uniqueOutputURL(
            directory: folder, pattern: pattern,
            fileExtension: format.fileExtension)
        do {
            try data.write(to: url)
            return url
        } catch {
            NSLog("Cliche: failed to write capture: \(error)")
            return nil
        }
    }

    public static func defaultDesktopDirectory() -> URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    public static func outputURL(
        directory: URL,
        fileExtension: String,
        pattern: String = CaptureNaming.defaultPattern
    ) -> URL {
        CaptureNaming.uniqueOutputURL(
            directory: directory, pattern: pattern, fileExtension: fileExtension)
    }
}
