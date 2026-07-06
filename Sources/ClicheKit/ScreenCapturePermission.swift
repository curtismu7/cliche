import AppKit
import CoreGraphics

/// Screen Recording permission checks. macOS ties permission to each app
/// path + signature — duplicate installs (Homebrew vs ~/Applications vs
/// make install) are the usual reason Settings looks enabled but capture
/// still fails.
public enum ScreenCapturePermission {
    private static var didShowHelpThisSession = false

    public static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Opens the Screen & System Audio Recording pane in System Settings.
    public static func openSettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    /// Other common install locations besides the running copy.
    public static func duplicateInstallPaths(excluding current: String? = nil) -> [String] {
        let currentPath = current ?? Bundle.main.bundlePath
        return [
            "/Applications/Cliche.app",
            NSHomeDirectory() + "/Applications/Cliche.app",
        ].filter { $0 != currentPath && FileManager.default.fileExists(atPath: $0) }
    }

    /// Shows setup help once per launch when permission is missing. Returns
    /// true only when capture can proceed.
    @MainActor
    public static func ensureGranted(appName: String = "Cliché") -> Bool {
        guard !isGranted else { return true }
        guard !didShowHelpThisSession else { return false }
        didShowHelpThisSession = true

        let appPath = Bundle.main.bundlePath
        var detail = """
        macOS has not granted Screen Recording to this copy of \(appName):

        \(appPath)

        1. Quit every copy of Cliché.
        2. System Settings → Screen & System Audio Recording — turn OFF all "Cliché" entries.
        3. Reopen Cliché from the path above only.
        4. Turn Cliché ON in that same settings pane, then quit and reopen once more.
        """
        let duplicates = duplicateInstallPaths(excluding: appPath)
        if !duplicates.isEmpty {
            detail += "\n\nRemove extra copies so only one remains:\n"
            detail += duplicates.map { "• \($0)" }.joined(separator: "\n")
        }

        let alert = NSAlert()
        alert.messageText = "Screen Recording permission needed"
        alert.informativeText = detail
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn {
            openSettings()
        }
        return false
    }
}
