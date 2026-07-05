# Browser/Device Frames (C1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wrap captures in procedural presentation chrome — browser bar (light/dark, editable URL), macOS window bar, or generic phone/tablet bezel — inside the existing beautify pipeline with live preview.

**Architecture:** `FrameStyle` + two new `BeautifyConfig` fields (backward-compatible decoding). A new `FrameRenderer` computes `chromeInsets` and draws the chrome; `BeautifyRenderer.layout` adds the insets so the screenshot shifts inside the plate (gesture mapping keeps working for free), and `render` draws chrome between the matte and the screenshot. Inspector gains a Frame Style picker + URL field.

**Tech Stack:** Swift 6 (language mode v5), macOS 14+, Core Graphics, SwiftUI. Tests via `cliche-selftest`.

## Global Constraints

- Platform floor: macOS 14 (`.macOS(.v14)`); Swift language mode v5. No new dependencies.
- Model/render code in `ClicheKit`; UI in `Cliche`. Tests are `do { … expect(…) }` blocks in `Sources/cliche-selftest/main.swift`.
- **Backward compatibility:** persisted `BeautifyConfig` JSON without `frame`/`frameURL` keys MUST decode (defaults `.none`, `""`). Existing beautify selftests must keep passing unchanged.
- All chrome metrics are fractions of the screenshot's min dimension (consistent under the fixed-canvas uniform scale).

---

## File Structure

- **Modify** `Sources/ClicheKit/BeautifyConfig.swift` — `FrameStyle`, config fields, legacy decode, `isIdentity` (Task 1)
- **Create** `Sources/ClicheKit/FrameRenderer.swift` — insets + chrome drawing (Tasks 2–3)
- **Modify** `Sources/ClicheKit/BeautifyRenderer.swift` — layout insets + render hook (Tasks 2–3)
- **Modify** `Sources/Cliche/BeautifyInspector.swift` — Frame Style section (Task 4)
- **Modify** `README.md` — beautify bullet mentions frames (Task 4)
- **Modify** `Sources/cliche-selftest/main.swift` — test blocks (Tasks 1–3)

---

### Task 1: `FrameStyle` + config fields with legacy decoding

**Files:**
- Modify: `Sources/ClicheKit/BeautifyConfig.swift`
- Test: `Sources/cliche-selftest/main.swift`

**Interfaces:**
- Produces: `public enum FrameStyle: String, Codable, CaseIterable, Equatable { case none, browserLight, browserDark, macWindow, phone, tablet }` with `var label: String`, `var isBrowser: Bool`; `BeautifyConfig.frame: FrameStyle`, `BeautifyConfig.frameURL: String`; `isIdentity == background.isEmpty && frame == .none`.

- [ ] **Step 1: Write the failing test**

Append to `Sources/cliche-selftest/main.swift` (after the `// beautifyPersistence` block):

```swift
// frameStyleModel
do {
    let labels = FrameStyle.allCases.map(\.label)
    expect(FrameStyle.allCases.count == 6
        && Set(labels).count == labels.count && labels.allSatisfy { !$0.isEmpty },
        "six frame styles with unique labels")
    expect(FrameStyle.browserLight.isBrowser && FrameStyle.browserDark.isBrowser
        && !FrameStyle.macWindow.isBrowser && !FrameStyle.none.isBrowser,
        "isBrowser true exactly for browser styles")

    // Round-trip with frame fields.
    var cfg = BeautifyConfig.gradient(RGBAColor(1, 0, 0), RGBAColor(0, 0, 1))
    cfg.frame = .browserDark
    cfg.frameURL = "example.com"
    let data = try! JSONEncoder().encode(cfg)
    let decoded = try! JSONDecoder().decode(BeautifyConfig.self, from: data)
    expect(decoded == cfg && decoded.frame == .browserDark
        && decoded.frameURL == "example.com",
        "BeautifyConfig round-trips frame fields")

    // Legacy JSON without frame keys still decodes.
    var legacyDict = try! JSONSerialization.jsonObject(
        with: JSONEncoder().encode(BeautifyConfig.identity)) as! [String: Any]
    legacyDict.removeValue(forKey: "frame")
    legacyDict.removeValue(forKey: "frameURL")
    let legacyData = try! JSONSerialization.data(withJSONObject: legacyDict)
    let legacy = try? JSONDecoder().decode(BeautifyConfig.self, from: legacyData)
    expect(legacy?.frame == FrameStyle.none && legacy?.frameURL == "",
        "legacy config JSON without frame keys decodes with defaults")

    // Frame-only config is not identity.
    var frameOnly = BeautifyConfig.identity
    frameOnly.frame = .phone
    expect(!frameOnly.isIdentity && BeautifyConfig.identity.isIdentity,
        "frame-only config is not identity; plain identity still is")
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd /Users/cmuir/Development/cliche && swift build 2>&1 | grep error: | head -3`
Expected: `cannot find 'FrameStyle' in scope`

