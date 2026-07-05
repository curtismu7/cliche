import AppKit

/// Composites a screenshot onto a "social-ready" backdrop — gradient
/// background, padding, rounded corners, drop shadow, optional inset matte,
/// and fixed canvas sizes — driven by a `BeautifyConfig`.
public enum BeautifyRenderer {
    public struct BeautifyLayout: Equatable {
        public var outputSize: CGSize
        public var screenshotRect: CGRect
        public init(outputSize: CGSize, screenshotRect: CGRect) {
            self.outputSize = outputSize
            self.screenshotRect = screenshotRect
        }
    }

    /// Where the (possibly trimmed) screenshot lands and how big the output is.
    /// Pure geometry — takes the cropped screenshot size, not the image.
    public static func layout(_ config: BeautifyConfig, croppedSize: CGSize) -> BeautifyLayout {
        let minDim = min(croppedSize.width, croppedSize.height)
        let pad = config.padding * minDim
        let insetW = (config.inset?.width ?? 0) * minDim
        let chrome = FrameRenderer.chromeInsets(config.frame, minDimension: minDim)
        let frameW = croppedSize.width + chrome.left + chrome.right + 2 * insetW
        let frameH = croppedSize.height + chrome.top + chrome.bottom + 2 * insetW
        let contentW = frameW + 2 * pad
        let contentH = frameH + 2 * pad

        switch config.canvas {
        case .free:
            let rect = CGRect(
                x: pad + insetW + chrome.left, y: pad + insetW + chrome.bottom,
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
                x: ox + (pad + insetW + chrome.left) * s,
                y: oy + (pad + insetW + chrome.bottom) * s,
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
        let chrome = FrameRenderer.chromeInsets(config.frame, minDimension: shotMin)
        let chromePlate = CGRect(
            x: shot.minX - chrome.left, y: shot.minY - chrome.bottom,
            width: shot.width + chrome.left + chrome.right,
            height: shot.height + chrome.top + chrome.bottom)
        let cornerRadius = config.cornerRadius * shotMin
        let insetW = (config.inset?.width ?? 0) * shotMin
        let matte = chromePlate.insetBy(dx: -insetW, dy: -insetW)
        let plateRadius = cornerRadius + insetW
        let platePath = CGPath(roundedRect: matte,
                               cornerWidth: plateRadius, cornerHeight: plateRadius,
                               transform: nil)

        // Shadow cast by an opaque plate under the whole framed unit.
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

        // Inset matte fill (color band around the framed unit).
        if let inset = config.inset, insetW > 0 {
            ctx.saveGState()
            ctx.addPath(platePath)
            ctx.setFillColor(inset.color.cgColor)
            ctx.fillPath()
            ctx.restoreGState()
        }

        // Presentation chrome (browser/mac bar or device bezel).
        FrameRenderer.draw(config.frame, urlText: config.frameURL,
                           plateRect: chromePlate, screenshotRect: shot,
                           cornerRadius: cornerRadius, in: ctx)

        // Screenshot. Frameless: rounded to its own corners. Framed: square
        // inside the chrome — the chrome plate carries the corner rounding.
        let shotPath = config.frame == .none
            ? CGPath(roundedRect: shot, cornerWidth: cornerRadius,
                     cornerHeight: cornerRadius, transform: nil)
            : CGPath(roundedRect: chromePlate, cornerWidth: cornerRadius,
                     cornerHeight: cornerRadius, transform: nil)
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
