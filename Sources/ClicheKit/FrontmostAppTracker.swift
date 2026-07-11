import AppKit

/// Remembers the last app that was frontmost before Cliché took focus.
public enum FrontmostAppTracker {
    private static var cachedApplication: NSRunningApplication?
    private static var observer: NSObjectProtocol?

    public static func startMonitoring() {
        guard observer == nil else { return }
        cachedApplication = otherApp(from: NSWorkspace.shared.frontmostApplication)
        let center = NSWorkspace.shared.notificationCenter
        observer = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication,
                  let other = otherApp(from: app) else { return }
            cachedApplication = other
            PasteService.capturePasteTarget(from: other)
        }
        center.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil, queue: .main
        ) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication,
                  let other = otherApp(from: app) else { return }
            cachedApplication = other
            PasteService.capturePasteTarget(from: other)
        }
    }

    public static func captureNow() {
        guard let other = otherApp(from: NSWorkspace.shared.frontmostApplication) else { return }
        cachedApplication = other
        PasteService.capturePasteTarget(from: other, appOnly: true)
    }

    public static var lastApplication: NSRunningApplication? {
        cachedApplication ?? otherApp(from: NSWorkspace.shared.frontmostApplication)
    }

    private static func otherApp(from app: NSRunningApplication?) -> NSRunningApplication? {
        guard let app, let bundleID = app.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier else { return nil }
        return app
    }
}
