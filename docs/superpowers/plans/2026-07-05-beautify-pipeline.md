# Beautify Pipeline (B1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Cliché's fixed 5-preset backdrop with a full "social-ready" beautify pipeline — editable linear-gradient backgrounds, adjustable padding/inset/corner/shadow, auto-balance centering, named user presets, and fixed social canvas sizes — previewed live in the annotation editor.

**Architecture:** Follow the existing `Annotation`/`AnnotationRenderer` split: a `Codable` value-type config (`BeautifyConfig`) plus a stateless pure renderer. The renderer exposes a `layout` geometry function that is the single source of truth so the editor's gesture→pixel mapping and the pixel compositor always agree. Presets are named configs persisted in `AppSettings`.

**Tech Stack:** Swift 6 (language mode 5), macOS 14+, SwiftUI + AppKit, Core Graphics / Core Image. Tests run through the existing `cliche-selftest` executable (no XCTest available).

## Global Constraints

- Platform floor: macOS 14 (`.macOS(.v14)`); Swift language mode v5. Do not raise.
- No new third-party dependencies.
- New model + renderer code lives in the `ClicheKit` target; UI lives in the `Cliche` target.
- Tests are `do { … expect(condition, "label") }` blocks appended to `Sources/cliche-selftest/main.swift`. `expect(_ condition: Bool, _ label: String)` already exists. The executable exits non-zero if any check fails.
- Colors in persisted models are stored as sRGB `Double` components (never `CGColor`/`NSColor`) so configs round-trip through JSON.
- All spatial parameters (padding, inset width, corner radius, shadow blur/offset) are stored as **fractions of the screenshot's min dimension**, resolved to pixels in the renderer, so output is resolution-independent.
- Preserve existing behavior for users who never open the inspector: absence of a persisted config resolves to `BeautifyConfig.identity`, which renders the image unchanged.

---

## File Structure

- **Create** `Sources/ClicheKit/BeautifyConfig.swift` — value-type model (`BeautifyConfig`, `Gradient`, `GradientStop`, `RGBAColor`, `InsetFrame`, `Shadow`, `CanvasSize`, `NamedBeautifyConfig`), `identity`, and built-in presets. (Task 1)
- **Rewrite** `Sources/ClicheKit/BeautifyRenderer.swift` — remove `BeautifyStyle`; add `sourceCrop`, `layout`, and `render(_:to:)`. (Tasks 2 & 5)
- **Modify** `Sources/ClicheKit/AppSettings.swift` — add `lastBeautifyConfig` and `beautifyPresets` persistence. (Task 3)
- **Create** `Sources/Cliche/BeautifyInspector.swift` — the SwiftUI inspector panel. (Task 4)
- **Modify** `Sources/Cliche/AnnotationEditor.swift` — host the inspector, live-composited canvas, gesture remapping. (Task 4)
- **Modify** `Sources/cliche-selftest/main.swift` — replace the old `beautifyRenderer` block; add model, layout, crop, and persistence tests. (Tasks 1, 2, 3, 5)

---

### Task 1: BeautifyConfig data model

**Files:**
- Create: `Sources/ClicheKit/BeautifyConfig.swift`
- Test: `Sources/cliche-selftest/main.swift` (append a new `do { }` block)

**Interfaces:**
- Produces:
  - `struct RGBAColor: Codable, Equatable { var r, g, b, a: Double; init(_ r:Double,_ g:Double,_ b:Double,_ a:Double = 1); var cgColor: CGColor }`
  - `struct GradientStop: Codable, Equatable { var color: RGBAColor; var location: Double }`
  - `struct Gradient: Codable, Equatable { var stops: [GradientStop]; var angleDegrees: Double; var isEmpty: Bool }`
  - `struct InsetFrame: Codable, Equatable { var width: Double; var color: RGBAColor }`
  - `struct Shadow: Codable, Equatable { var blur: Double; var yOffsetFraction: Double; var opacity: Double }`
  - `enum CanvasSize: Codable, Equatable { case free; case fixed(width: Int, height: Int, label: String); var label: String; static let socialPresets: [CanvasSize] }`
  - `struct BeautifyConfig: Codable, Equatable { var background: Gradient; var padding: Double; var inset: InsetFrame?; var cornerRadius: Double; var shadow: Shadow; var canvas: CanvasSize; var autoBalance: Bool; var isIdentity: Bool; static let identity: BeautifyConfig }`
  - `struct NamedBeautifyConfig: Codable, Equatable, Identifiable { var id: UUID; var name: String; var config: BeautifyConfig }`
  - `extension BeautifyConfig { static let builtInPresets: [NamedBeautifyConfig] }`

- [x] **Step 1: Write the failing test**

Append this block to `Sources/cliche-selftest/main.swift` (after the existing `// beautifyRenderer` block):

