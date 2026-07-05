import CoreGraphics
import Vision

/// Stitches frames of a vertically scrolling region (captured top-to-bottom)
/// into one tall image, aligning consecutive frames with Vision's
/// translational registration.
public enum Stitcher {
    public static func stitch(_ frames: [CGImage]) -> CGImage? {
        guard let first = frames.first else { return nil }
        guard frames.count > 1 else { return first }

        // Cumulative downward offset (in pixels, top-left origin) of each
        // frame relative to the first.
        var offsets: [Int] = [0]
        var kept: [CGImage] = [first]
        var cumulative = 0

        for index in 1..<frames.count {
            let request = VNTranslationalImageRegistrationRequest(
                targetedCGImage: frames[index])
            try? VNImageRequestHandler(cgImage: kept[kept.count - 1])
                .perform([request])
            guard let transform = request.results?.first?.alignmentTransform else {
                continue
            }
            let dy = Int(abs(transform.ty).rounded())
            // No meaningful scroll between frames — drop the duplicate.
            guard dy >= 3 else { continue }
            // A jump larger than a frame means registration failed; skip.
            guard dy < frames[index].height else { continue }
            cumulative += dy
            offsets.append(cumulative)
            kept.append(frames[index])
        }

        guard kept.count > 1 else { return first }
        let width = first.width
        let totalHeight = cumulative + kept[kept.count - 1].height
        guard let context = CGContext(
            data: nil, width: width, height: totalHeight,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        // Later frames draw on top; convert top-left offsets to CG's
        // bottom-left origin.
        for (frame, offset) in zip(kept, offsets) {
            let y = totalHeight - offset - frame.height
            context.draw(frame, in: CGRect(
                x: 0, y: y, width: frame.width, height: frame.height))
        }
        return context.makeImage()
    }
}
