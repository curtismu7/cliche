import AppKit
import CoreImage

/// Flattens annotations onto an image. Used both for the live editor preview
/// and the final export, so what you see is exactly what you save.
public enum AnnotationRenderer {
    /// Renders at the base image's pixel size. Stroke widths, fonts, and
    /// badge sizes scale with the image so annotations stay legible on
    /// Retina captures.
    public static func render(base: CGImage, annotations: [Annotation]) -> CGImage? {
        let width = base.width
        let height = base.height
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        let fullRect = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(base, in: fullRect)

        // Size unit proportional to the image so markup reads at any scale.
        let unit = max(2, CGFloat(min(width, height)) / 250)
        let red = CGColor(red: 0.92, green: 0.18, blue: 0.14, alpha: 1)

        for annotation in annotations {
            switch annotation.kind {
            case .arrow:
                drawArrow(annotation, in: context, unit: unit, color: red)
            case .rectangle:
                context.setStrokeColor(red)
                context.setLineWidth(1.5 * unit)
                context.stroke(annotation.rect)
            case .blur:
                if let pixelated = pixelate(base, in: annotation.rect
                    .intersection(fullRect).integral) {
                    context.draw(pixelated.image, in: pixelated.rect)
                }
            case .counter(let number):
                drawCounter(number, at: annotation.end, in: context, unit: unit, color: red)
            case .text(let string):
                drawText(string, at: annotation.end, in: context, unit: unit)
            }
        }
        return context.makeImage()
    }

    public static func pngData(base: CGImage, annotations: [Annotation]) -> Data? {
        render(base: base, annotations: annotations)
            .flatMap(CaptureDelivery.pngData(from:))
    }

    // MARK: Primitives

    private static func drawArrow(
        _ annotation: Annotation, in context: CGContext, unit: CGFloat, color: CGColor
    ) {
        let start = annotation.start
        let end = annotation.end
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength = 6 * unit
        let headAngle: CGFloat = 0.45

        context.setStrokeColor(color)
        context.setLineWidth(1.5 * unit)
        context.setLineCap(.round)
        context.move(to: start)
        context.addLine(to: end)
        context.move(to: end)
        context.addLine(to: CGPoint(
            x: end.x - headLength * cos(angle - headAngle),
            y: end.y - headLength * sin(angle - headAngle)))
        context.move(to: end)
        context.addLine(to: CGPoint(
            x: end.x - headLength * cos(angle + headAngle),
            y: end.y - headLength * sin(angle + headAngle)))
        context.strokePath()
    }

    private static func drawCounter(
        _ number: Int, at center: CGPoint, in context: CGContext,
        unit: CGFloat, color: CGColor
    ) {
        let radius = 5 * unit
        context.setFillColor(color)
        context.fillEllipse(in: CGRect(
            x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2))
        drawString(
            "\(number)",
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: 5.5 * unit),
                .foregroundColor: NSColor.white,
            ],
            centeredAt: center, in: context)
    }

    private static func drawText(
        _ string: String, at point: CGPoint, in context: CGContext, unit: CGFloat
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 9 * unit),
            .foregroundColor: NSColor(calibratedRed: 0.92, green: 0.18, blue: 0.14, alpha: 1),
            .strokeColor: NSColor.white,
            .strokeWidth: -2.5,  // negative: stroke and fill
        ]
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        (string as NSString).draw(at: point, withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawString(
        _ string: String, attributes: [NSAttributedString.Key: Any],
        centeredAt center: CGPoint, in context: CGContext
    ) {
        let size = (string as NSString).size(withAttributes: attributes)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        (string as NSString).draw(
            at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2),
            withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func pixelate(
        _ base: CGImage, in rect: CGRect
    ) -> (image: CGImage, rect: CGRect)? {
        guard rect.width >= 2, rect.height >= 2 else { return nil }
        let input = CIImage(cgImage: base)
        guard let filter = CIFilter(name: "CIPixellate") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(max(8, rect.width / 25), forKey: kCIInputScaleKey)
        filter.setValue(CIVector(x: rect.midX, y: rect.midY), forKey: kCIInputCenterKey)
        guard let output = filter.outputImage?.cropped(to: rect),
              let image = CIContext().createCGImage(output, from: rect)
        else { return nil }
        return (image, rect)
    }
}