```swift
// beautifyConfigModel
do {
    // Identity renders nothing → empty gradient.
    expect(BeautifyConfig.identity.isIdentity, "identity config is identity")

    // Built-ins: None + 5 gradients, first is identity.
    let builtins = BeautifyConfig.builtInPresets
    expect(builtins.count == 6, "six built-in presets (None + 5 gradients)")
    expect(builtins.first?.config.isIdentity == true, "first built-in is None/identity")
    expect(builtins.contains { $0.name == "Indigo" }, "built-ins include Indigo")

    // Codable round-trip preserves value equality.
    let indigo = builtins.first { $0.name == "Indigo" }!.config
    let data = try! JSONEncoder().encode(indigo)
    let decoded = try! JSONDecoder().decode(BeautifyConfig.self, from: data)
    expect(decoded == indigo, "BeautifyConfig JSON round-trips to an equal value")

    // CanvasSize round-trips including the fixed case.
    let canvas = CanvasSize.fixed(width: 1600, height: 900, label: "X · 1600 × 900")
    let cdata = try! JSONEncoder().encode(canvas)
    let cdecoded = try! JSONDecoder().decode(CanvasSize.self, from: cdata)
    expect(cdecoded == canvas, "CanvasSize.fixed round-trips")
    expect(CanvasSize.socialPresets.first == .free, "social presets start with .free")
}
```

- [x] **Step 2: Run to verify it fails**

Run: `cd /Users/cmuir/Development/cliche && swift build 2>&1 | tail -5`
Expected: FAIL — compile error, `cannot find 'BeautifyConfig' in scope` (the type does not exist yet).

- [x] **Step 3: Write minimal implementation**

Create `Sources/ClicheKit/BeautifyConfig.swift`:

```swift
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

public enum CanvasSize: Codable, Equatable {
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
```

- [x] **Step 4: Run to verify it passes**

Run: `cd /Users/cmuir/Development/cliche && swift run cliche-selftest 2>&1 | grep -i "config\|round-trip\|preset\|canvas"`
Expected: all matching lines start with `PASS`. (The old `beautify .none`/`beautify pads` lines still reference the old API and remain untouched until Task 5.)

- [x] **Step 5: Commit**

```bash
git add Sources/ClicheKit/BeautifyConfig.swift Sources/cliche-selftest/main.swift
git commit -m "feat(beautify): add BeautifyConfig value-type model and built-in presets"
```

---

### Task 2: Renderer — sourceCrop, layout, render(config:)

**Files:**
- Modify: `Sources/ClicheKit/BeautifyRenderer.swift` (add new API alongside the existing `BeautifyStyle.apply`, which stays until Task 5)
- Test: `Sources/cliche-selftest/main.swift` (append a new `do { }` block)

**Interfaces:**
- Consumes: `BeautifyConfig`, `CanvasSize` (Task 1).
- Produces:
  - `struct BeautifyLayout: Equatable { var outputSize: CGSize; var screenshotRect: CGRect }`
  - `static func layout(_ config: BeautifyConfig, croppedSize: CGSize) -> BeautifyLayout`
  - `static func sourceCrop(_ config: BeautifyConfig, in image: CGImage) -> CGRect`
  - `static func render(_ config: BeautifyConfig, to image: CGImage) -> CGImage?`

- [x] **Step 1: Write the failing test**

Append to `Sources/cliche-selftest/main.swift`:

```swift
// beautifyLayoutAndCrop
do {
    // layout: .free canvas → output is cropped size + 2·padding (no inset).
    let cfg = BeautifyConfig.gradient(RGBAColor(0, 0, 1), RGBAColor(0, 1, 0))
    let cropped = CGSize(width: 800, height: 600)
    let L = BeautifyRenderer.layout(cfg, croppedSize: cropped)
    let pad = 0.09 * 600.0
    expect(abs(L.outputSize.width - (800 + 2 * pad)) < 0.5
        && abs(L.outputSize.height - (600 + 2 * pad)) < 0.5,
        "free layout = cropped size + 2·padding")
    expect(abs(L.screenshotRect.origin.x - pad) < 0.5
        && abs(L.screenshotRect.width - 800) < 0.5,
        "free layout centers screenshot inside padding")

    // layout: fixed canvas → output is EXACTLY the target size.
    var fixedCfg = cfg
    fixedCfg.canvas = .fixed(width: 1600, height: 900, label: "X")
    let F = BeautifyRenderer.layout(fixedCfg, croppedSize: cropped)
    expect(F.outputSize == CGSize(width: 1600, height: 900),
        "fixed layout output equals exact target size")
    expect(F.screenshotRect.midX == 800 && F.screenshotRect.midY == 450,
        "fixed layout centers screenshot in canvas")

    // sourceCrop: auto-balance trims a uniform border to the inner block.
    let bw = 200, bh = 160
    let bctx = CGContext(data: nil, width: bw, height: bh, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    bctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    bctx.fill(CGRect(x: 0, y: 0, width: bw, height: bh))
    bctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    bctx.fill(CGRect(x: 40, y: 30, width: 100, height: 80))  // inner red block
    let bordered = bctx.makeImage()!
    var balCfg = cfg
    balCfg.autoBalance = true
    let crop = BeautifyRenderer.sourceCrop(balCfg, in: bordered)
    expect(crop.width <= 108 && crop.width >= 96
        && crop.height <= 88 && crop.height >= 76,
        "auto-balance trims uniform margins to the inner block (±1 row/col)")

    // render: identity returns the image unchanged.
    let idImg = bctx.makeImage()!
    let out = BeautifyRenderer.render(.identity, to: idImg)
    expect(out?.width == bw && out?.height == bh, "render identity leaves image unchanged")

    // render: fixed canvas produces exactly the target pixel size.
    let styled = BeautifyRenderer.render(fixedCfg, to: idImg)
    expect(styled?.width == 1600 && styled?.height == 900,
        "render fixed canvas outputs exact target pixel size")
}
```