- [ ] **Step 3: Write minimal implementation**

In `Sources/ClicheKit/BeautifyConfig.swift`:

(a) Add above `BeautifyConfig`:

```swift
/// Presentation chrome drawn around the screenshot. All procedural —
/// no image assets; bezels are generic, not device replicas.
public enum FrameStyle: String, Codable, CaseIterable, Equatable {
    case none, browserLight, browserDark, macWindow, phone, tablet

    public var label: String {
        switch self {
        case .none: return "None"
        case .browserLight: return "Browser · Light"
        case .browserDark: return "Browser · Dark"
        case .macWindow: return "Mac Window"
        case .phone: return "Phone"
        case .tablet: return "Tablet"
        }
    }

    public var isBrowser: Bool { self == .browserLight || self == .browserDark }
}
```

(b) Add fields to `BeautifyConfig` (after `autoBalance`):

```swift
    public var frame: FrameStyle
    public var frameURL: String
```

(c) Extend the memberwise `init` with `frame: FrameStyle = .none, frameURL: String = ""` (defaulted, so existing call sites compile) and assign them.

(d) Change `isIdentity`:

```swift
    public var isIdentity: Bool { background.isEmpty && frame == .none }
```

(e) Add backward-compatible decoding (below the memberwise init):

```swift
    private enum CodingKeys: String, CodingKey {
        case background, padding, inset, cornerRadius, shadow, canvas,
             autoBalance, frame, frameURL
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        background = try c.decode(Gradient.self, forKey: .background)
        padding = try c.decode(Double.self, forKey: .padding)
        inset = try c.decodeIfPresent(InsetFrame.self, forKey: .inset)
        cornerRadius = try c.decode(Double.self, forKey: .cornerRadius)
        shadow = try c.decode(Shadow.self, forKey: .shadow)
        canvas = try c.decode(CanvasSize.self, forKey: .canvas)
        autoBalance = try c.decode(Bool.self, forKey: .autoBalance)
        // Added after 0.1.3 — older persisted configs lack these keys.
        frame = try c.decodeIfPresent(FrameStyle.self, forKey: .frame) ?? .none
        frameURL = try c.decodeIfPresent(String.self, forKey: .frameURL) ?? ""
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd /Users/cmuir/Development/cliche && swift run cliche-selftest 2>&1 | grep -iE "frame|legacy|FAIL"`
Expected: new lines `PASS`; zero `FAIL` anywhere (existing beautify tests unaffected).

- [ ] **Step 5: Commit**

```bash
git add Sources/ClicheKit/BeautifyConfig.swift Sources/cliche-selftest/main.swift
git commit -m "feat(frames): FrameStyle model with backward-compatible config decoding"
```

---

### Task 2: `chromeInsets` + layout integration

**Files:**
- Create: `Sources/ClicheKit/FrameRenderer.swift`
- Modify: `Sources/ClicheKit/BeautifyRenderer.swift` (`layout`)
- Test: `Sources/cliche-selftest/main.swift`

**Interfaces:**
- Consumes: `FrameStyle` (Task 1), `BeautifyRenderer.layout(_:croppedSize:)`.
- Produces: `FrameRenderer.chromeInsets(_ style: FrameStyle, minDimension: CGFloat) -> NSEdgeInsets`; `layout` output includes chrome insets.

- [ ] **Step 1: Write the failing test**

Append to `Sources/cliche-selftest/main.swift`:

