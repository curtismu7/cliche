import AppKit
import Foundation

/// Reads Clipy's per-clip `.data` files from
/// `~/Library/Application Support/com.clipy-app.Clipy/`.
/// Each `.data` file is an `NSKeyedArchiver` archive of a `CPYClipData`
/// object (an NSArray of pasteboard types and values). Text and image
/// items are imported; other types are skipped.
public struct ClipyImporter: ClipboardImporter {
    public let name = "Clipy"

    public init() {}

    public var isAvailable: Bool { !Self.dataFiles.isEmpty }

    private static var supportDirectory: URL {
        URL(fileURLWithPath: "\(NSHomeDirectory())/Library/Application Support/com.clipy-app.Clipy")
    }

    private static var dataFiles: [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: supportDirectory, includingPropertiesForKeys: nil)
        else { return [] }
        return entries.filter { $0.pathExtension == "data" }
    }

    @MainActor
    public func importAll(into store: HistoryStore) throws -> ImportResult {
        let files = Self.dataFiles
        guard !files.isEmpty else {
            throw NSError(domain: "ClipyImporter", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Clipy storage not found."])
        }
        var result = ImportResult()
        // Newest first by mtime.
        let sorted = files.sorted { lhs, rhs in
            let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            return l > r
        }
        for file in sorted {
            let outcome = importFile(file, into: store)
            switch outcome {
            case .text: result.importedTexts += 1
            case .image: result.importedImages += 1
            case .skipped: result.skipped += 1
            }
        }
        return result
    }

    private enum Outcome { case text, image, skipped }

    private func importFile(_ url: URL, into store: HistoryStore) -> Outcome {
        // NSKeyedUnarchiver returns a CPYClipData (a custom NSObject) whose
        // `types` and `values` arrays we read via KVC. Falls back to a
        // generic NSDictionary if the class isn't available (Clipy not
        // linked): the archive still decodes plist types.
        guard let data = try? Data(contentsOf: url),
              let root = LegacyKeyedUnarchiver.topLevelObject(from: data)
        else { return .skipped }

        // Pin state lives in Clipy's Realm DB (CPYClip.isPinned), not in the
        // archived .data file. We probe for it via KVC in case a future
        // build embeds it; otherwise default to unpinned.
        let pinned: Bool = (root as? NSObject)
            .flatMap { $0.value(forKey: "isPinned") as? Bool } ?? false

        // Try KVC on a CPYClipData-like object.
        if let clipData = root as? NSObject,
           let types = clipData.value(forKey: "types") as? [String],
           let values = clipData.value(forKey: "values") as? [Data] {
            return importTypesAndValues(types, values, pinned: pinned, into: store)
        }
        // Legacy: archived NSDictionary.
        if let dict = root as? [String: Any] {
            return importItem(dict, pinned: pinned, into: store)
        }
        return .skipped
    }

    private func importTypesAndValues(_ types: [String], _ values: [Data],
                                       pinned: Bool, into store: HistoryStore) -> Outcome {
        var best = Outcome.skipped
        for (type, value) in zip(types, values) where !value.isEmpty {
            switch importEntry(type: type, value: value, pinned: pinned, into: store) {
            case .text where best != .text: best = .text
            case .image where best == .skipped: best = .image
            default: break
            }
        }
        return best
    }

    private func importItem(_ item: [String: Any], pinned: Bool, into store: HistoryStore) -> Outcome {
        var best = Outcome.skipped
        for (type, value) in item {
            if let data = value as? Data, !data.isEmpty {
                switch importEntry(type: type, value: data, pinned: pinned, into: store) {
                case .text where best != .text: best = .text
                case .image where best == .skipped: best = .image
                default: break
                }
            }
        }
        return best
    }

    private func importEntry(type: String, value: Data, pinned: Bool, into store: HistoryStore) -> Outcome {
        switch type {
        case "public.utf8-plain-text", "public.text", "NSStringPboardType":
            guard let s = String(data: value, encoding: .utf8),
                  !s.isEmpty,
                  !store.items.contains(where: { $0.dedupeKey == "t:\(s)" })
            else { return .skipped }
            store.addText(s, pinned: pinned)
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
                store.addImage(png, pinned: pinned)
                return .image
            }
            return .skipped
        default:
            return .skipped
        }
    }
}