- [x] **Step 2: Run to verify it fails**

Run: `cd /Users/cmuir/Development/cliche && swift build 2>&1 | tail -5`
Expected: FAIL — compile error, `type 'BeautifyRenderer' has no member 'layout'`.

- [x] **Step 3: Write minimal implementation**

Add to `Sources/ClicheKit/BeautifyRenderer.swift` inside the `public enum BeautifyRenderer { … }` (keep the existing `BeautifyStyle` and `apply(_:to:)` for now). Add `import CoreImage` at top if not present:

```swift
    public struct BeautifyLayout: Equatable {
        public var outputSize: CGSize
        public var screenshotRect: CGRect
    }

    /// Where the (possibly trimmed) screenshot lands and how big the output is.
    /// Pure geometry — takes the cropped screenshot size, not the image.
    public static func layout(_ config: BeautifyConfig, croppedSize: CGSize) -> BeautifyLayout {
        let minDim = min(croppedSize.width, croppedSize.height)
        let pad = config.padding * minDim
        let insetW = (config.inset?.width ?? 0) * minDim
        let frameW = croppedSize.width + 2 * insetW
        let frameH = croppedSize.height + 2 * insetW
        let contentW = frameW + 2 * pad
        let contentH = frameH + 2 * pad

        switch config.canvas {
        case .free:
            let rect = CGRect(x: pad + insetW, y: pad + insetW,
                              width: croppedSize.width, height: croppedSize.height)
            return BeautifyLayout(
                outputSize: CGSize(width: contentW, height: contentH),
                screenshotRect: rect)
        case .fixed(let w, let h, _):
            let canvas = CGSize(width: CGFloat(w), height: CGFloat(h))
            let s = min(canvas.width / contentW, canvas.height / contentH)
            let drawW = contentW * s, drawH = contentH * s
            let ox = (canvas.width - drawW) / 2, oy = (canvas.height - drawH) / 2
            let rect = CGRect(
                x: ox + (pad + insetW) * s, y: oy + (pad + insetW) * s,
                width: croppedSize.width * s, height: croppedSize.height * s)
            return BeautifyLayout(outputSize: canvas, screenshotRect: rect)
        }
    }

    /// Region of `image` to composite. Full image unless auto-balance is on,
    /// in which case uniform-color margins (matching the top-left pixel) are
    /// trimmed. Returns an integral rect in image pixel coordinates.
    public static func sourceCrop(_ config: BeautifyConfig, in image: CGImage) -> CGRect {
        let full = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard config.autoBalance else { return full }
        guard let data = image.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return full }
        let bpr = image.bytesPerRow
        let bpp = image.bitsPerPixel / 8
        guard bpp >= 3 else { return full }

        func px(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let o = y * bpr + x * bpp
            return (Int(ptr[o]), Int(ptr[o + 1]), Int(ptr[o + 2]))
        }
        let bg = px(0, 0)
        func differs(_ x: Int, _ y: Int) -> Bool {
            let p = px(x, y)
            return abs(p.0 - bg.0) + abs(p.1 - bg.1) + abs(p.2 - bg.2) > 24
        }

        var minX = image.width, minY = image.height, maxX = -1, maxY = -1
        for y in 0..<image.height {
            for x in 0..<image.width where differs(x, y) {
                if x < minX { minX = x }; if x > maxX { maxX = x }
                if y < minY { minY = y }; if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return full }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// Composites `image` onto the configured backdrop. Identity → unchanged.
    public static func render(_ config: BeautifyConfig, to image: CGImage) -> CGImage? {
        if config.isIdentity { return image }
        let crop = sourceCrop(config, in: image)
        let cropped = image.cropping(to: crop) ?? image
        let croppedSize = CGSize(width: cropped.width, height: cropped.height)
        let l = layout(config, croppedSize: croppedSize)
        let outW = Int(l.outputSize.width.rounded())
        let outH = Int(l.outputSize.height.rounded())
        guard outW > 0, outH > 0,
              let ctx = CGContext(
                data: nil, width: outW, height: outH,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        let outputRect = CGRect(x: 0, y: 0, width: outW, height: outH)
        drawGradient(config.background, in: outputRect, context: ctx)

        let shot = l.screenshotRect
        let shotMin = min(shot.width, shot.height)
        let cornerRadius = config.cornerRadius * shotMin
        let insetW = (config.inset?.width ?? 0) * shotMin
        let matte = shot.insetBy(dx: -insetW, dy: -insetW)
        let plateRadius = cornerRadius + insetW
        let platePath = CGPath(roundedRect: matte,
                               cornerWidth: plateRadius, cornerHeight: plateRadius,
                               transform: nil)

        // Shadow cast by an opaque plate under the (matte-expanded) screenshot.
        if config.shadow.opacity > 0 {
            ctx.saveGState()
            ctx.setShadow(
                offset: CGSize(width: 0, height: -config.shadow.yOffsetFraction * shotMin),
                blur: config.shadow.blur * shotMin,
                color: CGColor(gray: 0, alpha: config.shadow.opacity))
            ctx.addPath(platePath)
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillPath()
            ctx.restoreGState()
        }

        // Inset matte fill (color band around the screenshot).
        if let inset = config.inset, insetW > 0 {
            ctx.saveGState()
            ctx.addPath(platePath)
            ctx.setFillColor(inset.color.cgColor)
            ctx.fillPath()
            ctx.restoreGState()
        }

        // Screenshot clipped to its rounded rect.
        let shotPath = CGPath(roundedRect: shot,
                              cornerWidth: cornerRadius, cornerHeight: cornerRadius,
                              transform: nil)
        ctx.saveGState()
        ctx.addPath(shotPath)
        ctx.clip()
        ctx.draw(cropped, in: shot)
        ctx.restoreGState()

        return ctx.makeImage()
    }

    private static func drawGradient(_ gradient: Gradient, in rect: CGRect, context: CGContext) {
        guard !gradient.isEmpty else { return }
        let space = CGColorSpaceCreateDeviceRGB()
        let colors = gradient.stops.map { $0.color.cgColor } as CFArray
        let locations = gradient.stops.map { CGFloat($0.location) }
        guard let cg = CGGradient(colorsSpace: space, colors: colors, locations: locations)
        else { return }
        let a = gradient.angleDegrees * .pi / 180
        let dx = cos(a), dy = sin(a)
        let half = abs(dx) * rect.width / 2 + abs(dy) * rect.height / 2
        let start = CGPoint(x: rect.midX - dx * half, y: rect.midY - dy * half)
        let end = CGPoint(x: rect.midX + dx * half, y: rect.midY + dy * half)
        context.drawLinearGradient(cg, start: start, end: end, options: [])
    }
```

