import AppKit
import ClicheKit
import SwiftUI

/// Panel chrome derived from AppSettings (header color + light/dark mode).
enum PanelTheme {
    static func headerBackground(_ settings: AppSettings) -> Color {
        guard let rgb = ColorUtil.rgb(fromHex: settings.headerBarColorHex) else {
            return Color(red: 0.78, green: 0.16, blue: 0.15)
        }
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    static func headerTitleColor(_ settings: AppSettings) -> Color {
        guard let rgb = ColorUtil.rgb(fromHex: settings.headerBarColorHex),
              let ratio = ColorUtil.contrastRatio(
                  NSColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1),
                  .white),
              ratio >= 3
        else { return .black }
        return .white
    }

    static func panelBackground(_ settings: AppSettings) -> Color {
        settings.panelColorScheme == .dark ? Color(white: 0.12) : .white
    }

    static func swiftUIColorScheme(_ settings: AppSettings) -> ColorScheme {
        settings.panelColorScheme == .dark ? .dark : .light
    }

    static func nsAppearance(_ settings: AppSettings) -> NSAppearance {
        NSAppearance(named: settings.panelColorScheme == .dark ? .darkAqua : .aqua) ?? NSAppearance(named: .aqua)!
    }

    static func borderColor(_ settings: AppSettings) -> Color {
        settings.panelColorScheme == .dark
            ? Color.white.opacity(0.15)
            : Color.black.opacity(0.15)
    }

    static func floatingBorderColor(_ settings: AppSettings) -> Color {
        settings.panelColorScheme == .dark
            ? Color.white.opacity(0.2)
            : Color.black.opacity(0.2)
    }

    /// Brand red for the settings gear — hard to miss in the panel footer.
    static let settingsIcon = Color(red: 0.78, green: 0.16, blue: 0.15)
}
