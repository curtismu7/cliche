import AppKit

/// Procedural presentation chrome: browser/mac title bars and generic
/// device bezels, drawn straight into the beautify render context.
public enum FrameRenderer {
    /// Extra space the chrome needs around the screenshot, in pixels.
    public static func chromeInsets(
        _ style: FrameStyle, minDimension: CGFloat
    ) -> NSEdgeInsets {
        switch style {
        case .none:
            return NSEdgeInsets()
        case .browserLight, .browserDark, .macWindow:
            return NSEdgeInsets(top: 0.055 * minDimension, left: 0, bottom: 0, right: 0)
        case .phone:
            let b = 0.045 * minDimension
            return NSEdgeInsets(top: b, left: b, bottom: b, right: b)
        case .tablet:
            let b = 0.06 * minDimension
            return NSEdgeInsets(top: b, left: b, bottom: b, right: b)
        }
    }

    /// Draws the chrome for `style` around `screenshotRect`. `plateRect` is
    /// the screenshot expanded by `chromeInsets`; `cornerRadius` matches the
    /// beautify plate rounding so chrome corners align with the plate.
    public static func draw(
        _ style: FrameStyle, urlText: String,
        plateRect: CGRect, screenshotRect: CGRect,
        cornerRadius: CGFloat, in ctx: CGContext
    ) {
        guard style != .none else { return }
        let clip = CGPath(roundedRect: plateRect,
                          cornerWidth: cornerRadius, cornerHeight: cornerRadius,
                          transform: nil)
        ctx.saveGState()
        ctx.addPath(clip)
        ctx.clip()

        switch style {
        case .none:
            break
        case .browserLight, .browserDark, .macWindow:
            drawBar(style, urlText: urlText, plateRect: plateRect,
                    screenshotRect: screenshotRect, in: ctx)
        case .phone, .tablet:
            // Bezel: fill the border band around the screenshot.
            let bezelColor = CGColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
            ctx.setFillColor(bezelColor)
            ctx.fill(CGRect(x: plateRect.minX, y: plateRect.minY,
                            width: plateRect.width,
                            height: screenshotRect.minY - plateRect.minY))
            ctx.fill(CGRect(x: plateRect.minX, y: screenshotRect.maxY,
                            width: plateRect.width,
                            height: plateRect.maxY - screenshotRect.maxY))
            ctx.fill(CGRect(x: plateRect.minX, y: screenshotRect.minY,
                            width: screenshotRect.minX - plateRect.minX,
                            height: screenshotRect.height))
            ctx.fill(CGRect(x: screenshotRect.maxX, y: screenshotRect.minY,
                            width: plateRect.maxX - screenshotRect.maxX,
                            height: screenshotRect.height))
            // Camera dot centered in the top bezel band.
            let bezelTop = plateRect.maxY - screenshotRect.maxY
            let r = max(2, bezelTop * 0.14)
            ctx.setFillColor(CGColor(red: 0.25, green: 0.25, blue: 0.28, alpha: 1))
            ctx.fillEllipse(in: CGRect(
                x: plateRect.midX - r, y: screenshotRect.maxY + bezelTop / 2 - r,
                width: r * 2, height: r * 2))
        }
        ctx.restoreGState()
    }

    private static func drawBar(
        _ style: FrameStyle, urlText: String,
        plateRect: CGRect, screenshotRect: CGRect, in ctx: CGContext
    ) {
        let barRect = CGRect(
            x: plateRect.minX, y: screenshotRect.maxY,
            width: plateRect.width, height: plateRect.maxY - screenshotRect.maxY)
        let dark = style == .browserDark
        let barColor = dark
            ? CGColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1)
            : CGColor(red: 0.925, green: 0.925, blue: 0.94, alpha: 1)
        ctx.setFillColor(barColor)
        ctx.fill(barRect)

        // Traffic lights.
        let r = barRect.height * 0.16
        let colors: [CGColor] = [
            CGColor(red: 1.0, green: 0.37, blue: 0.34, alpha: 1),
            CGColor(red: 1.0, green: 0.74, blue: 0.18, alpha: 1),
            CGColor(red: 0.16, green: 0.78, blue: 0.25, alpha: 1),
        ]
        for (i, color) in colors.enumerated() {
            ctx.setFillColor(color)
            ctx.fillEllipse(in: CGRect(
                x: barRect.minX + barRect.height * 0.45 + CGFloat(i) * r * 3.1,
                y: barRect.midY - r, width: r * 2, height: r * 2))
        }

        guard style.isBrowser else { return }
        // URL pill.
        let pillWidth = plateRect.width * 0.6
        let pillHeight = barRect.height * 0.58
        let pill = CGRect(
            x: barRect.midX - pillWidth / 2, y: barRect.midY - pillHeight / 2,
            width: pillWidth, height: pillHeight)
        ctx.setFillColor(dark
            ? CGColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1)
            : CGColor(gray: 1, alpha: 1))
        ctx.addPath(CGPath(roundedRect: pill, cornerWidth: pillHeight / 2,
                           cornerHeight: pillHeight / 2, transform: nil))
        ctx.fillPath()

        guard !urlText.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: pillHeight * 0.5),
            .foregroundColor: dark
                ? NSColor(calibratedWhite: 0.72, alpha: 1)
                : NSColor(calibratedWhite: 0.42, alpha: 1),
        ]
        let size = (urlText as NSString).size(withAttributes: attributes)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        (urlText as NSString).draw(
            at: CGPoint(x: pill.midX - size.width / 2, y: pill.midY - size.height / 2),
            withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }
}
