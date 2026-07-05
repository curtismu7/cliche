import Foundation
import Observation

/// User-configurable capture behavior, persisted in UserDefaults.
@Observable
public final class AppSettings {
    public enum ImageFormat: String, CaseIterable, Codable {
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

    /// Exclude Finder's desktop-icon windows from captures (wallpaper stays).
    public var hideDesktopIcons: Bool {
        didSet { defaults.set(hideDesktopIcons, forKey: "hideDesktopIcons") }
    }

    public enum MenuBarStyle: String, CaseIterable {
        /// One icon opening the full panel.
        case combined
        /// Two icons — clipboard history and screen capture — each opening
        /// its own focused panel.
        case split
    }

    public static let menuBarStyleChanged = Notification.Name("ClicheMenuBarStyleChanged")
    public static let historyLimitsChanged = Notification.Name("ClicheHistoryLimitsChanged")

    /// History caps (pinned items never count against them).
    public var maxTextEntries: Int {
        didSet {
            defaults.set(maxTextEntries, forKey: "maxTextEntries")
            NotificationCenter.default.post(name: Self.historyLimitsChanged, object: nil)
        }
    }

    public var maxImageEntries: Int {
        didSet {
            defaults.set(maxImageEntries, forKey: "maxImageEntries")
            NotificationCenter.default.post(name: Self.historyLimitsChanged, object: nil)
        }
    }

    public var menuBarStyle: MenuBarStyle {
        didSet {
            defaults.set(menuBarStyle.rawValue, forKey: "menuBarStyle")
            NotificationCenter.default.post(name: Self.menuBarStyleChanged, object: nil)
        }
    }

    /// Last beautify config used in the editor; the editor opens with this.
    public var lastBeautifyConfig: BeautifyConfig {
        didSet { Self.encode(lastBeautifyConfig, to: defaults, key: "lastBeautifyConfig") }
    }

    /// User-saved named beautify presets.
    public var beautifyPresets: [NamedBeautifyConfig] {
        didSet { Self.encode(beautifyPresets, to: defaults, key: "beautifyPresets") }
    }

    /// User-saved capture presets (mode + format + destination + naming).
    public var capturePresets: [CapturePreset] {
        didSet { Self.encode(capturePresets, to: defaults, key: "capturePresets") }
    }

    private let defaults: UserDefaults
    /// Same store, exposed for the hotkeys extension.
    var hotkeysDefaults: UserDefaults { defaults }

    private static func encode<T: Encodable>(_ value: T, to defaults: UserDefaults, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from defaults: UserDefaults,
                                             key: String, default fallback: T) -> T {
        guard let data = defaults.data(forKey: key),
              let value = try? JSONDecoder().decode(type, from: data)
        else { return fallback }
        return value
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.captureFormat = defaults.string(forKey: "captureFormat")
            .flatMap(ImageFormat.init(rawValue:)) ?? .png
        self.copyCapturesToClipboard =
            defaults.object(forKey: "copyCapturesToClipboard") as? Bool ?? true
        self.timerSeconds = defaults.object(forKey: "timerSeconds") as? Int ?? 0
        self.showCursor = defaults.object(forKey: "showCursor") as? Bool ?? false
        self.windowShadow = defaults.object(forKey: "windowShadow") as? Bool ?? false
        self.hideDesktopIcons =
            defaults.object(forKey: "hideDesktopIcons") as? Bool ?? false
        self.menuBarStyle = defaults.string(forKey: "menuBarStyle")
            .flatMap(MenuBarStyle.init(rawValue:)) ?? .combined
        self.maxTextEntries = defaults.object(forKey: "maxTextEntries") as? Int ?? 150
        self.maxImageEntries = defaults.object(forKey: "maxImageEntries") as? Int ?? 50
        self.lastBeautifyConfig = Self.decode(
            BeautifyConfig.self, from: defaults,
            key: "lastBeautifyConfig", default: .identity)
        self.beautifyPresets = Self.decode(
            [NamedBeautifyConfig].self, from: defaults,
            key: "beautifyPresets", default: [])
        self.capturePresets = Self.decode(
            [CapturePreset].self, from: defaults,
            key: "capturePresets", default: [])
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