- [x] **Step 4: Run to verify it passes**

Run: `cd /Users/cmuir/Development/cliche && swift run cliche-selftest 2>&1 | grep -i "layout\|auto-balance\|render\|canvas outputs"`
Expected: all matching lines `PASS`.

- [x] **Step 5: Commit**

```bash
git add Sources/ClicheKit/BeautifyRenderer.swift Sources/cliche-selftest/main.swift
git commit -m "feat(beautify): add config-driven renderer with layout, crop, and auto-balance"
```

---

### Task 3: AppSettings persistence

**Files:**
- Modify: `Sources/ClicheKit/AppSettings.swift`
- Test: `Sources/cliche-selftest/main.swift` (append a new `do { }` block)

**Interfaces:**
- Consumes: `BeautifyConfig`, `NamedBeautifyConfig` (Task 1).
- Produces (on `AppSettings`):
  - `var lastBeautifyConfig: BeautifyConfig { get set }` (persisted JSON, default `.identity`)
  - `var beautifyPresets: [NamedBeautifyConfig] { get set }` (persisted JSON, default `[]`)

- [x] **Step 1: Write the failing test**

Append to `Sources/cliche-selftest/main.swift`:

```swift
// beautifyPersistence
do {
    let suite = "ClicheBeautifyTest-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let settings = AppSettings(defaults: defaults)

    expect(settings.lastBeautifyConfig.isIdentity, "lastBeautifyConfig defaults to identity")
    expect(settings.beautifyPresets.isEmpty, "beautifyPresets default to empty")

    var cfg = BeautifyConfig.gradient(RGBAColor(1, 0, 0), RGBAColor(0, 0, 1))
    cfg.padding = 0.2
    settings.lastBeautifyConfig = cfg
    settings.beautifyPresets = [NamedBeautifyConfig(name: "Launch shot", config: cfg)]

    let reloaded = AppSettings(defaults: defaults)
    expect(reloaded.lastBeautifyConfig == cfg, "lastBeautifyConfig persists across instances")
    expect(reloaded.beautifyPresets.count == 1
        && reloaded.beautifyPresets[0].name == "Launch shot",
        "beautifyPresets persist across instances")
    defaults.removePersistentDomain(forName: suite)
}
```