```swift
// frameChromeInsets
do {
    let none = FrameRenderer.chromeInsets(.none, minDimension: 1000)
    expect(none.top == 0 && none.bottom == 0 && none.left == 0 && none.right == 0,
        "no chrome insets for FrameStyle.none")
    let bar = FrameRenderer.chromeInsets(.browserLight, minDimension: 1000)
    expect(bar.top == 55 && bar.bottom == 0 && bar.left == 0 && bar.right == 0,
        "browser bar is a top-only inset of 5.5% min dimension")
    let phone = FrameRenderer.chromeInsets(.phone, minDimension: 1000)
    expect(phone.top == 45 && phone.bottom == 45 && phone.left == 45 && phone.right == 45,
        "phone bezel is uniform 4.5% min dimension")

    // layout grows by exactly the chrome insets.
    var plain = BeautifyConfig.gradient(RGBAColor(0, 0, 1), RGBAColor(0, 1, 0))
    var framed = plain
    framed.frame = .browserLight
    let size = CGSize(width: 800, height: 600)
    let plainL = BeautifyRenderer.layout(plain, croppedSize: size)
    let framedL = BeautifyRenderer.layout(framed, croppedSize: size)
    let expectedBar = 0.055 * 600
    expect(abs(framedL.outputSize.height - plainL.outputSize.height - expectedBar) < 0.5
        && abs(framedL.outputSize.width - plainL.outputSize.width) < 0.5,
        "browser frame adds exactly the bar height to layout")
    expect(abs(framedL.screenshotRect.minY - plainL.screenshotRect.minY) < 0.5
        && abs(framedL.screenshotRect.width - plainL.screenshotRect.width) < 0.5,
        "screenshot keeps its position; bar space is added above")
    _ = plain; _ = framed
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd /Users/cmuir/Development/cliche && swift build 2>&1 | grep error: | head -3`
Expected: `cannot find 'FrameRenderer' in scope`

- [ ] **Step 3: Write minimal implementation**

Create `Sources/ClicheKit/FrameRenderer.swift`:

```swift
import AppKit

/// Procedural presentation chrome: browser/mac title bars and generic
/// device bezels, drawn straight into the beautify render context.
public enum FrameRenderer {
    /// Extra space the chrome needs around the screenshot, in pixels.
    public static func chromeInsets(
        _ style: FrameStyle, minDimension: CGFloat
    ) -> NSEdgeInsets {
        switch style {
        case .none:
            return NSEdgeInsets()
        case .browserLight, .browserDark, .macWindow:
            return NSEdgeInsets(top: 0.055 * minDimension, left: 0, bottom: 0, right: 0)
        case .phone:
            let b = 0.045 * minDimension
            return NSEdgeInsets(top: b, left: b, bottom: b, right: b)
        case .tablet:
            let b = 0.06 * minDimension
            return NSEdgeInsets(top: b, left: b, bottom: b, right: b)
        }
    }
}
```

In `Sources/ClicheKit/BeautifyRenderer.swift`, update `layout` — replace its body with:

```swift
    public static func layout(_ config: BeautifyConfig, croppedSize: CGSize) -> BeautifyLayout {
        let minDim = min(croppedSize.width, croppedSize.height)
        let pad = config.padding * minDim
        let insetW = (config.inset?.width ?? 0) * minDim
        let chrome = FrameRenderer.chromeInsets(config.frame, minDimension: minDim)
        let frameW = croppedSize.width + chrome.left + chrome.right + 2 * insetW
        let frameH = croppedSize.height + chrome.top + chrome.bottom + 2 * insetW
        let contentW = frameW + 2 * pad
        let contentH = frameH + 2 * pad

        switch config.canvas {
        case .free:
            let rect = CGRect(
                x: pad + insetW + chrome.left, y: pad + insetW + chrome.bottom,
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
                x: ox + (pad + insetW + chrome.left) * s,
                y: oy + (pad + insetW + chrome.bottom) * s,
                width: croppedSize.width * s, height: croppedSize.height * s)
            return BeautifyLayout(outputSize: canvas, screenshotRect: rect)
        }
    }
```

