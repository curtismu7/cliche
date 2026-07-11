import Foundation

/// Commands reachable via the cliche:// URL scheme (Raycast, Shortcuts,
/// `open`). Parsing is total: anything unrecognized returns nil.
public enum URLCommand: Equatable {
    case captureRegion, captureWindow, captureFullScreen,
         allInOne, ocr, repeatRegion, panel, permissions

    public static func parse(_ url: URL) -> URLCommand? {
        guard url.scheme?.lowercased() == "cliche" else { return nil }
        switch url.host?.lowercased() {
        case "capture":
            let mode = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name.lowercased() == "mode" }?
                .value?.lowercased() ?? "region"
            switch mode {
            case "region": return .captureRegion
            case "window": return .captureWindow
            case "fullscreen": return .captureFullScreen
            case "allinone": return .allInOne
            default: return nil
            }
        case "ocr": return .ocr
        case "repeat": return .repeatRegion
        case "panel": return .panel
        case "permissions", "setup": return .permissions
        default: return nil
        }
    }
}
