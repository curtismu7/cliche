import AppKit

/// Backdrop styles for "social-ready" screenshots: gradient background,
/// padding, rounded corners, and a drop shadow.
public enum BeautifyStyle: String, CaseIterable {
    case none
    case indigo
    case sunset
    case ocean
    case forest
    case slate

    public var label: String {
        switch self {
        case .none: return "None"
        case .indigo: return "Indigo"
        case .sunset: return "Sunset"
        case .ocean: return "Ocean"
        case .forest: return "Forest"
        case .slate: return "Slate"
        }
    }

    var gradient: (start: CGColor, end: CGColor)? {
        func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
            CGColor(red: r, green: g, blue: b, alpha: 1)
        }
        switch self {
        case .none: return nil
        case .indigo: return (rgb(0.35, 0.30, 0.85), rgb(0.65, 0.35, 0.85))
        case .sunset: return (rgb(0.95, 0.45, 0.30), rgb(0.90, 0.30, 0.55))
        case .ocean: return (rgb(0.15, 0.55, 0.85), rgb(0.20, 0.80, 0.75))
        case .forest: return (rgb(0.15, 0.55, 0.35), rgb(0.55, 0.75, 0.30))
        case .slate: return (rgb(0.25, 0.28, 0.33), rgb(0.45, 0.50, 0.58))
        }
    }
}

public enum BeautifyRenderer {
    /// Composites the image onto a padded gradient backdrop with rounded
    /// corners and a drop shadow. `.none` returns the image untouched.
    public static func apply(_ style: BeautifyStyle, to image: CGImage) -> CGImage? {
        guard let gradientColors = style.gradient else { return image }

        let padding = max(48, CGFloat(min(image.width, image.height)) * 0.09)
        let width = image.width + Int(padding * 2)
        let height = image.height + Int(padding * 2)
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        // Diagonal gradient backdrop.
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        if let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [gradientColors.start, gradientColors.end] as CFArray,
            locations: [0, 1]) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: CGFloat(height)),
                end: CGPoint(x: CGFloat(width), y: 0),
                options: [])
        }

        let imageRect = CGRect(
            x: padding, y: padding,
            width: CGFloat(image.width), height: CGFloat(image.height))
        let cornerRadius = max(10, CGFloat(min(image.width, image.height)) / 60)
        let rounded = CGPath(
            roundedRect: imageRect,
            cornerWidth: cornerRadius, cornerHeight: cornerRadius,
            transform: nil)

        // Shadow is cast by an opaque rounded plate under the screenshot.
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -padding * 0.18),
            blur: padding * 0.5,
            color: CGColor(gray: 0, alpha: 0.45))
        context.addPath(rounded)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fillPath()
        context.restoreGState()

        // The screenshot itself, clipped to the rounded plate.
        context.saveGState()
        context.addPath(rounded)
        context.clip()
        context.draw(image, in: imageRect)
        context.restoreGState()

        return context.makeImage()
    }
}
