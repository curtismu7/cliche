import AppKit
import Foundation

/// Reads FIPLAB's CopyClip and CopyClip 2 history. Both apps are sandboxed
/// to `~/Library/Containers/com.fiplab.clipboard` and persist clips as an
/// `NSKeyedArchiver` archive (typically `clippings.data`) inside their
/// Application Support folder. Each clip is an `NSDictionary` whose values
/// are pasteboard-type → `NSData` pairs (plus a few metadata keys like
/// `date`, `sourceApp`). Text and image types are imported; other types
/// (RTF, HTML, file URLs) are skipped.
public struct CopyClipImporter: ClipboardImporter {
    public let name: String

    public var isAvailable: Bool { dataFile != nil }

    /// `true` for CopyClip 2 (the paid text-only version), `false` for the
    /// original CopyClip. Both share the same container id and on-disk
    /// format, so the importer logic is identical.
    private let isCopyClip2: Bool

    public init(isCopyClip2: Bool = false) {
        self.isCopyClip2 = isCopyClip2
        self.name = isCopyClip2 ? "CopyClip 2" : "CopyClip"
    }

    private static var containerURL: URL {
        URL(fileURLWithPath: "\(NSHomeDirectory())/Library/Containers/com.fiplab.clipboard")
    }

    private var dataFile: URL? {
        let support = Self.containerURL
            .appendingPathComponent("Data/Library/Application Support", isDirectory: true)
        // FIPLAB has used a few different filenames across versions; pick
        // the first one that exists.
        let candidates = ["clippings.data", "clipboard.data", "Clipboard.data",
                           "Clippings.data", "history.data"]
        let fm = FileManager.default
        for name in candidates {
            let url = support.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) { return url }
        }
        // Fall back to any .data file in the support folder.
        if let entries = try? fm.contentsOfDirectory(at: support,
                                                     includingPropertiesForKeys: nil) {
            return entries.first { $0.pathExtension == "data" }
        }
        return nil
    }

    @MainActor
    public func importAll(into store: HistoryStore) throws -> ImportResult {
        guard let url = dataFile else {
            throw NSError(domain: "CopyClipImporter", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "\(name) storage not found."])
        }
        let data = try Data(contentsOf: url)
        // CopyClip archives an NSArray of NSDictionary clips (or a single
        // NSDictionary in older builds). Try both.
        guard let root = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) else {
            throw NSError(domain: "CopyClipImporter", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Could not read \(name) archive."])
        }
        var result = ImportResult()
        let clips: [NSDictionary] = {
            if let array = root as? [NSDictionary] { return array }
            if let single = root as? NSDictionary { return [single] }
            return []
        }()
        // Newest first if dates are available.
        let sorted = clips.sorted { lhs, rhs in
            Self.date(from: lhs) > Self.date(from: rhs)
        }
        for clip in sorted {
            let outcome = importClip(clip, into: store)
            switch outcome {
            case .text: result.importedTexts += 1
            case .image: result.importedImages += 1
            case .skipped: result.skipped += 1
            }
        }
        return result
    }

    private enum Outcome { case text, image, skipped }

    private func importClip(_ clip: NSDictionary, into store: HistoryStore) -> Outcome {
        // A clip dict maps pasteboard type strings to NSData values, plus a
        // few metadata keys we ignore. Treat unknown keys as non-content.
        let metadataKeys: Set<String> = ["date", "sourceApp", "source", "timestamp",
                                          "hash", "id", "pinned", "favorite"]
        var best = Outcome.skipped
        for (key, value) in clip {
            guard let type = key as? String,
                  let data = value as? Data,
                  !data.isEmpty,
                  !metadataKeys.contains(type)
            else { continue }
            switch importEntry(type: type, value: data, into: store) {
            case .text where best != .text: best = .text
            case .image where best == .skipped: best = .image
            default: break
            }
        }
        return best
    }

    private func importEntry(type: String, value: Data, into store: HistoryStore) -> Outcome {
        switch type {
        case "public.utf8-plain-text", "public.text", "NSStringPboardType",
             "public.utf16-external-plain-text", "public.utf16-plain-text":
            let text = String(data: value, encoding: .utf8)
                ?? String(data: value, encoding: .utf16)
                ?? ""
            guard !text.isEmpty,
                  !store.items.contains(where: { $0.dedupeKey == "t:\(text)" })
            else { return .skipped }
            store.addText(text)
            return .text
        case "public.png", "public.heic", "public.tiff", "public.jpeg",
             "NSPasteboardTypePNG", "Apple TIFF pasteboard type", "NSPasteboardTypeTIFF":
            if let nsImage = NSImage(data: value),
               let tiff = nsImage.tiffRepresentation as Data?,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                let sha = HistoryStore.sha256(png)
                guard !store.items.contains(where: { $0.dedupeKey == "i:\(sha)" })
                else { return .skipped }
                store.addImage(png)
                return .image
            }
            return .skipped
        default:
            return .skipped
        }
    }

    private static func date(from clip: NSDictionary) -> Date {
        if let d = clip["date"] as? Date { return d }
        if let ts = clip["timestamp"] as? TimeInterval { return Date(timeIntervalSince1970: ts) }
        if let ts = clip["timestamp"] as? NSNumber { return Date(timeIntervalSince1970: ts.doubleValue) }
        return .distantPast
    }
}
