import Foundation
import ServiceManagement

/// Launch-at-login via SMAppService. Only effective when running from the
/// bundled Cliche.app (registration needs a bundle identity).
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns the resulting state (unchanged if registration failed,
    /// e.g. when running unbundled via `swift run`).
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Cliche: launch-at-login change failed: \(error)")
        }
        return isEnabled
    }
}
