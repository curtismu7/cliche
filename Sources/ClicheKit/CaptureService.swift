import AppKit

public enum CaptureMode: String, Codable, Equatable {
    case region
    case window
    case fullScreen
}

/// Takes screenshots by shelling out to the system `screencapture` tool,
/// which provides the native crosshair/window-picker UI. The result lands as
/// a timestamped PNG on the Desktop and is also copied to the clipboard.
public final class CaptureService {
    public init() {}

    /// `onSaved` runs on the main queue with the file URL when a screenshot
    /// was actually written (not when the user cancels with Esc).
    public func capture(
        _ mode: CaptureMode,
        format: AppSettings.ImageFormat = .png,
        copyToClipboard: Bool = true,
        showCursor: Bool = false,
        windowShadow: Bool = false,
        outputURL explicitURL: URL? = nil,
        onSaved: ((URL) -> Void)? = nil
    ) {
        let outputURL = explicitURL ?? Self.outputURL(fileExtension: format.fileExtension)
        var arguments: [String]
        switch mode {
        case .region: arguments = ["-i"]
        case .window: arguments = windowShadow ? ["-iW"] : ["-iWo"]
        case .fullScreen: arguments = []
        }
        if showCursor { arguments.append("-C") }
        arguments += ["-t", format == .png ? "png" : "jpg", outputURL.path]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = arguments
        process.terminationHandler = { _ in
            DispatchQueue.main.async {
                // No file means the user pressed Esc — silently do nothing,
                // matching the native ⌘⇧4 behavior.
                if let data = try? Data(contentsOf: outputURL) {
                    if copyToClipboard {
                        ClipboardWriter.writeImage(pngData: data)
                    }
                    onSaved?(outputURL)
                }
            }
        }
        do {
            try process.run()
        } catch {
            NSLog("Cliche: failed to launch screencapture: \(error)")
        }
    }

    public static func outputURL(fileExtension: String = "png") -> URL {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        return CaptureNaming.outputURL(
            directory: desktop, pattern: CaptureNaming.defaultPattern,
            fileExtension: fileExtension)
    }
}
