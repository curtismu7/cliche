import CoreGraphics
import Foundation

/// sRGB color stored as components so configs round-trip through JSON.
public struct RGBAColor: Codable, Equatable {
    public var r, g, b, a: Double
    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
    public var cgColor: CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
}

public struct GradientStop: Codable, Equatable {
    public var color: RGBAColor
    public var location: Double  // 0...1
    public init(color: RGBAColor, location: Double) {
        self.color = color; self.location = location
    }
}

/// The whole background. An empty gradient means "no backdrop" (identity).
public struct Gradient: Codable, Equatable {
    public var stops: [GradientStop]
    public var angleDegrees: Double
    public init(stops: [GradientStop], angleDegrees: Double) {
        self.stops = stops; self.angleDegrees = angleDegrees
    }
    public var isEmpty: Bool { stops.isEmpty }

    /// Two-stop convenience for built-ins.
    public static func linear(_ start: RGBAColor, _ end: RGBAColor,
                              angle: Double = 135) -> Gradient {
        Gradient(stops: [GradientStop(color: start, location: 0),
                         GradientStop(color: end, location: 1)],
                 angleDegrees: angle)
    }
}

/// Optional matte band drawn around the screenshot inside the rounded corners.
public struct InsetFrame: Codable, Equatable {
    public var width: Double  // fraction of screenshot min dimension
    public var color: RGBAColor
    public init(width: Double, color: RGBAColor) {
        self.width = width; self.color = color
    }
}

public struct Shadow: Codable, Equatable {
    public var blur: Double            // fraction of min dimension
    public var yOffsetFraction: Double // fraction of min dimension (positive = downward)
    public var opacity: Double         // 0...1; 0 = no shadow
    public init(blur: Double, yOffsetFraction: Double, opacity: Double) {
        self.blur = blur; self.yOffsetFraction = yOffsetFraction; self.opacity = opacity
    }
}

public enum CanvasSize: Codable, Equatable, Hashable {
    case free
    case fixed(width: Int, height: Int, label: String)

    public var label: String {
        switch self {
        case .free: return "Free (fit content)"
        case .fixed(_, _, let label): return label
        }
    }

    public static let socialPresets: [CanvasSize] = [
        .free,
        .fixed(width: 1600, height: 900, label: "X · 1600 × 900"),
        .fixed(width: 1080, height: 1080, label: "Square · 1080 × 1080"),
        .fixed(width: 1080, height: 1350, label: "IG Portrait · 1080 × 1350"),
    ]
}

public struct BeautifyConfig: Codable, Equatable {
    public var background: Gradient
    public var padding: Double        // fraction of min dimension
    public var inset: InsetFrame?
    public var cornerRadius: Double   // fraction of min dimension
    public var shadow: Shadow
    public var canvas: CanvasSize
    public var autoBalance: Bool

    public init(background: Gradient, padding: Double, inset: InsetFrame?,
                cornerRadius: Double, shadow: Shadow, canvas: CanvasSize,
                autoBalance: Bool) {
        self.background = background; self.padding = padding; self.inset = inset
        self.cornerRadius = cornerRadius; self.shadow = shadow
        self.canvas = canvas; self.autoBalance = autoBalance
    }

    /// No background → renderer returns the image untouched.
    public var isIdentity: Bool { background.isEmpty }

    public static let identity = BeautifyConfig(
        background: Gradient(stops: [], angleDegrees: 135),
        padding: 0.09, inset: nil, cornerRadius: 0.017,
        shadow: Shadow(blur: 0.045, yOffsetFraction: 0.016, opacity: 0.45),
        canvas: .free, autoBalance: false)

    /// Default look for a new gradient config (reproduces the old fixed look).
    static func gradient(_ start: RGBAColor, _ end: RGBAColor) -> BeautifyConfig {
        BeautifyConfig(
            background: .linear(start, end),
            padding: 0.09, inset: nil, cornerRadius: 0.017,
            shadow: Shadow(blur: 0.045, yOffsetFraction: 0.016, opacity: 0.45),
            canvas: .free, autoBalance: false)
    }
}

public struct NamedBeautifyConfig: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var config: BeautifyConfig
    public init(id: UUID = UUID(), name: String, config: BeautifyConfig) {
        self.id = id; self.name = name; self.config = config
    }
}

extension BeautifyConfig {
    /// The five gradients from the original BeautifyRenderer, plus None.
    public static let builtInPresets: [NamedBeautifyConfig] = [
        NamedBeautifyConfig(name: "None", config: .identity),
        NamedBeautifyConfig(name: "Indigo",
            config: .gradient(RGBAColor(0.35, 0.30, 0.85), RGBAColor(0.65, 0.35, 0.85))),
        NamedBeautifyConfig(name: "Sunset",
            config: .gradient(RGBAColor(0.95, 0.45, 0.30), RGBAColor(0.90, 0.30, 0.55))),
        NamedBeautifyConfig(name: "Ocean",
            config: .gradient(RGBAColor(0.15, 0.55, 0.85), RGBAColor(0.20, 0.80, 0.75))),
        NamedBeautifyConfig(name: "Forest",
            config: .gradient(RGBAColor(0.15, 0.55, 0.35), RGBAColor(0.55, 0.75, 0.30))),
        NamedBeautifyConfig(name: "Slate",
            config: .gradient(RGBAColor(0.25, 0.28, 0.33), RGBAColor(0.45, 0.50, 0.58))),
    ]
}
