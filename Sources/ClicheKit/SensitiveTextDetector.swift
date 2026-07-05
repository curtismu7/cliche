import AppKit
import Vision

/// Finds text that probably shouldn't be shared — emails, links, phone
/// numbers, and API-key-looking tokens — and returns their bounding boxes
/// in image pixels (bottom-left origin, ready to become blur annotations).
public enum SensitiveTextDetector {
    private static let tokenPattern = try! NSRegularExpression(
        // key/secret/token assignments, bearer values, or long opaque tokens
        pattern: #"(?i)(api[-_]?key|secret|token|bearer|passwd|password)\s*[:=]?\s*\S{6,}|[A-Za-z0-9_\-]{28,}"#)

    public static func detect(in image: CGImage) -> [CGRect] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: image).perform([request])
        guard let observations = request.results else { return [] }

        let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
                | NSTextCheckingResult.CheckingType.phoneNumber.rawValue)
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        var rects: [CGRect] = []

        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string
            let fullRange = NSRange(text.startIndex..., in: text)

            var matchRanges: [NSRange] = []
            detector?.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                if let match { matchRanges.append(match.range) }
            }
            matchRanges += Self.tokenPattern.matches(in: text, range: fullRange)
                .map(\.range)

            for nsRange in matchRanges {
                guard let range = Range(nsRange, in: text) else { continue }
                // Sub-rect of just the matched words when Vision can give it;
                // otherwise the whole line.
                let box = (try? candidate.boundingBox(for: range))?.boundingBox
                    ?? observation.boundingBox
                // Vision boxes are normalized with a bottom-left origin.
                let rect = CGRect(
                    x: box.minX * width,
                    y: box.minY * height,
                    width: box.width * width,
                    height: box.height * height)
                    .insetBy(dx: -3, dy: -3)
                rects.append(rect)
            }
        }
        return rects
    }
}
