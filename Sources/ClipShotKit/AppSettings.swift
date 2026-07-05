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

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.captureFormat = defaults.string(forKey: "captureFormat")
            .flatMap(ImageFormat.init(rawValue:)) ?? .png
        self.copyCapturesToClipboard =
            defaults.object(forKey: "copyCapturesToClipboard") as? Bool ?? true
    }
}
