import AppKit
import Foundation

/// Common interface for clipboard-history importers. Each source (Maccy,
/// Paste, Clipy) implements this; the UI lists every available importer
/// and runs the chosen one against a HistoryStore.
public protocol ClipboardImporter {
    /// Human-readable product name, e.g. "Maccy".
    var name: String { get }
    /// True when the source's data store exists on this Mac.
    var isAvailable: Bool { get }
    /// Imports every item into `store`, skipping duplicates. Runs on the
    /// main actor because HistoryStore is @Observable and not thread-safe.
    @MainActor
    func importAll(into store: HistoryStore) throws -> ImportResult
}

public struct ImportResult {
    public var importedTexts = 0
    public var importedImages = 0
    public var skipped = 0

    public var summary: String {
        "Imported \(importedTexts) text + \(importedImages) image items (\(skipped) skipped)."
    }
}

/// Lists every importer whose source store is present. Empty when nothing
/// is installed to import from.
public enum ClipboardImporters {
    public static var all: [ClipboardImporter] {
        [MaccyImporter(), PasteImporter(), ClipyImporter()]
    }

    public static var available: [ClipboardImporter] {
        all.filter(\.isAvailable)
    }
}
