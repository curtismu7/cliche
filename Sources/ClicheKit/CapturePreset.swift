import Foundation

/// A named capture profile: one click bundles mode, format, clipboard
/// behavior, destination folder, and filename pattern (Snagit-style).
public struct CapturePreset: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var mode: CaptureMode
    public var format: AppSettings.ImageFormat
    public var copyToClipboard: Bool
    /// nil = Desktop (the default destination).
    public var destinationPath: String?
    public var filenamePattern: String

    public init(
        id: UUID = UUID(), name: String, mode: CaptureMode,
        format: AppSettings.ImageFormat = .png, copyToClipboard: Bool = true,
        destinationPath: String? = nil,
        filenamePattern: String = CaptureNaming.defaultPattern
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.format = format
        self.copyToClipboard = copyToClipboard
        self.destinationPath = destinationPath
        self.filenamePattern = filenamePattern
    }

    public var destinationURL: URL {
        if let path = destinationPath, !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath,
                       isDirectory: true)
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }
}

/// Filename construction for captures — the single source of naming truth
/// for both the default path and presets. Tokens: %DATE% and %TIME%.
public enum CaptureNaming {
    public static let defaultPattern = "Cliché %DATE% at %TIME%"

    public static func filename(
        pattern: String, fileExtension: String, date: Date = Date()
    ) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH.mm.ss"
        let name = pattern
            .replacingOccurrences(of: "%DATE%", with: dateFormatter.string(from: date))
            .replacingOccurrences(of: "%TIME%", with: timeFormatter.string(from: date))
        return "\(name).\(fileExtension)"
    }

    public static func outputURL(
        directory: URL, pattern: String, fileExtension: String, date: Date = Date()
    ) -> URL {
        directory.appendingPathComponent(
            filename(pattern: pattern, fileExtension: fileExtension, date: date))
    }

    /// Like `outputURL`, but never overwrites: same-second captures and
    /// token-less patterns get " 2", " 3", … suffixes.
    public static func uniqueOutputURL(
        directory: URL, pattern: String, fileExtension: String, date: Date = Date()
    ) -> URL {
        let base = outputURL(
            directory: directory, pattern: pattern,
            fileExtension: fileExtension, date: date)
        guard FileManager.default.fileExists(atPath: base.path) else { return base }
        let stem = base.deletingPathExtension().lastPathComponent
        for n in 2...999 {
            let candidate = directory
                .appendingPathComponent("\(stem) \(n).\(fileExtension)")
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return base
    }
}
