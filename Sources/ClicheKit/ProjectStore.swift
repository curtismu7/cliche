import Foundation

/// Non-destructive editing: a sidecar "project" per capture holding the
/// original (pre-annotation) PNG plus the annotation layers and beautify
/// config, so a saved capture can be reopened and re-edited.
public struct AnnotationProject: Codable, Equatable {
    public var annotations: [Annotation]
    public var config: BeautifyConfig
    public init(annotations: [Annotation], config: BeautifyConfig) {
        self.annotations = annotations
        self.config = config
    }
}

public final class ProjectStore {
    private let root: URL

    public init(directory: URL? = nil) {
        self.root = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cliche/Projects", isDirectory: true)
    }

    private func folder(for captureURL: URL) -> URL {
        root.appendingPathComponent(captureURL.lastPathComponent, isDirectory: true)
    }
    private func originalURL(for captureURL: URL) -> URL {
        folder(for: captureURL).appendingPathComponent("original.png")
    }
    private func projectURL(for captureURL: URL) -> URL {
        folder(for: captureURL).appendingPathComponent("project.json")
    }

    /// The pre-annotation base for a capture, if a project exists.
    public func originalPNG(for captureURL: URL) -> Data? {
        try? Data(contentsOf: originalURL(for: captureURL))
    }

    public func load(for captureURL: URL) -> AnnotationProject? {
        guard let data = try? Data(contentsOf: projectURL(for: captureURL))
        else { return nil }
        return try? JSONDecoder().decode(AnnotationProject.self, from: data)
    }

    /// Persists layers for a capture. `originalPNG` is written only on the
    /// first save so later saves never clobber the true original.
    public func save(
        _ project: AnnotationProject, originalPNG: Data, for captureURL: URL
    ) throws {
        let dir = folder(for: captureURL)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        let originalFile = originalURL(for: captureURL)
        if !FileManager.default.fileExists(atPath: originalFile.path) {
            try originalPNG.write(to: originalFile)
        }
        let data = try JSONEncoder().encode(project)
        try data.write(to: projectURL(for: captureURL))
    }

    /// Removes the sidecar when its capture is deleted.
    public func remove(for captureURL: URL) {
        try? FileManager.default.removeItem(at: folder(for: captureURL))
    }
}
