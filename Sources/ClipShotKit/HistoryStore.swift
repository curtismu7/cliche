import CryptoKit
import Foundation
import Observation

@Observable
public final class HistoryStore {
    public private(set) var items: [ClipItem] = []

    public let directory: URL
    public let maxItems: Int

    private var imagesDirectory: URL {
        directory.appendingPathComponent("images", isDirectory: true)
    }
    private var historyFile: URL {
        directory.appendingPathComponent("history.json")
    }

    public init(directory: URL, maxItems: Int = 50) {
        self.directory = directory
        self.maxItems = maxItems
        try? FileManager.default.createDirectory(
            at: imagesDirectory, withIntermediateDirectories: true)
        load()
    }

    public func addText(_ text: String) {
        guard !text.isEmpty else { return }
        insert(ClipItem(id: UUID(), date: Date(), kind: .text(text)))
    }

    public func addImage(_ pngData: Data) {
        let sha = Self.sha256(pngData)
        if let existing = items.first(where: { $0.dedupeKey == "i:\(sha)" }) {
            // Same image already in history: move to front, reuse its file.
            insert(ClipItem(id: UUID(), date: Date(), kind: existing.kind))
            return
        }
        let fileName = UUID().uuidString + ".png"
        do {
            try pngData.write(to: imagesDirectory.appendingPathComponent(fileName))
        } catch {
            return
        }
        insert(ClipItem(id: UUID(), date: Date(), kind: .image(fileName: fileName, sha256: sha)))
    }

    public func imageData(for item: ClipItem) -> Data? {
        guard case .image(let fileName, _) = item.kind else { return nil }
        return try? Data(contentsOf: imagesDirectory.appendingPathComponent(fileName))
    }

    public func togglePin(_ item: ClipItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].pinned.toggle()
        save()
    }

    public func remove(_ item: ClipItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        deleteImageFile(of: items.remove(at: index))
        save()
    }

    /// Removes unpinned items only; pinned items survive a clear.
    public func clear() {
        for item in items where !item.pinned { deleteImageFile(of: item) }
        items = items.filter(\.pinned)
        save()
    }

    private func insert(_ item: ClipItem) {
        if let index = items.firstIndex(where: { $0.dedupeKey == item.dedupeKey }) {
            // Content already pinned: leave the pinned item alone.
            if items[index].pinned { return }
            // Otherwise the new item replaces it (image file is shared,
            // so nothing to delete).
            items.remove(at: index)
        }
        items.insert(item, at: 0)
        // The cap applies to unpinned items; pinned items are never evicted.
        while items.filter({ !$0.pinned }).count > maxItems {
            if let last = items.lastIndex(where: { !$0.pinned }) {
                deleteImageFile(of: items.remove(at: last))
            }
        }
        save()
    }

    private func deleteImageFile(of item: ClipItem) {
        guard case .image(let fileName, _) = item.kind else { return }
        try? FileManager.default.removeItem(
            at: imagesDirectory.appendingPathComponent(fileName))
    }

    private func load() {
        guard let data = try? Data(contentsOf: historyFile),
              let decoded = try? JSONDecoder().decode([ClipItem].self, from: data)
        else { return }
        // Drop image items whose backing file has gone missing.
        items = decoded.filter { item in
            guard case .image(let fileName, _) = item.kind else { return true }
            return FileManager.default.fileExists(
                atPath: imagesDirectory.appendingPathComponent(fileName).path)
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: historyFile, options: .atomic)
        } catch {
            NSLog("ClipShot: failed to save history: \(error)")
        }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
