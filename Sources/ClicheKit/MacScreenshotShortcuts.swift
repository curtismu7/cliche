import AppKit
import Carbon.HIToolbox
import Foundation

/// Disables macOS's built-in screenshot shortcuts (⌘⇧3/4/5) so Cliché's
/// global hotkeys can register. Backs up prior state for restore.
public enum MacScreenshotShortcuts {
    /// Symbolic hotkey IDs documented in com.apple.symbolichotkeys.plist.
    public static let screenshotHotkeyIDs = [28, 29, 30, 31, 184]

    private static let preferencesDomain = "com.apple.symbolichotkeys"
    private static let backupKey = "macScreenshotShortcutBackup"
    private static let activateSettingsPath =
        "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"

    public static let knownValues: [Int: [Int]] = [
        28: [51, 20, 1179648],       // ⌘⇧3 save screen
        29: [51, 20, 1441792],       // ⌃⌘⇧3 copy screen
        30: [52, 21, 1179648],       // ⌘⇧4 save selection
        31: [52, 21, 1441792],       // ⌃⌘⇧4 copy selection
        184: [53, 23, 1179648],      // ⌘⇧5 screenshot UI
    ]

    /// Applies or restores macOS screenshot shortcuts based on the setting.
    public static func apply(disabled: Bool, settingsDefaults: UserDefaults = .standard) {
        if disabled {
            disable(settingsDefaults: settingsDefaults)
        } else {
            restore(settingsDefaults: settingsDefaults)
        }
        reloadSystemHotkeys()
    }

    /// True when any macOS screenshot shortcut is still enabled.
    public static func isAnyScreenshotShortcutEnabled() -> Bool {
        guard let hotkeys = loadHotkeys() else { return false }
        for id in screenshotHotkeyIDs {
            if enabledState(for: id, in: hotkeys) == true { return true }
        }
        return false
    }

    /// Human-readable macOS shortcut that conflicts with this combo, if any.
    public static func macOSConflictDescription(for combo: HotkeyCombo) -> String? {
        let screen = UInt32(shiftKey) | UInt32(cmdKey)
        let screenControl = screen | UInt32(controlKey)
        switch (combo.keyCode, combo.carbonModifiers) {
        case (UInt32(kVK_ANSI_3), screen):
            return "Conflicts with macOS full-screen screenshot (⌘⇧3)"
        case (UInt32(kVK_ANSI_3), screenControl):
            return "Conflicts with macOS copy-screen shortcut (⌃⌘⇧3)"
        case (UInt32(kVK_ANSI_4), screen):
            return "Conflicts with macOS region screenshot (⌘⇧4)"
        case (UInt32(kVK_ANSI_4), screenControl):
            return "Conflicts with macOS copy-region shortcut (⌃⌘⇧4)"
        case (UInt32(kVK_ANSI_5), screen):
            return "Conflicts with macOS screenshot toolbar (⌘⇧5)"
        default:
            return nil
        }
    }

    private static func disable(settingsDefaults: UserDefaults) {
        guard var hotkeys = loadHotkeys() else { return }
        var backup = settingsDefaults.dictionary(forKey: backupKey) as? [String: Bool] ?? [:]
        for id in screenshotHotkeyIDs {
            let key = String(id)
            if backup[key] == nil {
                backup[key] = enabledState(for: id, in: hotkeys) ?? true
            }
            setEntry(id: id, enabled: false, in: &hotkeys)
        }
        settingsDefaults.set(backup, forKey: backupKey)
        saveHotkeys(hotkeys)
    }

    private static func restore(settingsDefaults: UserDefaults) {
        guard var hotkeys = loadHotkeys() else { return }
        let backup = settingsDefaults.dictionary(forKey: backupKey) as? [String: Bool]
        for id in screenshotHotkeyIDs {
            let key = String(id)
            let enabled = backup?[key] ?? true
            setEntry(id: id, enabled: enabled, in: &hotkeys)
        }
        settingsDefaults.removeObject(forKey: backupKey)
        saveHotkeys(hotkeys)
    }

    private static func plistURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.apple.symbolichotkeys.plist")
    }

    private static func loadHotkeys() -> [String: Any]? {
        guard let root = NSDictionary(contentsOf: plistURL()) as? [String: Any] else {
            return [:]
        }
        return (root["AppleSymbolicHotKeys"] as? [String: Any]) ?? [:]
    }

    private static func saveHotkeys(_ hotkeys: [String: Any]) {
        var root = (NSDictionary(contentsOf: plistURL()) as? [String: Any]) ?? [:]
        root["AppleSymbolicHotKeys"] = hotkeys
        (root as NSDictionary).write(to: plistURL(), atomically: true)
    }

    private static func enabledState(for id: Int, in hotkeys: [String: Any]) -> Bool? {
        guard let entry = hotkeys[String(id)] as? [String: Any] else { return nil }
        return entry["enabled"] as? Bool
    }

    private static func setEntry(id: Int, enabled: Bool, in hotkeys: inout [String: Any]) {
        let key = String(id)
        var entry = hotkeys[key] as? [String: Any] ?? [:]
        entry["enabled"] = enabled
        if entry["value"] == nil, let parameters = knownValues[id] {
            entry["value"] = [
                "type": "standard",
                "parameters": parameters,
            ]
        }
        hotkeys[key] = entry
    }

    private static func reloadSystemHotkeys() {
        guard FileManager.default.isExecutableFile(atPath: activateSettingsPath) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: activateSettingsPath)
        process.arguments = ["-u"]
        try? process.run()
        process.waitUntilExit()
    }
}
