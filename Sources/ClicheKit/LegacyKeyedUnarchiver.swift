import Foundation

/// Decodes legacy NSKeyedArchiver blobs (Clipy, CopyClip) without secure coding.
enum LegacyKeyedUnarchiver {
    static func topLevelObject(from data: Data) -> Any? {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = false
        defer { unarchiver.finishDecoding() }
        return unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey)
    }
}
