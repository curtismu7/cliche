import AppKit

public enum ColorUtil {
    /// "#RRGGBB" in sRGB, e.g. "#3A7BD5".
    public static func hexString(_ color: NSColor) -> String? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        return String(
            format: "#%02X%02X%02X",
            Int((rgb.redComponent * 255).rounded()),
            Int((rgb.greenComponent * 255).rounded()),
            Int((rgb.blueComponent * 255).rounded()))
    }

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
}
