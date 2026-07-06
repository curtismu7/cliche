import AppKit
import SQLite3

/// Reads Maccy's Core Data SQLite store and converts each history item to a
/// `ClipItem`, writing text into `history.json` and images into the images
/// directory alongside the existing history.
public struct MaccyImporter: ClipboardImporter {
    public let name = "Maccy"

    public var isAvailable: Bool { Self.defaultDatabaseURL != nil }

    /// Default Maccy storage path (sandboxed container).
    public static var defaultDatabaseURL: URL? {
        let path = "\(NSHomeDirectory())/Library/Containers/org.p0deje.Maccy/Data/Library/Application Support/Maccy/Storage.sqlite"
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    @MainActor
    public func importAll(into store: HistoryStore) throws -> ImportResult {
        guard let dbURL = Self.defaultDatabaseURL else {
            throw NSError(domain: "MaccyImporter", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Maccy storage not found."])
        }
        let db = try Connection(url: dbURL)
        let rows = try db.fetchItems()
        var result = ImportResult()
        for row in rows {
            switch row.kind {
            case .text(let text):
                if !text.isEmpty,
                   !store.items.contains(where: { $0.dedupeKey == "t:\(text)" }) {
                    store.addText(text)
                    result.importedTexts += 1
                } else {
                    result.skipped += 1
                }
            case .image(let data):
                let sha = HistoryStore.sha256(data)
                if !store.items.contains(where: { $0.dedupeKey == "i:\(sha)" }) {
                    store.addImage(data)
                    result.importedImages += 1
                } else {
                    result.skipped += 1
                }
            case .none:
                result.skipped += 1
            }
        }
        return result
    }
}

/// Minimal SQLite reader — avoids linking a C library. Reads only what the
/// importers need: rows and columns from a single database file.
final class Connection {
    private let db: OpaquePointer

    init(url: URL) throws {
        var handle: OpaquePointer?
        let code = sqlite3_open(url.path, &handle)
        guard code == SQLITE_OK, let db = handle else {
            sqlite3_close(handle)
            throw NSError(domain: "ImporterConnection", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Could not open database."])
        }
        self.db = db
    }

    deinit { sqlite3_close(db) }

    /// Runs a SELECT and maps each row via `mapper`. Returns the array of
    /// mapped values in row order.
    func query<T>(_ sql: String, _ mapper: (OpaquePointer?) -> T) throws -> [T] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(domain: "ImporterConnection", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Could not prepare query."])
        }
        defer { sqlite3_finalize(stmt) }
        var out: [T] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(mapper(stmt))
        }
        return out
    }

    static func columnString(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let cstr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cstr)
    }

    static func columnBlob(_ stmt: OpaquePointer?, _ index: Int32) -> Data {
        let bytes = sqlite3_column_blob(stmt, index)
        let length = Int(sqlite3_column_bytes(stmt, index))
        guard let bytes, length > 0 else { return Data() }
        return Data(bytes: bytes, count: length)
    }
}

struct MaccyRow {
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

/// Internal: Connection extension that walks Maccy's two-table layout and
/// merges each item's content rows into one `MaccyRow` with the best kind.
extension Connection {
    func fetchItems() throws -> [MaccyRow] {
        let sql = """
        SELECT i.Z_PK, i.ZLASTCOPIEDAT, i.ZTITLE, c.ZTYPE, c.ZVALUE
        FROM ZHISTORYITEM i
        LEFT JOIN ZHISTORYITEMCONTENT c ON c.ZITEM = i.Z_PK
        ORDER BY i.ZLASTCOPIEDAT DESC
        """
        var byItem: [Int64: MaccyRow] = [:]
        _ = try query(sql) { stmt in
            let pk = sqlite3_column_int64(stmt, 0)
            let timestamp = sqlite3_column_double(stmt, 1)
            let title = Self.columnString(stmt, 2)
            let type = Self.columnString(stmt, 3)
            let value = Self.columnBlob(stmt, 4)

            if byItem[pk] == nil {
                byItem[pk] = MaccyRow(pk: pk, timestamp: timestamp, title: title, kind: .none)
            }
            byItem[pk]?.consider(type: type, value: value)
            return Void()
        }
        return byItem.values.sorted { $0.timestamp > $1.timestamp }
    }
}
