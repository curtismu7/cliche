import AVFoundation
import CoreGraphics
import Foundation

/// Converts a recorded video into a looping GIF by sampling frames
/// (record-to-MP4-first is far more reliable than live GIF encoding).
public enum VideoGIF {
    /// Duration is capped so GIFs stay a sane size.
    public static func gifData(
        from videoURL: URL, fps: Double = 10, maxDuration: Double = 30
    ) async -> Data? {
        let asset = AVURLAsset(url: videoURL)
        guard let duration = try? await asset.load(.duration).seconds,
              duration > 0
        else { return nil }
        let usable = min(duration, maxDuration)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 20)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 20)

        var frames: [CGImage] = []
        var time = 0.0
        while time < usable {
            let cmTime = CMTime(seconds: time, preferredTimescale: 600)
            if let image = try? await generator.image(at: cmTime).image {
                frames.append(image)
            }
            time += 1 / fps
        }
        guard !frames.isEmpty else { return nil }
        return GIFBuilder.gifData(frames: frames, frameDelay: 1 / fps)
    }
}
