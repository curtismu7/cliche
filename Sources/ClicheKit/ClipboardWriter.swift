import AppKit

public enum ClipboardWriter {
    private static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47]

    /// Writes an image to the pasteboard as both PNG and TIFF — some apps
    /// (older AppKit apps, some Office builds) only read TIFF, so writing
    /// PNG alone makes pasting silently fail there. Accepts any decodable
    /// image data (PNG, JPEG, …) and transcodes as needed.
    @discardableResult
    public static func writeImage(
        pngData imageData: Data, to pasteboard: NSPasteboard = .general
    ) -> Bool {
        guard let rep = NSBitmapImageRep(data: imageData) else { return false }
        let png = imageData.prefix(4).elementsEqual(pngSignature)
            ? imageData
            : rep.representation(using: .png, properties: [:])
        pasteboard.clearContents()
        if let png {
            pasteboard.setData(png, forType: .png)
        }
        if let tiff = rep.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
        return true
    }
}
