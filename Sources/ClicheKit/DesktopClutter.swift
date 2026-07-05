import ScreenCaptureKit

/// Identifies the Finder windows that draw desktop icons so captures can
/// exclude them (the wallpaper is a different layer and stays visible).
public enum DesktopClutter {
    public static func isDesktopIconWindow(
        owningBundleID: String?, windowLayer: Int
    ) -> Bool {
        owningBundleID == "com.apple.finder"
            && windowLayer == Int(CGWindowLevelForKey(.desktopIconWindow))
    }

    /// The windows a capture should exclude: Cliché's own windows, plus —
    /// when `hideDesktopIcons` — Finder's desktop-icon windows.
    public static func exclusions(
        in windows: [SCWindow], hideDesktopIcons: Bool
    ) -> [SCWindow] {
        let ownPID = pid_t(ProcessInfo.processInfo.processIdentifier)
        return windows.filter { window in
            if window.owningApplication?.processID == ownPID { return true }
            guard hideDesktopIcons else { return false }
            return isDesktopIconWindow(
                owningBundleID: window.owningApplication?.bundleIdentifier,
                windowLayer: window.windowLayer)
        }
    }
}
