import Foundation
import Observation

/// Index of past screenshots (files stay wherever they were saved, e.g. the
/// Desktop). Entries whose file has been moved or deleted are pruned on load.
@Observable
public final class CapturesStore {
    public struct Capture: Identifiable, Codable, Equatable {
        public let id: UUID
        public let date: Date
        public let path: String

        public init(id: UUID, date: Date, path: String) {
            self.id = id
            self.date = date
            self.path = path
        }
    }

    public private(set) var captures: [Capture] = []

    private let indexFile: URL

    public init(directory: URL) {
        indexFile = directory.appendingPathComponent("captures.json")
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        load()
    }

    public func add(path: String) {
        captures.insert(Capture(id: UUID(), date: Date(), path: path), at: 0)
        save()
    }

    /// Removes the index entry; optionally moves the file to the Trash.
    /// The capture's annotation project (if any) goes with it.
    public func remove(_ capture: Capture, deleteFile: Bool) {
        captures.removeAll { $0.id == capture.id }
        let url = URL(fileURLWithPath: capture.path)
        ProjectStore().remove(for: url)
        if deleteFile {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexFile),
              let decoded = try? JSONDecoder().decode([Capture].self, from: data)
        else { return }
        captures = decoded.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(captures)
            try data.write(to: indexFile, options: .atomic)
        } catch {
            NSLog("Cliche: failed to save captures index: \(error)")
        }
    }
}
