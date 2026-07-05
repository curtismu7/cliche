import AppKit
import Carbon.HIToolbox

/// The user-remappable global actions.
public enum HotkeyAction: String, CaseIterable, Codable {
    case togglePanel
    case captureRegion
    case captureWindow
    case captureText
    case repeatRegion
    case floatingList

    public var label: String {
        switch self {
        case .togglePanel: return "Open clipboard panel"
        case .captureRegion: return "Capture region"
        case .captureWindow: return "Capture window"
        case .captureText: return "Copy text from screen (OCR)"
        case .repeatRegion: return "Repeat last region"
        case .floatingList: return "Floating clipboard list"
        }
    }
}

/// A key combination in Carbon terms (what RegisterEventHotKey needs) plus a
/// human-readable form captured at record time.
public struct HotkeyCombo: Codable, Equatable {
    public var keyCode: UInt32
    public var carbonModifiers: UInt32
    public var display: String

    public init(keyCode: UInt32, carbonModifiers: UInt32, display: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.display = display
    }

    public static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        return modifiers
    }

    public static func displaySymbols(for flags: NSEvent.ModifierFlags) -> String {
        var symbols = ""
        if flags.contains(.control) { symbols += "⌃" }
        if flags.contains(.option) { symbols += "⌥" }
        if flags.contains(.shift) { symbols += "⇧" }
        if flags.contains(.command) { symbols += "⌘" }
        return symbols
    }
}

extension AppSettings {
    public static let hotkeysChanged = Notification.Name("ClicheHotkeysChanged")

    public static let defaultHotkeys: [HotkeyAction: HotkeyCombo] = {
        let base = UInt32(controlKey) | UInt32(optionKey) | UInt32(cmdKey)
        return [
            .togglePanel: HotkeyCombo(
                keyCode: UInt32(kVK_ANSI_C), carbonModifiers: base, display: "⌃⌥⌘C"),
            .captureRegion: HotkeyCombo(
                keyCode: UInt32(kVK_ANSI_4), carbonModifiers: base, display: "⌃⌥⌘4"),
            .captureWindow: HotkeyCombo(
                keyCode: UInt32(kVK_ANSI_5), carbonModifiers: base, display: "⌃⌥⌘5"),
            .captureText: HotkeyCombo(
                keyCode: UInt32(kVK_ANSI_6), carbonModifiers: base, display: "⌃⌥⌘6"),
            .repeatRegion: HotkeyCombo(
                keyCode: UInt32(kVK_ANSI_R), carbonModifiers: base, display: "⌃⌥⌘R"),
            .floatingList: HotkeyCombo(
                keyCode: UInt32(kVK_ANSI_1), carbonModifiers: UInt32(optionKey),
                display: "⌥1"),
        ]
    }()

    public func combo(for action: HotkeyAction) -> HotkeyCombo {
        loadHotkeys()[action] ?? Self.defaultHotkeys[action]!
    }

    /// Nil restores the default. Posts `hotkeysChanged` so registration and
    /// labels refresh.
    public func setCombo(_ combo: HotkeyCombo?, for action: HotkeyAction) {
        var all = loadHotkeys()
        all[action] = combo
        if let data = try? JSONEncoder().encode(
            Dictionary(uniqueKeysWithValues: all.map { ($0.key.rawValue, $0.value) })) {
            hotkeysDefaults.set(data, forKey: "hotkeyCombos")
        }
        NotificationCenter.default.post(name: Self.hotkeysChanged, object: nil)
    }

    /// The action already using this combo, if any (for conflict checks).
    public func action(using combo: HotkeyCombo) -> HotkeyAction? {
        HotkeyAction.allCases.first {
            let existing = self.combo(for: $0)
            return existing.keyCode == combo.keyCode
                && existing.carbonModifiers == combo.carbonModifiers
        }
    }

    private func loadHotkeys() -> [HotkeyAction: HotkeyCombo] {
        guard let data = hotkeysDefaults.data(forKey: "hotkeyCombos"),
              let raw = try? JSONDecoder().decode([String: HotkeyCombo].self, from: data)
        else { return [:] }
        var result: [HotkeyAction: HotkeyCombo] = [:]
        for (key, value) in raw {
            if let action = HotkeyAction(rawValue: key) {
                result[action] = value
            }
        }
        return result
    }
}
