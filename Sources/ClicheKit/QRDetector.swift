import CoreGraphics
import Vision

public enum QRDetector {
    /// Payload of the first QR code found in the image, if any.
    public static func firstQRPayload(in image: CGImage) -> String? {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return request.results?.compactMap(\.payloadStringValue).first
    }
}
