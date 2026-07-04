import Foundation

/// One markup element on a screenshot. Coordinates are in image pixels with
/// a bottom-left origin (CoreGraphics convention).
public struct Annotation: Identifiable, Equatable {
    public enum Kind: Equatable {
        case arrow
        case rectangle
        case text(String)
        case blur
        case counter(Int)
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
