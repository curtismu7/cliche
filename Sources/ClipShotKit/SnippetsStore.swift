import AppKit
import Foundation
import Observation

/// User-defined reusable text templates with variables, persisted alongside
/// history. Variables: %DATE%, %TIME%, %CLIPBOARD%.
@Observable
public final class SnippetsStore {
    public struct Snippet: Identifiable, Codable, Equatable {
        public let id: UUID
        public var name: String
        public var template: String

        public init(id: UUID = UUID(), name: String, template: String) {
            self.id = id
            self.name = name
            self.template = template
        }
    }

    public private(set) var snippets: [Snippet] = []

    private let file: URL

    public init(directory: URL) {
        file = directory.appendingPathComponent("snippets.json")
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        load()
    }

    public func add(name: String, template: String) {
        snippets.append(Snippet(name: name, template: template))
        save()
    }

    public func update(_ snippet: Snippet) {
        guard let index = snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        snippets[index] = snippet
        save()
    }

    public func remove(_ snippet: Snippet) {
        snippets.removeAll { $0.id == snippet.id }
        save()
    }

    /// Renders a template against explicit inputs (pure; used by tests).
    public static func render(template: String, clipboard: String, date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        return template
            .replacingOccurrences(of: "%DATE%", with: dateFormatter.string(from: date))
            .replacingOccurrences(of: "%TIME%", with: timeFormatter.string(from: date))
            .replacingOccurrences(of: "%CLIPBOARD%", with: clipboard)
    }

    /// Renders using the live clipboard and current date.
    public func render(_ snippet: Snippet) -> String {
        Self.render(
            template: snippet.template,
            clipboard: NSPasteboard.general.string(forType: .string) ?? "",
            date: Date())
    }

    private func load() {
        guard let data = try? Data(contentsOf: file),
              let decoded = try? JSONDecoder().decode([Snippet].self, from: data)
        else { return }
        snippets = decoded
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(snippets)
            try data.write(to: file, options: .atomic)
        } catch {
            NSLog("ClipShot: failed to save snippets: \(error)")
        }
    }
}
