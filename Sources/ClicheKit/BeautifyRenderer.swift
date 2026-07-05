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

    // MARK: Config-driven pipeline

    public struct BeautifyLayout: Equatable {
        public var outputSize: CGSize
        public var screenshotRect: CGRect
    }

    /// Where the (possibly trimmed) screenshot lands and how big the output is.
    /// Pure geometry — takes the cropped screenshot size, not the image.
    public static func layout(_ config: BeautifyConfig, croppedSize: CGSize) -> BeautifyLayout {
        let minDim = min(croppedSize.width, croppedSize.height)
        let pad = config.padding * minDim
        let insetW = (config.inset?.width ?? 0) * minDim
        let frameW = croppedSize.width + 2 * insetW
        let frameH = croppedSize.height + 2 * insetW
        let contentW = frameW + 2 * pad
        let contentH = frameH + 2 * pad

        switch config.canvas {
        case .free:
            let rect = CGRect(x: pad + insetW, y: pad + insetW,
                              width: croppedSize.width, height: croppedSize.height)
            return BeautifyLayout(
                outputSize: CGSize(width: contentW, height: contentH),
                screenshotRect: rect)
        case .fixed(let w, let h, _):
            let canvas = CGSize(width: CGFloat(w), height: CGFloat(h))
            let s = min(canvas.width / contentW, canvas.height / contentH)
            let drawW = contentW * s, drawH = contentH * s
            let ox = (canvas.width - drawW) / 2, oy = (canvas.height - drawH) / 2
            let rect = CGRect(
                x: ox + (pad + insetW) * s, y: oy + (pad + insetW) * s,
                width: croppedSize.width * s, height: croppedSize.height * s)
            return BeautifyLayout(outputSize: canvas, screenshotRect: rect)
        }
    }

    /// Region of `image` to composite. Full image unless auto-balance is on,
    /// in which case uniform-color margins (matching the top-left pixel) are
    /// trimmed. Returns an integral rect in image pixel coordinates.
    public static func sourceCrop(_ config: BeautifyConfig, in image: CGImage) -> CGRect {
        let full = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard config.autoBalance else { return full }
        guard let data = image.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return full }
        let bpr = image.bytesPerRow
        let bpp = image.bitsPerPixel / 8
        guard bpp >= 3 else { return full }

        func px(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let o = y * bpr + x * bpp
            return (Int(ptr[o]), Int(ptr[o + 1]), Int(ptr[o + 2]))
        }
        let bg = px(0, 0)
        func differs(_ x: Int, _ y: Int) -> Bool {
            let p = px(x, y)
            return abs(p.0 - bg.0) + abs(p.1 - bg.1) + abs(p.2 - bg.2) > 24
        }

        var minX = image.width, minY = image.height, maxX = -1, maxY = -1
        for y in 0..<image.height {
            for x in 0..<image.width where differs(x, y) {
                if x < minX { minX = x }; if x > maxX { maxX = x }
                if y < minY { minY = y }; if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return full }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// Composites `image` onto the configured backdrop. Identity → unchanged.
    public static func render(_ config: BeautifyConfig, to image: CGImage) -> CGImage? {
        if config.isIdentity { return image }
        let crop = sourceCrop(config, in: image)
        let cropped = image.cropping(to: crop) ?? image
        let croppedSize = CGSize(width: cropped.width, height: cropped.height)
        let l = layout(config, croppedSize: croppedSize)
        let outW = Int(l.outputSize.width.rounded())
        let outH = Int(l.outputSize.height.rounded())
        guard outW > 0, outH > 0,
              let ctx = CGContext(
                data: nil, width: outW, height: outH,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        let outputRect = CGRect(x: 0, y: 0, width: outW, height: outH)
        drawGradient(config.background, in: outputRect, context: ctx)

        let shot = l.screenshotRect
        let shotMin = min(shot.width, shot.height)
        let cornerRadius = config.cornerRadius * shotMin
        let insetW = (config.inset?.width ?? 0) * shotMin
        let matte = shot.insetBy(dx: -insetW, dy: -insetW)
        let plateRadius = cornerRadius + insetW
        let platePath = CGPath(roundedRect: matte,
                               cornerWidth: plateRadius, cornerHeight: plateRadius,
                               transform: nil)

        // Shadow cast by an opaque plate under the (matte-expanded) screenshot.
        if config.shadow.opacity > 0 {
            ctx.saveGState()
            ctx.setShadow(
                offset: CGSize(width: 0, height: -config.shadow.yOffsetFraction * shotMin),
                blur: config.shadow.blur * shotMin,
                color: CGColor(gray: 0, alpha: config.shadow.opacity))
            ctx.addPath(platePath)
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillPath()
            ctx.restoreGState()
        }

        // Inset matte fill (color band around the screenshot).
        if let inset = config.inset, insetW > 0 {
            ctx.saveGState()
            ctx.addPath(platePath)
            ctx.setFillColor(inset.color.cgColor)
            ctx.fillPath()
            ctx.restoreGState()
        }

        // Screenshot clipped to its rounded rect.
        let shotPath = CGPath(roundedRect: shot,
                              cornerWidth: cornerRadius, cornerHeight: cornerRadius,
                              transform: nil)
        ctx.saveGState()
        ctx.addPath(shotPath)
        ctx.clip()
        ctx.draw(cropped, in: shot)
        ctx.restoreGState()

        return ctx.makeImage()
    }

    private static func drawGradient(_ gradient: Gradient, in rect: CGRect, context: CGContext) {
        guard !gradient.isEmpty else { return }
        let space = CGColorSpaceCreateDeviceRGB()
        let colors = gradient.stops.map { $0.color.cgColor } as CFArray
        let locations = gradient.stops.map { CGFloat($0.location) }
        guard let cg = CGGradient(colorsSpace: space, colors: colors, locations: locations)
        else { return }
        let a = gradient.angleDegrees * .pi / 180
        let dx = cos(a), dy = sin(a)
        let half = abs(dx) * rect.width / 2 + abs(dy) * rect.height / 2
        let start = CGPoint(x: rect.midX - dx * half, y: rect.midY - dy * half)
        let end = CGPoint(x: rect.midX + dx * half, y: rect.midY + dy * half)
        context.drawLinearGradient(cg, start: start, end: end, options: [])
    }
}
