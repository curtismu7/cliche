import CoreGraphics
import Foundation

/// Pixel-ruler support: from a point, walk outward in each direction until
/// the luminance changes sharply (a UI edge).
public struct EdgeMeasure {
    private let width: Int
    private let height: Int
    private let luminance: [Float]

    public init?(image: CGImage) {
        width = image.width
        height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var lum = [Float](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            let p = i * 4
            lum[i] = 0.2126 * Float(pixels[p]) + 0.7152 * Float(pixels[p + 1])
                + 0.0722 * Float(pixels[p + 2])
        }
        luminance = lum
    }

    private func lum(_ x: Int, _ y: Int) -> Float {
        luminance[y * width + x]
    }

    /// Distances in pixels from `(x, y)` (top-left origin) to the nearest
    /// edge in each direction. Returns nil for out-of-bounds points.
    public func span(
        x: Int, y: Int, threshold: Float = 24
    ) -> (left: Int, right: Int, up: Int, down: Int)? {
        guard x >= 0, x < width, y >= 0, y < height else { return nil }

        var left = 0
        var probe = x
        while probe > 0, abs(lum(probe - 1, y) - lum(probe, y)) < threshold {
            probe -= 1
            left += 1
        }
        var right = 0
        probe = x
        while probe < width - 1, abs(lum(probe + 1, y) - lum(probe, y)) < threshold {
            probe += 1
            right += 1
        }
        var up = 0
        var probeY = y
        while probeY > 0, abs(lum(x, probeY - 1) - lum(x, probeY)) < threshold {
            probeY -= 1
            up += 1
        }
        var down = 0
        probeY = y
        while probeY < height - 1, abs(lum(x, probeY + 1) - lum(x, probeY)) < threshold {
            probeY += 1
            down += 1
        }
        return (left, right, up, down)
    }
}
