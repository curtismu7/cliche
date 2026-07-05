import CryptoKit
import Foundation
import Observation

@Observable
public final class HistoryStore {
    public private(set) var items: [ClipItem] = []

    public let directory: URL
    public let maxTexts: Int
    public let maxImages: Int

    private var imagesDirectory: URL {
        directory.appendingPathComponent("images", isDirectory: true)
    }
    private var historyFile: URL {
        directory.appendingPathComponent("history.json")
    }

    public init(directory: URL, maxTexts: Int = 150, maxImages: Int = 50) {
        self.directory = directory
        self.maxTexts = maxTexts
        self.maxImages = maxImages
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

    /// On-disk URL of an image item's PNG (for opening in the editor).
    public func imageFileURL(for item: ClipItem) -> URL? {
        guard case .image(let fileName, _) = item.kind else { return nil }
        return imagesDirectory.appendingPathComponent(fileName)
    }

    public func imageData(for item: ClipItem) -> Data? {
        guard case .image(let fileName, _) = item.kind else { return nil }
        return try? Data(contentsOf: imagesDirectory.appendingPathComponent(fileName))
    }

    /// Replaces a text item's content in place (position and pin state kept).
    public func updateText(_ item: ClipItem, to newText: String) {
        guard case .text = item.kind, !newText.isEmpty,
              let index = items.firstIndex(where: { $0.id == item.id })
        else { return }
        items[index] = ClipItem(
            id: item.id, date: Date(), kind: .text(newText),
            pinned: items[index].pinned)
        save()
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
        // Caps are per kind and apply to unpinned items only; pinned items
        // are never evicted.
        evictOldest(where: { if case .text = $0.kind { return true }; return false },
                    cap: maxTexts)
        evictOldest(where: { if case .image = $0.kind { return true }; return false },
                    cap: maxImages)
        save()
    }

    private func evictOldest(where matches: (ClipItem) -> Bool, cap: Int) {
        while items.filter({ !$0.pinned && matches($0) }).count > cap {
            guard let last = items.lastIndex(where: { !$0.pinned && matches($0) })
            else { return }
            deleteImageFile(of: items.remove(at: last))
        }
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
            NSLog("Cliche: failed to save history: \(error)")
        }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
