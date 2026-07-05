import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum GIFBuilder {
    /// Builds a looping GIF from frames with a uniform per-frame delay.
    public static func gifData(frames: [CGImage], frameDelay: Double) -> Data? {
        guard !frames.isEmpty else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.gif.identifier as CFString, frames.count, nil)
        else { return nil }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ] as CFDictionary)
        let frameProperties = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: frameDelay]
        ] as CFDictionary
        for frame in frames {
            CGImageDestinationAddImage(destination, frame, frameProperties)
        }
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
