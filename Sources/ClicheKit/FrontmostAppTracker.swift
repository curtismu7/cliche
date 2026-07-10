import AppKit

/// Remembers the last app that was frontmost before Cliché took focus.
public enum FrontmostAppTracker {
    private static var cachedApplication: NSRunningApplication?
    private static var observer: NSObjectProtocol?

    public static func startMonitoring() {
        guard observer == nil else { return }
        cachedApplication = otherApp(from: NSWorkspace.shared.frontmostApplication)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication,
                  let other = otherApp(from: app) else { return }
            cachedApplication = other
        }
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
