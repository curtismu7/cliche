import Foundation

public struct ClipItem: Identifiable, Equatable, Codable {
    public enum Kind: Equatable, Codable {
        case text(String)
        case image(fileName: String, sha256: String)
    }

    public let id: UUID
    public let date: Date
    public let kind: Kind
    public var pinned: Bool

    public init(id: UUID, date: Date, kind: Kind, pinned: Bool = false) {
        self.id = id
        self.date = date
        self.kind = kind
        self.pinned = pinned
    }

    /// Two items with the same key are the same logical clipboard content.
    var dedupeKey: String {
        switch kind {
        case .text(let s): return "t:\(s)"
        case .image(_, let sha): return "i:\(sha)"
        }
    }
}
