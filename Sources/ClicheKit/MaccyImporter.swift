import AppKit
import ClicheKit
import SQLite3

/// Reads Maccy's Core Data SQLite store and converts each history item to a
/// `ClipItem`, writing text into `history.json` and images into the images
/// directory alongside the existing history.
public enum MaccyImporter {
    public struct Result {
        public var importedTexts = 0
        public var importedImages = 0
        public var skipped = 0
    }

    /// Default Maccy storage path (sandboxed container).
    public static var defaultDatabaseURL: URL? {
        let home = NSHomeDirectory()
        let path = "\(home)/Library/Containers/org.p0deje.Maccy/Data/Library/Application Support/Maccy/Storage.sqlite"
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Imports every Maccy item into `store`. Idempotent: items already
    /// present (by content hash) are skipped.
    @MainActor
    public static func importAll(into store: HistoryStore) throws -> Result {
        guard let dbURL = defaultDatabaseURL else {
            throw NSError(domain: "MaccyImporter", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Maccy storage not found."])
        }
        let db = try Connection(url: dbURL)
        let rows = try db.fetchItems()
        var result = Result()
        for row in rows {
            let wasImported = importRow(row, into: store)
            if wasImported {
                switch row.kind {
                case .text: result.importedTexts += 1
                case .image: result.importedImages += 1
                case .none: break
                }
            } else {
                result.skipped += 1
            }
        }
        return result
    }

    private static func importRow(_ row: Row, into store: HistoryStore) -> Bool {
        switch row.kind {
        case .text(let text):
            guard !text.isEmpty,
                  !store.items.contains(where: { $0.dedupeKey == "t:\(text)" })
            else { return false }
            store.addText(text)
            return true
        case .image(let data):
            let sha = HistoryStore.sha256(data)
            guard !store.items.contains(where: { $0.dedupeKey == "i:\(sha)" })
            else { return false }
            store.addImage(data)
            return true
        case .none:
            return false
        }
    }
}

/// Minimal SQLite reader — avoids linking a C library. Reads only what the
/// importer needs: history rows with their preferred pasteboard type.
private final class Connection {
    private let db: OpaquePointer

    init(url: URL) throws {
        var handle: OpaquePointer?
        let code = sqlite3_open(url.path, &handle)
        guard code == SQLITE_OK, let db = handle else {
            sqlite3_close(handle)
            throw NSError(domain: "MaccyImporter", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Could not open Maccy database."])
        }
        self.db = db
    }

    deinit { sqlite3_close(db) }

    func fetchItems() throws -> [Row] {
        let sql = """
        SELECT i.Z_PK, i.ZLASTCOPIEDAT, i.ZTITLE, c.ZTYPE, c.ZVALUE
        FROM ZHISTORYITEM i
        LEFT JOIN ZHISTORYITEMCONTENT c ON c.ZITEM = i.Z_PK
        ORDER BY i.ZLASTCOPIEDAT DESC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(domain: "MaccyImporter", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Could not read Maccy history."])
        }
        defer { sqlite3_finalize(stmt) }

        var byItem: [Int64: Row] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let pk = sqlite3_column_int64(stmt, 0)
            let timestamp = sqlite3_column_double(stmt, 1)
            let title = columnString(stmt, 2)
            let type = columnString(stmt, 3)
            let value = columnBlob(stmt, 4)

            if byItem[pk] == nil {
                byItem[pk] = Row(pk: pk, timestamp: timestamp, title: title, kind: .none)
            }
            byItem[pk]?.consider(type: type, value: value)
        }
        return byItem.values.sorted { $0.timestamp > $1.timestamp }
    }

    private func columnString(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let cstr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cstr)
    }

    private func columnBlob(_ stmt: OpaquePointer?, _ index: Int32) -> Data {
        let bytes = sqlite3_column_blob(stmt, index)
        let length = Int(sqlite3_column_bytes(stmt, index))
        guard let bytes, length > 0 else { return Data() }
        return Data(bytes: bytes, count: length)
    }
}

private struct Row {
    let pk: Int64
    let timestamp: Double
    let title: String?
    var kind: Kind

    enum Kind {
        case none
        case text(String)
        case image(Data)
    }

    /// Pick the most useful pasteboard type for this item.
    mutating func consider(type: String?, value: Data) {
        guard let type, !value.isEmpty else { return }
        switch type {
        case "public.utf8-plain-text":
            if case .none = kind { kind = .text(String(data: value, encoding: .utf8) ?? "") }
        case "public.utf16-external-plain-text":
            if case .none = kind,
               let s = String(data: value, encoding: .utf16) {
                kind = .text(s)
            }
        case "public.png":
            kind = .image(value)
        case "public.heic":
            if let nsImage = NSImage(data: value),
               let tiff = nsImage.tiffRepresentation as Data?,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                kind = .image(png)
            }
        default:
            break
        }
    }
}