- [x] **Step 2: Run to verify it fails**

Run: `cd /Users/cmuir/Development/cliche && swift build 2>&1 | tail -5`
Expected: FAIL — compile error, `value of type 'AppSettings' has no member 'lastBeautifyConfig'`.

- [x] **Step 3: Write minimal implementation**

In `Sources/ClicheKit/AppSettings.swift`, add these stored properties to the class body (place them after `menuBarStyle`, before `private let defaults`):

```swift
    /// Last beautify config used in the editor; the editor opens with this.
    public var lastBeautifyConfig: BeautifyConfig {
        didSet { Self.encode(lastBeautifyConfig, to: defaults, key: "lastBeautifyConfig") }
    }

    /// User-saved named beautify presets.
    public var beautifyPresets: [NamedBeautifyConfig] {
        didSet { Self.encode(beautifyPresets, to: defaults, key: "beautifyPresets") }
    }
```

Add these JSON helpers as static methods inside the class (e.g. just above `public init`):

```swift
    private static func encode<T: Encodable>(_ value: T, to defaults: UserDefaults, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from defaults: UserDefaults,
                                             key: String, default fallback: T) -> T {
        guard let data = defaults.data(forKey: key),
              let value = try? JSONDecoder().decode(type, from: data)
        else { return fallback }
        return value
    }
```

In `init(defaults:)`, initialize the two new properties (add after the existing assignments, before the closing brace):

```swift
        self.lastBeautifyConfig = Self.decode(
            BeautifyConfig.self, from: defaults,
            key: "lastBeautifyConfig", default: .identity)
        self.beautifyPresets = Self.decode(
            [NamedBeautifyConfig].self, from: defaults,
            key: "beautifyPresets", default: [])
```

- [x] **Step 4: Run to verify it passes**

Run: `cd /Users/cmuir/Development/cliche && swift run cliche-selftest 2>&1 | grep -i "beautifyPresets\|lastBeautifyConfig\|persist"`
Expected: all matching lines `PASS`.

- [x] **Step 5: Commit**

```bash
git add Sources/ClicheKit/AppSettings.swift Sources/cliche-selftest/main.swift
git commit -m "feat(beautify): persist last config and named presets in AppSettings"
```

---

### Task 4: Editor inspector + live-composited canvas

**Files:**
- Create: `Sources/Cliche/BeautifyInspector.swift`
- Modify: `Sources/Cliche/AnnotationEditor.swift`
- Verification: manual (SwiftUI — no self-test harness for UI)

