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
}
