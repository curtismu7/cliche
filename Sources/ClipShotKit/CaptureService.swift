import AppKit

public enum CaptureMode {
    case region
    case window
    case fullScreen
}

/// Takes screenshots by shelling out to the system `screencapture` tool,
/// which provides the native crosshair/window-picker UI. The result lands as
/// a timestamped PNG on the Desktop and is also copied to the clipboard.
public final class CaptureService {
    public init() {}

    public func capture(_ mode: CaptureMode, completion: (() -> Void)? = nil) {
        let outputURL = Self.outputURL()
        var arguments: [String]
        switch mode {
        case .region: arguments = ["-i"]
        case .window: arguments = ["-iWo"]
        case .fullScreen: arguments = []
        }
        arguments.append(outputURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = arguments
        process.terminationHandler = { _ in
            DispatchQueue.main.async {
                // No file means the user pressed Esc — silently do nothing,
                // matching the native ⌘⇧4 behavior.
                if let data = try? Data(contentsOf: outputURL) {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setData(data, forType: .png)
                }
                completion?()
            }
        }
        do {
            try process.run()
        } catch {
            NSLog("ClipShot: failed to launch screencapture: \(error)")
        }
    }

    static func outputURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        return desktop.appendingPathComponent(
            "ClipShot \(formatter.string(from: Date())).png")
    }
}