(Note: `screenshotRect.minY` is unchanged for a top-bar frame because the bar sits ABOVE the screenshot in CG's bottom-left coordinates — the height grows instead.)

- [ ] **Step 4: Run to verify it passes**

Run: `cd /Users/cmuir/Development/cliche && swift run cliche-selftest 2>&1 | grep -iE "chrome|bar height|bezel|FAIL"`
Expected: all new lines `PASS`, zero `FAIL` (existing layout tests still pass — chrome is zero for frameless configs).

- [ ] **Step 5: Commit**

```bash
git add Sources/ClicheKit/FrameRenderer.swift Sources/ClicheKit/BeautifyRenderer.swift Sources/cliche-selftest/main.swift
git commit -m "feat(frames): chrome insets and layout integration"
```

---

### Task 3: Chrome drawing + render integration

**Files:**
- Modify: `Sources/ClicheKit/FrameRenderer.swift` (add `draw`)
- Modify: `Sources/ClicheKit/BeautifyRenderer.swift` (`render`)
- Test: `Sources/cliche-selftest/main.swift`

**Interfaces:**
- Consumes: Task 2's `chromeInsets`, existing `render` internals (`platePath`, `shot`, `shotMin`).
- Produces: `FrameRenderer.draw(_ style: FrameStyle, urlText: String, plateRect: CGRect, screenshotRect: CGRect, cornerRadius: CGFloat, in ctx: CGContext)`.

- [ ] **Step 1: Write the failing test**

Append to `Sources/cliche-selftest/main.swift`:

```swift
// frameRendering
do {
    let w = 400, h = 300
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    let green = ctx.makeImage()!

    var cfg = BeautifyConfig.gradient(RGBAColor(0, 0, 1), RGBAColor(0, 0, 1))
    cfg.frame = .browserLight
    cfg.frameURL = "cliche.app"
    let out = BeautifyRenderer.render(cfg, to: green)!
    let expected = BeautifyRenderer.layout(cfg, croppedSize: CGSize(width: w, height: h))
    expect(out.width == Int(expected.outputSize.width.rounded())
        && out.height == Int(expected.outputSize.height.rounded()),
        "framed render matches layout dimensions")

    // Sample the middle of the browser bar: above the screenshot top,
    // horizontally centered — must be light chrome, not green screenshot
    // and not the blue gradient.
    let rep = NSBitmapImageRep(cgImage: out)
    let barMidYFromBottom = expected.screenshotRect.maxY
        + FrameRenderer.chromeInsets(.browserLight, minDimension: 300).top / 2
    let sampleY = out.height - Int(barMidYFromBottom)  // rep is top-left origin
    let color = rep.colorAt(x: out.width / 2, y: sampleY)!.usingColorSpace(.deviceRGB)!
    expect(color.greenComponent < 0.9 && color.blueComponent > 0.3
        && abs(color.redComponent - color.greenComponent) < 0.35,
        "browser bar pixels are chrome-gray, not screenshot or gradient")

    // Frame-only (no gradient) still renders enlarged output.
    var frameOnly = BeautifyConfig.identity
    frameOnly.frame = .phone
    let bezel = BeautifyRenderer.render(frameOnly, to: green)!
    expect(bezel.width > w && bezel.height > h,
        "frame-only config renders enlarged (not identity passthrough)")
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd /Users/cmuir/Development/cliche && swift build 2>&1 | grep error: | head -3`
Expected: `type 'FrameRenderer' has no member 'draw'`

- [ ] **Step 3: Write minimal implementation**

Add to `Sources/ClicheKit/FrameRenderer.swift` inside the enum:

```swift
    /// Draws the chrome for `style` around `screenshotRect`. `plateRect` is
    /// the screenshot expanded by `chromeInsets`; `cornerRadius` matches the
    /// beautify plate rounding so chrome corners align with the plate.
    public static func draw(
        _ style: FrameStyle, urlText: String,
        plateRect: CGRect, screenshotRect: CGRect,
        cornerRadius: CGFloat, in ctx: CGContext
    ) {
        guard style != .none else { return }
        let clip = CGPath(roundedRect: plateRect,
                          cornerWidth: cornerRadius, cornerHeight: cornerRadius,
                          transform: nil)
        ctx.saveGState()
        ctx.addPath(clip)
        ctx.clip()

        switch style {
        case .none:
            break
        case .browserLight, .browserDark, .macWindow:
            drawBar(style, urlText: urlText, plateRect: plateRect,
                    screenshotRect: screenshotRect, in: ctx)
        case .phone, .tablet:
            // Bezel: fill everything except the screenshot area.
            ctx.setFillColor(CGColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1))
            ctx.fill(plateRect)
            ctx.clear(screenshotRect)
            ctx.setFillColor(CGColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1))
            // Camera dot centered in the top bezel band.
            let bezelTop = plateRect.maxY - screenshotRect.maxY
            let r = max(2, bezelTop * 0.14)
            ctx.setFillColor(CGColor(red: 0.25, green: 0.25, blue: 0.28, alpha: 1))
            ctx.fillEllipse(in: CGRect(
                x: plateRect.midX - r, y: screenshotRect.maxY + bezelTop / 2 - r,
                width: r * 2, height: r * 2))
        }
        ctx.restoreGState()
    }

    private static func drawBar(
        _ style: FrameStyle, urlText: String,
        plateRect: CGRect, screenshotRect: CGRect, in ctx: CGContext
    ) {
        let barRect = CGRect(
            x: plateRect.minX, y: screenshotRect.maxY,
            width: plateRect.width, height: plateRect.maxY - screenshotRect.maxY)
        let dark = style == .browserDark
        let barColor = dark
            ? CGColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1)
            : CGColor(red: 0.925, green: 0.925, blue: 0.94, alpha: 1)
        ctx.setFillColor(barColor)
        ctx.fill(barRect)

        // Traffic lights.
        let r = barRect.height * 0.16
        let colors: [CGColor] = [
            CGColor(red: 1.0, green: 0.37, blue: 0.34, alpha: 1),
            CGColor(red: 1.0, green: 0.74, blue: 0.18, alpha: 1),
            CGColor(red: 0.16, green: 0.78, blue: 0.25, alpha: 1),
        ]
        for (i, color) in colors.enumerated() {
            ctx.setFillColor(color)
            ctx.fillEllipse(in: CGRect(
                x: barRect.minX + barRect.height * 0.45 + CGFloat(i) * r * 3.1,
                y: barRect.midY - r, width: r * 2, height: r * 2))
        }

        guard style.isBrowser else { return }
        // URL pill.
        let pillWidth = plateRect.width * 0.6
        let pillHeight = barRect.height * 0.58
        let pill = CGRect(
            x: barRect.midX - pillWidth / 2, y: barRect.midY - pillHeight / 2,
            width: pillWidth, height: pillHeight)
        ctx.setFillColor(dark
            ? CGColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1)
            : CGColor(gray: 1, alpha: 1))
        ctx.addPath(CGPath(roundedRect: pill, cornerWidth: pillHeight / 2,
                           cornerHeight: pillHeight / 2, transform: nil))
        ctx.fillPath()

        guard !urlText.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: pillHeight * 0.5),
            .foregroundColor: dark
                ? NSColor(calibratedWhite: 0.72, alpha: 1)
                : NSColor(calibratedWhite: 0.42, alpha: 1),
        ]
        let size = (urlText as NSString).size(withAttributes: attributes)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        (urlText as NSString).draw(
            at: CGPoint(x: pill.midX - size.width / 2, y: pill.midY - size.height / 2),
            withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }
```

In `Sources/ClicheKit/BeautifyRenderer.swift`, update `render`. After the inset-matte block and before the screenshot block, compute the chrome plate and draw the frame; the shadow/matte/clip paths switch from the bare screenshot rect to the chrome plate. Replace everything from `let shot = l.screenshotRect` down to the final `return ctx.makeImage()` with:

```swift
        let shot = l.screenshotRect
        let shotMin = min(shot.width, shot.height)
        let chrome = FrameRenderer.chromeInsets(config.frame, minDimension: shotMin)
        let chromePlate = CGRect(
            x: shot.minX - chrome.left, y: shot.minY - chrome.bottom,
            width: shot.width + chrome.left + chrome.right,
            height: shot.height + chrome.top + chrome.bottom)
        let cornerRadius = config.cornerRadius * shotMin
        let insetW = (config.inset?.width ?? 0) * shotMin
        let matte = chromePlate.insetBy(dx: -insetW, dy: -insetW)
        let plateRadius = cornerRadius + insetW
        let platePath = CGPath(roundedRect: matte,
                               cornerWidth: plateRadius, cornerHeight: plateRadius,
                               transform: nil)

        // Shadow cast by an opaque plate under the whole framed unit.
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

        // Inset matte fill (color band around the framed unit).
        if let inset = config.inset, insetW > 0 {
            ctx.saveGState()
            ctx.addPath(platePath)
            ctx.setFillColor(inset.color.cgColor)
            ctx.fillPath()
            ctx.restoreGState()
        }

        // Presentation chrome (browser/mac bar or device bezel).
        FrameRenderer.draw(config.frame, urlText: config.frameURL,
                           plateRect: chromePlate, screenshotRect: shot,
                           cornerRadius: cornerRadius, in: ctx)

        // Screenshot. Frameless: rounded to the plate corners. Framed:
        // square inside the chrome (the chrome plate carries the rounding).
        let shotPath = config.frame == .none
            ? CGPath(roundedRect: shot, cornerWidth: cornerRadius,
                     cornerHeight: cornerRadius, transform: nil)
            : CGPath(roundedRect: chromePlate, cornerWidth: cornerRadius,
                     cornerHeight: cornerRadius, transform: nil)
        ctx.saveGState()
        ctx.addPath(shotPath)
        ctx.clip()
        ctx.draw(cropped, in: shot)
        ctx.restoreGState()

        return ctx.makeImage()
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd /Users/cmuir/Development/cliche && swift run cliche-selftest 2>&1 | grep -iE "framed|chrome-gray|enlarged|FAIL"; swift run cliche-selftest >/dev/null 2>&1; echo exit=$?`
Expected: new lines `PASS`, `exit=0` (all existing beautify tests still pass).

- [ ] **Step 5: Commit**

```bash
git add Sources/ClicheKit/FrameRenderer.swift Sources/ClicheKit/BeautifyRenderer.swift Sources/cliche-selftest/main.swift
git commit -m "feat(frames): procedural chrome drawing wired into beautify render"
```

---

### Task 4: Inspector UI, docs, verification

**Files:**
- Modify: `Sources/Cliche/BeautifyInspector.swift`
- Modify: `README.md`

**Interfaces:**
- Consumes: `FrameStyle` (Task 1), `$config.frame`, `$config.frameURL`.

- [ ] **Step 1: Add the Frame Style section**

In `Sources/Cliche/BeautifyInspector.swift`, add to the `body` VStack between `backgroundSection` and `frameSection`: `Divider()` + `frameStyleSection`, and add the section view:

```swift
    private var frameStyleSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("FRAME STYLE").sectionLabel()
            Picker("", selection: $config.frame) {
                ForEach(FrameStyle.allCases, id: \.self) { style in
                    Text(style.label).tag(style)
                }
            }
            .labelsHidden()
            if config.frame.isBrowser {
                TextField("example.com", text: $config.frameURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            }
        }
    }
```

- [ ] **Step 2: Update README**

In `README.md`, extend the Beautify bullet: after "optional matte border;" insert "**browser/device frames** — Safari-style bar (light/dark) with editable URL, Mac window bar, or phone/tablet bezel;".

- [ ] **Step 3: Full verification**

Run: `cd /Users/cmuir/Development/cliche && swift run cliche-selftest >/dev/null 2>&1; echo exit=$?; make app 2>&1 | tail -1`
Expected: `exit=0`, `Built build/Cliche.app`.

Render a visual proof through the real pipeline (temporary snippet, delete after inspection) and eyeball: browser bar with traffic lights + URL pill above the screenshot on the gradient.

Manual: open the annotation editor, pick each frame style, type a URL, confirm live preview + Save output + annotations landing on content.

- [ ] **Step 4: Commit**

```bash
git add Sources/Cliche/BeautifyInspector.swift README.md
git commit -m "feat(frames): inspector frame-style picker with URL field; README"
```

---

## Self-Review

**1. Spec coverage:** model+legacy decode → Task 1; chromeInsets+layout → Task 2; drawing+render → Task 3; inspector+URL field+README → Task 4; isIdentity change → Task 1; corner-rounding rule (plate carries rounding when framed) → Task 3. ✓
**2. Placeholder scan:** none. ✓
**3. Type consistency:** `FrameStyle`, `chromeInsets(_:minDimension:) -> NSEdgeInsets`, `draw(_:urlText:plateRect:screenshotRect:cornerRadius:in:)`, `config.frame`/`config.frameURL` used identically throughout. ✓
