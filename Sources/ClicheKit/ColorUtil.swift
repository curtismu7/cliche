import AppKit

public enum ColorUtil {
    /// WCAG 2.0 contrast ratio, 1...21.
    public static func contrastRatio(_ a: NSColor, _ b: NSColor) -> Double? {
        func luminance(_ color: NSColor) -> Double? {
            guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
            func linear(_ v: Double) -> Double {
                v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(rgb.redComponent)
                + 0.7152 * linear(rgb.greenComponent)
                + 0.0722 * linear(rgb.blueComponent)
        }
        guard let la = luminance(a), let lb = luminance(b) else { return nil }
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// "AAA", "AA", "AA Large", or "Fail" for normal text.
    public static func wcagVerdict(ratio: Double) -> String {
        if ratio >= 7 { return "AAA" }
        if ratio >= 4.5 { return "AA" }
        if ratio >= 3 { return "AA Large" }
        return "Fail"
    }

    public static let defaultHeaderBarHex = "#C72926"

    /// "#RRGGBB" in sRGB, e.g. "#3A7BD5".
    public static func hexString(_ color: NSColor) -> String? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        return hex(fromRGB: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
    }

    /// Parses "#RRGGBB" or "RRGGBB" into 0...1 sRGB components.
    public static func rgb(fromHex hex: String) -> (red: Double, green: Double, blue: Double)? {
        var trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") { trimmed.removeFirst() }
        guard trimmed.count == 6, let value = UInt32(trimmed, radix: 16) else { return nil }
        return (
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }

    public static func hex(fromRGB red: Double, green: Double, blue: Double) -> String {
        String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded()))
    }
}
