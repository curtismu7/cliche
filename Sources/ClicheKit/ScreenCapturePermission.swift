import AppKit
import CoreGraphics

/// Screen Recording permission checks. macOS ties permission to each app
/// path + code signature — ad-hoc dev builds change signature every compile,
/// so Homebrew users should stick to one install path and re-toggle after
/// updates.
public enum ScreenCapturePermission {
    private static var didRequestAccessThisSession = false
    private static var didShowHelpThisSession = false

    public static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Call once at launch so macOS registers Cliché in the Screen Recording
    /// list. Preflight alone never adds the app — that causes a Settings loop.
    public static func prepareAtLaunch() {
        guard !isGranted else { return }
        requestAccessIfNeeded()
    }

    @discardableResult
    private static func requestAccessIfNeeded() -> Bool {
        guard !didRequestAccessThisSession else { return isGranted }
        didRequestAccessThisSession = true
        return CGRequestScreenCaptureAccess()
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

    /// Returns true only when capture can proceed.
    @MainActor
    public static func ensureGranted(appName: String = "Cliché") -> Bool {
        if isGranted { return true }
        if requestAccessIfNeeded(), isGranted { return true }

        guard !didShowHelpThisSession else { return false }
        didShowHelpThisSession = true

        let appPath = Bundle.main.bundlePath
        var detail = """
        Cliché still does not have Screen Recording for this copy:

        \(appPath)

        1. Quit Cliché completely.
        2. System Settings → Privacy & Security → Screen & System Audio Recording.
        3. Remove every "Cliché" entry (toggle off, or run in Terminal:
           tccutil reset ScreenCapture org.coachcurtis.cliche)
        4. Open /Applications/Cliche.app again.
        5. Turn Cliché ON in that pane, then quit and reopen once more.

        After updating/rebuilding the app, you must toggle permission again \
        because unsigned builds get a new identity each time.
        """
        let duplicates = duplicateInstallPaths(excluding: appPath)
        if !duplicates.isEmpty {
            detail += "\n\nRemove extra copies:\n"
            detail += duplicates.map { "• \($0)" }.joined(separator: "\n")
        }

        let alert = NSAlert()
        alert.messageText = "Screen Recording permission needed"
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open Settings")
        if alert.runModal() == .alertSecondButtonReturn {
            openSettings()
        }
        return false
    }
}