**Interfaces:**
- Consumes: `BeautifyConfig`, `NamedBeautifyConfig`, `AppSettings`, `BeautifyRenderer.layout/render/sourceCrop`.
- Produces: `struct BeautifyInspector: View` (binds a `BeautifyConfig` and the settings' preset list); an updated `AnnotationEditorView` whose canvas shows `exported` and whose gestures map through `BeautifyRenderer`.

- [x] **Step 1: Create the inspector view**

Create `Sources/Cliche/BeautifyInspector.swift`:

```swift
import AppKit
import ClicheKit
import SwiftUI

/// Right-hand panel of the annotation editor: background, frame, shadow,
/// canvas size, and preset management. Binds a BeautifyConfig the editor
/// composites live.
struct BeautifyInspector: View {
    @Binding var config: BeautifyConfig
    let settings: AppSettings
    @State private var presetName = ""
    @State private var showingSave = false

    private var gradientStart: Binding<Color> {
        Binding(
            get: { config.background.stops.first.map { Color(cgColor: $0.color.cgColor) } ?? .black },
            set: { setStop(0, $0) })
    }
    private var gradientEnd: Binding<Color> {
        Binding(
            get: { config.background.stops.last.map { Color(cgColor: $0.color.cgColor) } ?? .black },
            set: { setStop(config.background.stops.count - 1, $0) })
    }

    private func setStop(_ index: Int, _ color: Color) {
        guard let rgba = color.rgba else { return }
        if config.background.stops.isEmpty {
            config.background.stops = [
                GradientStop(color: rgba, location: 0),
                GradientStop(color: rgba, location: 1)]
        } else if config.background.stops.indices.contains(index) {
            config.background.stops[index].color = rgba
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                presetSection
                Divider()
                backgroundSection
                Divider()
                frameSection
                Divider()
                shadowSection
                Divider()
                canvasSection
            }
            .padding(14)
        }
        .frame(width: 288)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var presetSection: some View {
        HStack(spacing: 8) {
            Menu(currentPresetName) {
                Section("Built-in") {
                    ForEach(BeautifyConfig.builtInPresets) { preset in
                        Button(preset.name) { config = preset.config }
                    }
                }
                if !settings.beautifyPresets.isEmpty {
                    Section("Yours") {
                        ForEach(settings.beautifyPresets) { preset in
                            Button(preset.name) { config = preset.config }
                        }
                    }
                }
            }
            Button {
                presetName = ""
                showingSave = true
            } label: { Image(systemName: "plus") }
                .help("Save as preset…")
        }
        .sheet(isPresented: $showingSave) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Preset name", text: $presetName).frame(width: 220)
                HStack {
                    Spacer()
                    Button("Cancel") { showingSave = false }
                        .keyboardShortcut(.cancelAction)
                    Button("Save") {
                        if !presetName.isEmpty {
                            settings.beautifyPresets.append(
                                NamedBeautifyConfig(name: presetName, config: config))
                        }
                        showingSave = false
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(presetName.isEmpty)
                }
            }.padding(14)
        }
    }

    private var currentPresetName: String {
        BeautifyConfig.builtInPresets.first { $0.config == config }?.name
            ?? settings.beautifyPresets.first { $0.config == config }?.name
            ?? "Custom"
    }

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("BACKGROUND").sectionLabel()
            HStack {
                ColorPicker("", selection: gradientStart).labelsHidden()
                ColorPicker("", selection: gradientEnd).labelsHidden()
                Spacer()
            }
            slider("Angle", value: $config.background.angleDegrees, range: 0...360, unit: "°")
        }
    }

    private var frameSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("FRAME").sectionLabel()
            slider("Padding", value: $config.padding, range: 0...0.4)
            slider("Corner", value: $config.cornerRadius, range: 0...0.1)
            Toggle("Inset matte", isOn: Binding(
                get: { config.inset != nil },
                set: { config.inset = $0
                    ? InsetFrame(width: 0.03, color: RGBAColor(1, 1, 1))
                    : nil }))
        }
    }

    private var shadowSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("SHADOW").sectionLabel()
            slider("Blur", value: $config.shadow.blur, range: 0...0.12)
            slider("Offset", value: $config.shadow.yOffsetFraction, range: 0...0.08)
            slider("Opacity", value: $config.shadow.opacity, range: 0...1, unit: "%", scale: 100)
        }
    }

    private var canvasSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("CANVAS").sectionLabel()
            Picker("", selection: $config.canvas) {
                ForEach(Array(CanvasSize.socialPresets.enumerated()), id: \.offset) { _, size in
                    Text(size.label).tag(size)
                }
            }
            .labelsHidden()
            Toggle("Auto-balance", isOn: $config.autoBalance)
        }
    }

    private func slider(_ name: String, value: Binding<Double>,
                        range: ClosedRange<Double>, unit: String = "",
                        scale: Double = 1) -> some View {
        HStack(spacing: 8) {
            Text(name).frame(width: 62, alignment: .leading)
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Slider(value: value, in: range)
            Text("\(Int((value.wrappedValue * scale).rounded()))\(unit)")
                .font(.system(size: 11)).monospacedDigit()
                .foregroundStyle(.tertiary).frame(width: 34, alignment: .trailing)
        }
    }
}

private extension Text {
    func sectionLabel() -> some View {
        self.font(.system(size: 10.5, weight: .bold))
            .tracking(0.7).foregroundStyle(.tertiary)
    }
}

extension Color {
    /// sRGB components for persistence; nil if the color can't be resolved.
    var rgba: RGBAColor? {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return RGBAColor(Double(c.redComponent), Double(c.greenComponent),
                         Double(c.blueComponent), Double(c.alphaComponent))
    }
}
```

- [x] **Step 2: Wire the inspector into the editor**

In `Sources/Cliche/AnnotationEditor.swift`:

(a) Replace the `@State private var backdrop: BeautifyStyle = .none` line with:

```swift
    @State private var config: BeautifyConfig
```

(b) `AnnotationEditorView` currently has memberwise defaults for its `@State`. Add an explicit initializer so the editor opens with the persisted config. Add these stored properties and init right after `let onSave: (CGImage) -> Void`:

```swift
    let settings: AppSettings

    init(base: CGImage, settings: AppSettings,
         onCopy: @escaping (CGImage) -> Void,
         onSave: @escaping (CGImage) -> Void) {
        self.base = base
        self.settings = settings
        self.onCopy = onCopy
        self.onSave = onSave
        _config = State(initialValue: settings.lastBeautifyConfig)
    }
```

(c) Replace the `exported` computed property body:

```swift
    private var exported: CGImage {
        BeautifyRenderer.render(config, to: flattened) ?? flattened
    }
```

(d) Remove the old `Picker("Backdrop", …)` block from `toolbar` (the whole `Picker` … `.help(...)` chain that iterated `BeautifyStyle.allCases`).

(e) Change `body` so the canvas sits beside the inspector, and persist config on change. Replace the `body` `VStack` with:

```swift
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                toolbar
                Divider()
                GeometryReader { geometry in
                    canvas(in: geometry.size)
                }
                .background(Color(nsColor: .underPageBackgroundColor))
            }
            Divider()
            BeautifyInspector(config: $config, settings: settings)
        }
        .onChange(of: config) { settings.lastBeautifyConfig = config }
        .sheet(isPresented: Binding(
            get: { pendingTextPoint != nil },
            set: { if !$0 { pendingTextPoint = nil } }
        )) {
            textSheet
        }
    }
```

(f) Replace `canvas(in:)` so it displays the composited `exported` image and maps gestures through `BeautifyRenderer`. Replace the whole `private func canvas(in available: CGSize)` with:

```swift
    private func canvas(in available: CGSize) -> some View {
        let display = exported
        let crop = BeautifyRenderer.sourceCrop(config, in: flattened)
        let croppedSize = CGSize(width: crop.width, height: crop.height)
        let l = BeautifyRenderer.layout(config, croppedSize: croppedSize)
        let outW = l.outputSize.width, outH = l.outputSize.height
        let scale = min(available.width / outW, available.height / outH)
        let shown = CGSize(width: outW * scale, height: outH * scale)
        let origin = CGPoint(
            x: (available.width - shown.width) / 2,
            y: (available.height - shown.height) / 2)
        let shot = l.screenshotRect  // in output pixels, bottom-left origin

        // Map a SwiftUI view point (top-left origin) to base image pixels.
        func imagePoint(_ viewPoint: CGPoint) -> CGPoint {
            let outX = (viewPoint.x - origin.x) / scale
            let outYTop = (viewPoint.y - origin.y) / scale
            let outY = outH - outYTop  // flip to bottom-left origin
            let sx = shot.width / croppedSize.width
            let sy = shot.height / croppedSize.height
            let cropX = (outX - shot.minX) / sx
            let cropYFromBottom = (outY - shot.minY) / sy
            // crop origin is top-left in image space; base image is top-left origin
            let baseX = crop.minX + cropX
            let baseYTop = crop.minY + (croppedSize.height - cropYFromBottom)
            return CGPoint(
                x: min(max(baseX, 0), CGFloat(flattened.width)),
                y: min(max(CGFloat(flattened.height) - baseYTop, 0), CGFloat(flattened.height)))
        }

        return Image(nsImage: NSImage(
            cgImage: display,
            size: NSSize(width: outW, height: outH)))
            .resizable()
            .interpolation(.high)
            .frame(width: shown.width, height: shown.height)
            .position(x: origin.x + shown.width / 2, y: origin.y + shown.height / 2)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let start = imagePoint(value.startLocation)
                        let current = imagePoint(value.location)
                        switch tool {
                        case .arrow: draft = Annotation(kind: .arrow, start: start, end: current)
                        case .rectangle: draft = Annotation(kind: .rectangle, start: start, end: current)
                        case .blur: draft = Annotation(kind: .blur, start: start, end: current)
                        case .text, .counter: break
                        }
                    }
                    .onEnded { value in
                        let point = imagePoint(value.location)
                        switch tool {
                        case .arrow, .rectangle, .blur:
                            if let finished = draft,
                               hypot(finished.end.x - finished.start.x,
                                     finished.end.y - finished.start.y) > 4 {
                                annotations.append(finished)
                            }
                            draft = nil
                        case .counter:
                            annotations.append(Annotation(
                                kind: .counter(nextCounter), start: point, end: point))
                            nextCounter += 1
                        case .text:
                            textInput = ""
                            pendingTextPoint = point
                        }
                    })
    }
```

Note: the imagePoint mapping composes two flips (SwiftUI top-left → CG bottom-left for output, then crop-local → base top-left). Verify by drawing an arrow in Step 4; if it lands mirrored, the fix is isolated to `imagePoint`.

- [x] **Step 3: Update the `open` call site**

In `AnnotationEditor.open(fileURL:)`, the `AnnotationEditorView(...)` call needs the new `settings` argument. The editor is opened from `AppDelegate`; thread an `AppSettings` through. Change `open` signature:

```swift
    static func open(fileURL: URL, settings: AppSettings) {
```

and the view construction:

```swift
        let view = AnnotationEditorView(
            base: base,
            settings: settings,
            onCopy: { flattened in copyToClipboard(flattened) },
            onSave: { flattened in
                if let data = CaptureDelivery.pngData(from: flattened) {
                    try? data.write(to: fileURL)
                }
                copyToClipboard(flattened)
                window?.close()
                window = nil
            })
```

Then update every `AnnotationEditor.open(fileURL:` call. Find them:

Run: `cd /Users/cmuir/Development/cliche && grep -rn "AnnotationEditor.open" Sources`

For each hit, pass the existing settings instance (AppDelegate already owns an `AppSettings`; use that property). Example edit: `AnnotationEditor.open(fileURL: url)` → `AnnotationEditor.open(fileURL: url, settings: settings)`.

- [x] **Step 4: Build and manually verify**

Run: `cd /Users/cmuir/Development/cliche && swift build 2>&1 | tail -8`
Expected: build succeeds (warnings OK).

Then run the app and exercise the editor:

Run: `cd /Users/cmuir/Development/cliche && make && open build/Cliche.app` (or the project's usual launch path from `Scripts/make-app.sh`).

Manually confirm:
1. Capture a region → editor opens with a live preview.
2. Pick a built-in preset (Indigo) → the gradient appears immediately in the canvas (not blind).
3. Drag Padding / Corner / Shadow sliders → preview updates live.
4. Switch Canvas to "X · 1600 × 900" → preview reframes to 16:9.
5. Draw an arrow over the screenshot → it lands on the screenshot content, not the padding.
6. Save → the written PNG matches the preview; reopen the editor → it remembers the last config.
7. Save a custom preset → it appears under "Yours"; relaunch → it persists.

- [x] **Step 5: Commit**

```bash
git add Sources/Cliche/BeautifyInspector.swift Sources/Cliche/AnnotationEditor.swift
git commit -m "feat(beautify): live inspector panel, composited preview, gesture remap"
```

---

### Task 5: Remove BeautifyStyle, migrate self-test, final verification

**Files:**
- Modify: `Sources/ClicheKit/BeautifyRenderer.swift` (delete `BeautifyStyle` and `apply(_:to:)`)
- Modify: `Sources/cliche-selftest/main.swift` (delete the old `// beautifyRenderer` block)

**Interfaces:**
- Consumes: the new renderer API (Tasks 1–2). No new production API.

- [x] **Step 1: Confirm no remaining consumers of the old API**

Run: `cd /Users/cmuir/Development/cliche && grep -rn "BeautifyStyle\|\.apply(" Sources | grep -i beautif`
Expected: only the definition in `BeautifyRenderer.swift` and the old test block in `main.swift` (both removed below). If any other consumer appears, migrate it to `BeautifyRenderer.render(_:to:)` first.

- [x] **Step 2: Delete the old enum and method**

In `Sources/ClicheKit/BeautifyRenderer.swift`, delete the entire `public enum BeautifyStyle { … }` declaration and the `public static func apply(_ style: BeautifyStyle, to image: CGImage) -> CGImage?` method. Keep `layout`, `sourceCrop`, `render`, and `drawGradient`.

In `Sources/cliche-selftest/main.swift`, delete the entire original `// beautifyRenderer` `do { … }` block (the one asserting `beautify .none leaves image untouched` and `beautify pads with gradient…`). The new `beautifyLayoutAndCrop` block from Task 2 replaces its coverage.

- [x] **Step 3: Build to verify it fails if anything still references the old API**

Run: `cd /Users/cmuir/Development/cliche && swift build 2>&1 | tail -8`
Expected: build succeeds. If it fails with `cannot find 'BeautifyStyle'`, a consumer was missed — migrate it to `render(_:to:)`.

- [x] **Step 4: Run the full self-test suite**

Run: `cd /Users/cmuir/Development/cliche && swift run cliche-selftest 2>&1 | tail -20; echo "exit: $?"`
Expected: every line `PASS`, final `exit: 0`. No `FAIL` lines.

- [x] **Step 5: Commit**

```bash
git add Sources/ClicheKit/BeautifyRenderer.swift Sources/cliche-selftest/main.swift
git commit -m "refactor(beautify): remove legacy BeautifyStyle enum, migrate self-tests"
```

---

## Self-Review

**1. Spec coverage:**
- §1 data model → Task 1 (all types, identity, built-ins). ✓
- §2 renderer (`layout`, `render`, auto-balance, fit-and-center) → Task 2. ✓
- §3 editor UI (inspector, live preview, gesture remap) → Task 4. ✓
- §4 presets & persistence → Task 3 (storage) + Task 4 (save/load UI). ✓
- §5 canvas sizes → Task 1 (`CanvasSize.socialPresets`) + Task 2 (fixed render) + Task 4 (menu). ✓
- §6 testing → Tasks 1–3 self-tests + Task 4 manual smoke + Task 5 full run. ✓
- Migration (remove `BeautifyStyle`, default identity) → Task 5 + Task 3 default. ✓

**2. Placeholder scan:** No TBD/TODO; every code step contains complete code. ✓

**3. Type consistency:** `BeautifyConfig`, `Gradient`, `RGBAColor`, `InsetFrame`, `Shadow`, `CanvasSize`, `NamedBeautifyConfig`, `BeautifyLayout`, and the `layout/sourceCrop/render` signatures are used identically across Tasks 1–5. `RGBAColor` uses positional init `RGBAColor(_:_:_:_:)` consistently. `AppSettings.decode/encode` helpers match their call sites. ✓

**Known follow-ups (out of scope, noted not silently dropped):**
- Multi-stop gradient editing UI (the model supports N stops; the inspector edits two). The renderer already honors N stops.
- Inset matte color is fixed white in the toggle; a color well can be added later.
