import AppKit
import CoreGraphics

/// Screen Recording permission checks. macOS ties permission to each app
/// path + code signature — ad-hoc dev builds change signature every compile,
/// so keep one install at /Applications/Cliche.app and re-toggle after updates.
public enum ScreenCapturePermission {
    private static var didShowHelpThisSession = false
    /// CGRequestScreenCaptureAccess() reopens System Settings on repeat calls when
    /// permission is stale — only invoke it once per app session.
    private static var didRequestAccessThisSession = false

    /// Where `make install` and the zip installer put the app.
    public static var standardInstallPath: String {
        "/Applications/Cliche.app"
    }

    public static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Opens the Screen & System Audio Recording pane in System Settings.
    public static func openSettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    /// Other install locations that cause permission confusion if both exist.
    public static func duplicateInstallPaths(excluding current: String? = nil) -> [String] {
        let currentPath = current ?? Bundle.main.bundlePath
        let homeCopy = NSHomeDirectory() + "/Applications/Cliche.app"
        return [
            standardInstallPath,
            homeCopy,
        ].filter { $0 != currentPath && FileManager.default.fileExists(atPath: $0) }
    }

    /// Warn once at launch when a second copy exists — the usual cause of a
    /// Screen Recording loop (permission granted to the wrong path).
    @MainActor
    public static func warnAboutDuplicateInstallsIfNeeded() {
        let appPath = Bundle.main.bundlePath
        let duplicates = duplicateInstallPaths(excluding: appPath)
        guard !duplicates.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "Multiple Cliché installs detected"
        alert.informativeText = """
        You're running:
        \(appPath)

        Another copy also exists:
        \(duplicates.joined(separator: "\n"))

        Screen Recording permission applies to one path only. Delete the extra \
        copy and keep \(standardInstallPath), then reset permission:
        tccutil reset ScreenCapture org.coachcurtis.cliche
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Ask macOS to add Cliché to the Screen Recording list. Safe to call at
    /// launch — runs at most once per session and does not open Settings.
    @MainActor
    @discardableResult
    public static func registerWithSystemIfNeeded() -> Bool {
        if isGranted { return true }
        requestAccessOnce()
        return isGranted
    }

    /// Returns true only when capture can proceed. When permission is missing,
    /// requests access at most once per session, then shows a one-time help alert.
    @MainActor
    public static func ensureGranted(appName: String = "Cliché") -> Bool {
        if isGranted { return true }

        requestAccessOnce()
        if isGranted { return true }

        guard !didShowHelpThisSession else { return false }
        didShowHelpThisSession = true

        let appPath = Bundle.main.bundlePath
        var detail = """
        Cliché needs Screen Recording for this exact copy:

        \(appPath)

        If macOS just prompted you, approve it and **quit + reopen Cliché** —
        the permission only takes effect after a restart.

        If no prompt appeared:
        1. Quit every copy of Cliché.
        2. System Settings → Privacy & Security → Screen & System Audio Recording.
        3. Turn OFF every Cliché entry, then run in Terminal:
           tccutil reset ScreenCapture org.coachcurtis.cliche
        4. Open only \(standardInstallPath).
        5. Trigger a capture (⌘⇧6) — macOS will prompt. Approve, quit, reopen.

        Rebuilding or upgrading Cliché changes its signature — toggle Screen Recording again after `brew upgrade --cask cliche`.
        """
        let duplicates = duplicateInstallPaths(excluding: appPath)
        if !duplicates.isEmpty {
            detail += "\n\nDelete extra copies:\n"
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

    /// Triggers the one-time macOS registration dialog when needed.
    private static func requestAccessOnce() {
        guard !didRequestAccessThisSession else { return }
        didRequestAccessThisSession = true
        _ = CGRequestScreenCaptureAccess()
    }
}
