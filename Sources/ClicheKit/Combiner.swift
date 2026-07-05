import AppKit

/// Stitches several captures into one laid-out image — for step-by-step
/// docs and side-by-side comparisons.
public enum Combiner {
    public enum Layout: CaseIterable {
        case horizontal, vertical, grid

        public var label: String {
            switch self {
            case .horizontal: return "Side by side"
            case .vertical: return "Stacked"
            case .grid: return "Grid"
            }
        }
    }

    /// Combines 2+ images. Horizontal scales everything to the smallest
    /// height; vertical to the smallest width; grid uses uniform cells of
    /// the largest scaled image, ⌈√n⌉ columns, row-major from top-left.
    /// `gapFraction` is spacing as a fraction of the reference dimension.
    public static func combine(
        _ images: [CGImage], layout: Layout,
        gapFraction: CGFloat = 0.02,
        background: RGBAColor = RGBAColor(1, 1, 1)
    ) -> CGImage? {
        guard images.count >= 2 else { return nil }

        switch layout {
        case .horizontal:
            let height = CGFloat(images.map(\.height).min()!)
            let gap = (height * gapFraction).rounded()
            let widths = images.map {
                (CGFloat($0.width) * height / CGFloat($0.height)).rounded()
            }
            let totalW = widths.reduce(0, +) + gap * CGFloat(images.count - 1)
            return draw(size: CGSize(width: totalW, height: height),
                        background: background) { ctx in
                var x: CGFloat = 0
                for (image, width) in zip(images, widths) {
                    ctx.draw(image, in: CGRect(x: x, y: 0, width: width, height: height))
                    x += width + gap
                }
            }
        case .vertical:
            let width = CGFloat(images.map(\.width).min()!)
            let gap = (width * gapFraction).rounded()
            let heights = images.map {
                (CGFloat($0.height) * width / CGFloat($0.width)).rounded()
            }
            let totalH = heights.reduce(0, +) + gap * CGFloat(images.count - 1)
            return draw(size: CGSize(width: width, height: totalH),
                        background: background) { ctx in
                // First image at the TOP (CG y grows upward).
                var y = totalH
                for (image, height) in zip(images, heights) {
                    y -= height
                    ctx.draw(image, in: CGRect(x: 0, y: y, width: width, height: height))
                    y -= gap
                }
            }
        case .grid:
            let columns = Int(Double(images.count).squareRoot().rounded(.up))
            let rows = Int((Double(images.count) / Double(columns)).rounded(.up))
            // Uniform cell: everything scaled to the smallest height, cell
            // width = widest scaled image.
            let cellH = CGFloat(images.map(\.height).min()!)
            let scaledWidths = images.map {
                (CGFloat($0.width) * cellH / CGFloat($0.height)).rounded()
            }
            let cellW = scaledWidths.max()!
            let gap = (cellH * gapFraction).rounded()
            let totalW = cellW * CGFloat(columns) + gap * CGFloat(columns - 1)
            let totalH = cellH * CGFloat(rows) + gap * CGFloat(rows - 1)
            return draw(size: CGSize(width: totalW, height: totalH),
                        background: background) { ctx in
                for (index, image) in images.enumerated() {
                    let col = index % columns
                    let row = index / columns  // 0 = top row
                    let width = scaledWidths[index]
                    let x = CGFloat(col) * (cellW + gap) + (cellW - width) / 2
                    let y = totalH - CGFloat(row + 1) * cellH - CGFloat(row) * gap
                    ctx.draw(image, in: CGRect(x: x, y: y, width: width, height: cellH))
                }
            }
        }
    }

    private static func draw(
        size: CGSize, background: RGBAColor, body: (CGContext) -> Void
    ) -> CGImage? {
        guard size.width >= 1, size.height >= 1,
              let ctx = CGContext(
                data: nil, width: Int(size.width), height: Int(size.height),
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.setFillColor(background.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        ctx.interpolationQuality = .high
        body(ctx)
        return ctx.makeImage()
    }
}
