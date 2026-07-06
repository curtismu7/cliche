import AppKit
import CoreGraphics

/// Screen Recording permission checks. macOS ties permission to each app
/// path + code signature — ad-hoc dev builds change signature every compile,
/// so keep one install at /Applications/Cliche.app and re-toggle after updates.
public enum ScreenCapturePermission {
    private static var didShowHelpThisSession = false
    /// CGRequestScreenCaptureAccess() reopens System Settings on repeat calls when
    /// permission is stale — only invoke it from explicit user actions.
    private static var didRequestAccessThisSession = false
    private static let grantedExecutableModKey = "screenCaptureGrantedExecutableMod"

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

    /// Checks permission only — never opens Settings or shows a system prompt.
    @MainActor
    @discardableResult
    public static func registerWithSystemIfNeeded() -> Bool {
        if isGranted { noteGrantedExecutableIfNeeded() }
        return isGranted
    }

    /// User clicked Enable / Show prompt — may invoke the one-time macOS dialog.
    @MainActor
    @discardableResult
    public static func requestAccessUserInitiated() -> Bool {
        if isGranted {
            noteGrantedExecutableIfNeeded()
            return true
        }
        requestAccessOnce()
        if isGranted { noteGrantedExecutableIfNeeded() }
        return isGranted
    }

    /// Returns true only when capture can proceed. Never auto-opens Settings;
    /// shows a one-time help alert when permission is missing.
    @MainActor
    public static func ensureGranted(appName: String = "Cliché") -> Bool {
        if isGranted {
            noteGrantedExecutableIfNeeded()
            return true
        }

        guard !didShowHelpThisSession else { return false }
        didShowHelpThisSession = true

        let appPath = Bundle.main.bundlePath
        var detail = """
        Cliché needs Screen Recording for this exact copy:

        \(appPath)

        In System Settings → Privacy & Security → Screen & System Audio Recording:
        turn Cliché OFF, then ON again, quit Cliché completely, and reopen it.

        If Cliché is missing from the list, click "Show Permission Prompt" below.
        """
        if executableWasRebuiltSinceLastGrant {
            detail += """

            This build's signature changed since Screen Recording was last enabled \
            (common after `brew upgrade --cask cliche` or `make install`). \
            Toggling OFF then ON fixes it — no need to reset TCC every time.
            """
        } else {
            detail += """

            If nothing works, quit Cliché and run:
            tccutil reset ScreenCapture org.coachcurtis.cliche
            Then open only \(standardInstallPath) and use "Show Permission Prompt".
            """
        }
        let duplicates = duplicateInstallPaths(excluding: appPath)
        if !duplicates.isEmpty {
            detail += "\n\nDelete extra copies:\n"
            detail += duplicates.map { "• \($0)" }.joined(separator: "\n")
        }

        let alert = NSAlert()
        alert.messageText = "Screen Recording permission needed"
        alert.informativeText = detail
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Show Permission Prompt")
        alert.addButton(withTitle: "Not Now")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openSettings()
        } else if response == .alertSecondButtonReturn {
            _ = requestAccessUserInitiated()
        }
        return false
    }

    /// Triggers the one-time macOS registration dialog when the user asks for it.
    private static func requestAccessOnce() {
        guard !didRequestAccessThisSession else { return }
        didRequestAccessThisSession = true
        _ = CGRequestScreenCaptureAccess()
    }

    /// Remember which executable build had permission so we can spot ad-hoc re-signs.
    private static func noteGrantedExecutableIfNeeded() {
        guard isGranted, let mod = executableModificationDate() else { return }
        UserDefaults.standard.set(mod.timeIntervalSince1970, forKey: grantedExecutableModKey)
    }

    private static func executableModificationDate() -> Date? {
        guard let url = Bundle.main.executableURL else { return nil }
        return (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
    }

    /// True when the binary was rebuilt after permission last worked (ad-hoc signing).
    static var executableWasRebuiltSinceLastGrant: Bool {
        let stored = UserDefaults.standard.double(forKey: grantedExecutableModKey)
        guard stored > 0, let current = executableModificationDate() else { return false }
        return current.timeIntervalSince1970 > stored + 1
    }
}
