import Foundation

/// One markup element on a screenshot. Coordinates are in image pixels with
/// a bottom-left origin (CoreGraphics convention).
public struct Annotation: Identifiable, Equatable, Codable {
    public enum Kind: Equatable {
        case arrow
        case rectangle
        case text(String)
        /// Pixelate (CIPixellate blocks).
        case blur
        case counter(Int)
        case ellipse
        case line
        case freehand(points: [CGPoint])
        /// Translucent marker fill.
        case highlight
        /// Unrecoverable gaussian blur (downscale-then-upscale).
        case gaussianBlur
    }

    public let id: UUID
    public var kind: Kind
    public var start: CGPoint
    public var end: CGPoint

    public init(id: UUID = UUID(), kind: Kind, start: CGPoint, end: CGPoint) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
    }

    /// Normalized bounding rect between start and end.
    public var rect: CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(start.x - end.x),
            height: abs(start.y - end.y))
    }
}

// MARK: - Codable (type-discriminated so project files stay readable)

extension Annotation.Kind: Codable {
    private enum CodingKeys: String, CodingKey { case type, text, number, points }

    private var typeName: String {
        switch self {
        case .arrow: return "arrow"
        case .rectangle: return "rectangle"
        case .text: return "text"
        case .blur: return "blur"
        case .counter: return "counter"
        case .ellipse: return "ellipse"
        case .line: return "line"
        case .freehand: return "freehand"
        case .highlight: return "highlight"
        case .gaussianBlur: return "gaussianBlur"
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(typeName, forKey: .type)
        switch self {
        case .text(let string): try c.encode(string, forKey: .text)
        case .counter(let number): try c.encode(number, forKey: .number)
        case .freehand(let points):
            try c.encode(points.flatMap { [$0.x, $0.y] }, forKey: .points)
        default: break
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "arrow": self = .arrow
        case "rectangle": self = .rectangle
        case "text": self = .text(try c.decode(String.self, forKey: .text))
        case "blur": self = .blur
        case "counter": self = .counter(try c.decode(Int.self, forKey: .number))
        case "ellipse": self = .ellipse
        case "line": self = .line
        case "freehand":
            let flat = try c.decode([CGFloat].self, forKey: .points)
            let points = stride(from: 0, to: flat.count - 1, by: 2).map {
                CGPoint(x: flat[$0], y: flat[$0 + 1])
            }
            self = .freehand(points: points)
        case "highlight": self = .highlight
        case "gaussianBlur": self = .gaussianBlur
        case let unknown:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c,
                debugDescription: "unknown annotation kind '\(unknown)'")
        }
    }
}
