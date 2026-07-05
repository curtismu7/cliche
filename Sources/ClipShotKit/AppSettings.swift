import Foundation
import Observation

/// User-configurable capture behavior, persisted in UserDefaults.
@Observable
public final class AppSettings {
    public enum ImageFormat: String, CaseIterable {
        case png
        case jpeg

        public var fileExtension: String { self == .png ? "png" : "jpg" }
        public var label: String { self == .png ? "PNG" : "JPEG" }
    }

    public var captureFormat: ImageFormat {
        didSet { defaults.set(captureFormat.rawValue, forKey: "captureFormat") }
    }

    /// When off, screenshots are saved to disk only — nothing touches the
    /// clipboard (and therefore nothing enters clipboard history).
    public var copyCapturesToClipboard: Bool {
        didSet { defaults.set(copyCapturesToClipboard, forKey: "copyCapturesToClipboard") }
    }

    /// Countdown before a capture starts (0 = off). For menus/tooltips.
    public var timerSeconds: Int {
        didSet { defaults.set(timerSeconds, forKey: "timerSeconds") }
    }

    public var showCursor: Bool {
        didSet { defaults.set(showCursor, forKey: "showCursor") }
    }

    /// Include the window shadow in window captures.
    public var windowShadow: Bool {
        didSet { defaults.set(windowShadow, forKey: "windowShadow") }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.captureFormat = defaults.string(forKey: "captureFormat")
            .flatMap(ImageFormat.init(rawValue:)) ?? .png
        self.copyCapturesToClipboard =
            defaults.object(forKey: "copyCapturesToClipboard") as? Bool ?? true
        self.timerSeconds = defaults.object(forKey: "timerSeconds") as? Int ?? 0
        self.showCursor = defaults.object(forKey: "showCursor") as? Bool ?? false
        self.windowShadow = defaults.object(forKey: "windowShadow") as? Bool ?? false
    }

    // MARK: Last capture region (for repeat-area capture)

    /// Pixel rect (top-left origin, display-relative) plus the display it
    /// belongs to. Not @Observable — read on demand by the repeat hotkey.
    public var lastRegion: (rect: CGRect, displayID: UInt32)? {
        get {
            guard let values = defaults.array(forKey: "lastRegionRect") as? [Double],
                  values.count == 4,
                  defaults.object(forKey: "lastRegionDisplay") != nil
            else { return nil }
            let display = UInt32(defaults.integer(forKey: "lastRegionDisplay"))
            return (CGRect(x: values[0], y: values[1], width: values[2], height: values[3]),
                    display)
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: "lastRegionRect")
                defaults.removeObject(forKey: "lastRegionDisplay")
                return
            }
            let rect = newValue.rect
            defaults.set([rect.origin.x, rect.origin.y, rect.width, rect.height],
                         forKey: "lastRegionRect")
            defaults.set(Int(newValue.displayID), forKey: "lastRegionDisplay")
        }
    }
}
