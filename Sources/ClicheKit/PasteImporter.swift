import AppKit
import SQLite3

/// Reads Paste.app's SQLite store. Paste keeps each clip as a binary
/// property list (bplist) in `ZSNIPPET.ZCONTENT`; this importer decodes
/// the plist and pulls out plain-text and image types, ignoring rich
/// content like RTF, HTML, and web archives.
public struct PasteImporter: ClipboardImporter {
    public let name = "Paste"

    public init() {}

    public var isAvailable: Bool { Self.defaultDatabaseURL != nil }

    public static var defaultDatabaseURL: URL? {
        let path = "\(NSHomeDirectory())/Library/Containers/com.wiheads.paste/Data/Library/Application Support/Paste/Paste.db"
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    @MainActor
    public func importAll(into store: HistoryStore) throws -> ImportResult {
        guard let dbURL = Self.defaultDatabaseURL else {
            throw NSError(domain: "PasteImporter", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Paste storage not found."])
        }
        let db = try Connection(url: dbURL)
        var result = ImportResult()
        // ZSNIPPET columns vary by version; pick the ones we need defensively.
        let hasZContent = try db.query(
            "SELECT name FROM pragma_table_info('ZSNIPPET') WHERE name = 'ZCONTENT'"
        ) { _ in Void() }.count > 0
        guard hasZContent else { return result }
        let hasZPinned = try db.query(
            "SELECT name FROM pragma_table_info('ZSNIPPET') WHERE name = 'ZPINNED'"
        ) { _ in Void() }.count > 0
        let pinnedColumn = hasZPinned ? "ZPINNED" : "0"
        let blobs = try db.query(
            "SELECT ZCONTENT, \(pinnedColumn) FROM ZSNIPPET ORDER BY ZTIMESTAMP DESC"
        ) { stmt in
            (blob: Connection.columnBlob(stmt, 0),
             pinned: sqlite3_column_int(stmt, 1) != 0)
        }
        for entry in blobs {
            let outcome = importBlob(entry.blob, pinned: entry.pinned, into: store)
            switch outcome {
            case .text:
                result.importedTexts += 1
                if entry.pinned { result.pinnedImports += 1 }
            case .image:
                result.importedImages += 1
                if entry.pinned { result.pinnedImports += 1 }
            case .skipped:
                result.skipped += 1
            }
        }
        return result
    }

    private enum Outcome { case text, image, skipped }

    /// Decodes a bplist and tries to import text or image content from it.
    private func importBlob(_ blob: Data, pinned dbPinned: Bool, into store: HistoryStore) -> Outcome {
        guard !blob.isEmpty,
              let plist = try? PropertyListSerialization.propertyList(
                  from: blob, options: [], format: nil) as? [String: Any]
        else { return .skipped }

        // Pin state can live either in the ZSNIPPET row (dbPinned) or inside
        // the bplist metadata (pinned/favorite). Either source wins.
        let pinned = dbPinned
            || (plist["pinned"] as? Bool == true)
            || (plist["favorite"] as? Bool == true)

        // Paste stores an array of pasteboard item dicts under "items" or
        // a flat dict of type→value. Try both layouts.
        var best = Outcome.skipped
        if let items = plist["items"] as? [[String: Any]] {
            for item in items {
                if let r = importItem(item, pinned: pinned, into: store), r == .text { best = .text }
                else if let r = importItem(item, pinned: pinned, into: store), r == .image, best != .text { best = .image }
            }
        } else if let r = importItem(plist, pinned: pinned, into: store) {
            best = r
        }
        return best
    }

    private func importItem(_ item: [String: Any], pinned: Bool, into store: HistoryStore) -> Outcome? {
        // Text first.
        if let s = item["public.utf8-plain-text"] as? String ?? item["public.text"] as? String,
           !s.isEmpty,
           !store.items.contains(where: { $0.dedupeKey == "t:\(s)" }) {
            store.addText(s, pinned: pinned)
            return .text
        }
        // Images.
        let pngData = item["public.png"] as? Data ?? decodeImage(item)
        if let pngData, !pngData.isEmpty {
            let sha = HistoryStore.sha256(pngData)
            guard !store.items.contains(where: { $0.dedupeKey == "i:\(sha)" })
            else { return .skipped }
            store.addImage(pngData, pinned: pinned)
            return .image
        }
        return nil
    }

    /// HEIC/JPEG/TIFF → PNG.
    private func decodeImage(_ item: [String: Any]) -> Data? {
        for key in ["public.heic", "public.jpeg", "public.tiff", "public.file-url"] {
            guard let raw = item[key] as? Data, !raw.isEmpty else { continue }
            if let nsImage = NSImage(data: raw),
               let tiff = nsImage.tiffRepresentation as Data?,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                return png
            }
        }
        return nil
    }
}
