import AppKit
import SQLite3

/// Reads FIPLAB's CopyClip 2 history (and the original CopyClip, which
/// uses the same Core Data layout in a different sandbox container). The
/// store is `copyclip.sqlite` with a `ZCLIPPING` table holding
/// `ZCONTENTS` (plain text), `ZATTRIBUTEDCONTENTS` (bplist blob,
/// RTF/image), and `ZTYPE` (pasteboard type). Text and image types are
/// imported; other types are skipped.
public struct CopyClipImporter: ClipboardImporter {
    public let name: String

    public var isAvailable: Bool { databaseURL != nil }

    /// `true` for CopyClip 2 (bundle id `com.fiplab.copyclip2`), `false` for
    /// the original CopyClip (bundle id `com.fiplab.clipboard`). Both use a
    /// Core Data SQLite store with the same `ZCLIPPING` schema.
    private let isCopyClip2: Bool

    public init(isCopyClip2: Bool = false) {
        self.isCopyClip2 = isCopyClip2
        self.name = isCopyClip2 ? "CopyClip 2" : "CopyClip"
    }

    private var containerURL: URL {
        let id = isCopyClip2 ? "com.fiplab.copyclip2" : "com.fiplab.clipboard"
        return URL(fileURLWithPath: "\(NSHomeDirectory())/Library/Containers/\(id)")
    }

    /// Locates the SQLite store inside the sandboxed container. CopyClip 2
    /// keeps it at `Data/Library/Application Support/CopyClip/copyclip.sqlite`.
    private var databaseURL: URL? {
        let fm = FileManager.default
        let support = containerURL.appendingPathComponent(
            "Data/Library/Application Support", isDirectory: true)
        // Try the documented CopyClip 2 subfolder first, then a flat scan.
        let copyclipSub = support.appendingPathComponent("CopyClip", isDirectory: true)
        if let entries = try? fm.contentsOfDirectory(at: copyclipSub,
                                                     includingPropertiesForKeys: nil) {
            if let db = entries.first(where: { $0.pathExtension == "sqlite" }) {
                return db
            }
        }
        // Fall back to any *.sqlite file anywhere under Application Support.
        if let entries = try? fm.contentsOfDirectory(at: support,
                                                     includingPropertiesForKeys: nil) {
            return entries.first { $0.pathExtension == "sqlite" }
        }
        return nil
    }

    @MainActor
    public func importAll(into store: HistoryStore) throws -> ImportResult {
        guard let url = databaseURL else {
            throw NSError(domain: "CopyClipImporter", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "\(name) storage not found."])
        }
        let db = try Connection(url: url)
        // Be defensive about the schema: older builds may not have every
        // column. We only need ZCONTENTS, ZTYPE, and ZATTRIBUTEDCONTENTS.
        let columns = try db.query(
            "SELECT name FROM pragma_table_info('ZCLIPPING')"
        ) { stmt in Connection.columnString(stmt, 0) ?? "" }
        guard columns.contains("ZCONTENTS") else {
            throw NSError(domain: "CopyClipImporter", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "\(name) schema not recognized."])
        }
        let hasBlob = columns.contains("ZATTRIBUTEDCONTENTS")
        let blobColumn = hasBlob ? "ZATTRIBUTEDCONTENTS" : "NULL"
        let sql = "SELECT ZTYPE, ZCONTENTS, \(blobColumn) FROM ZCLIPPING ORDER BY ZDATERECORDED DESC"
        let rows = try db.query(sql) { stmt in
            CopyClipRow(
                type: Connection.columnString(stmt, 0),
                contents: Connection.columnString(stmt, 1) ?? "",
                blob: hasBlob ? Connection.columnBlob(stmt, 2) : Data())
        }
        var result = ImportResult()
        for row in rows {
            let outcome = importRow(row, into: store)
            switch outcome {
            case .text: result.importedTexts += 1
            case .image: result.importedImages += 1
            case .skipped: result.skipped += 1
            }
        }
        return result
    }

    private enum Outcome { case text, image, skipped }

    private func importRow(_ row: CopyClipRow, into store: HistoryStore) -> Outcome {
        // ZCONTENTS holds the plain-text representation; prefer it for text
        // items. The blob (an archived RTF/image) is only consulted when the
        // row's type signals an image clip.
        switch row.type {
        case "NSStringPboardType", "public.utf8-plain-text", "public.text":
            guard !row.contents.isEmpty,
                  !store.items.contains(where: { $0.dedupeKey == "t:\(row.contents)" })
            else { return .skipped }
            store.addText(row.contents)
            return .text
        case "public.png", "public.heic", "public.tiff", "public.jpeg",
             "NSPasteboardTypePNG", "Apple TIFF pasteboard type", "NSPasteboardTypeTIFF":
            if let png = decodeImage(row.blob) {
                let sha = HistoryStore.sha256(png)
                guard !store.items.contains(where: { $0.dedupeKey == "i:\(sha)" })
                else { return .skipped }
                store.addImage(png)
                return .image
            }
            return .skipped
        default:
            // Some builds leave ZTYPE null but still populate ZCONTENTS with
            // text — treat a non-empty ZCONTENTS as a text clip in that case.
            if !row.contents.isEmpty,
               !store.items.contains(where: { $0.dedupeKey == "t:\(row.contents)" }) {
                store.addText(row.contents)
                return .text
            }
            return .skipped
        }
    }

    /// The blob is an `NSKeyedArchiver` archive wrapping RTF or image data.
    /// Decode it and convert to PNG.
    private func decodeImage(_ blob: Data) -> Data? {
        guard !blob.isEmpty,
              let root = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(blob)
        else { return nil }
        // The archived object is often an NSData wrapping the image bytes.
        if let raw = root as? Data, let nsImage = NSImage(data: raw),
           let tiff = nsImage.tiffRepresentation as Data?,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return png
        }
        return nil
    }
}

private struct CopyClipRow {
    let type: String?
    let contents: String
    let blob: Data
}
